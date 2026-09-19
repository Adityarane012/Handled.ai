"""
Phase 3.3 — audit-log integrity.

Every tool call writes a permanent agent_action row regardless of bucket, and
reject/edit never delete or overwrite the original draft.
"""
from sqlalchemy import text


def _rows(admin_conn, company_id):
    return admin_conn.execute(text(
        "SELECT tool_name, action_type, status, draft_output, final_output "
        "FROM agent_action WHERE company_id = :c ORDER BY created_at"
    ), {"c": company_id}).fetchall()


def test_history_returns_every_bucket_and_status(client, make_company, admin_conn):
    co = make_company()
    H = co["headers"]

    client.post("/ops/status-summary", json={}, headers=H)  # auto
    client.post("/ops/vendor-status", json={                 # template_restricted
        "vendor_name": "Acme", "template_key": "delivery_confirmed_v1",
        "details": {"vendor_name": "Acme", "order_ref": "1", "delivery_date": "2026-09-01", "company_name": "Co"},
    }, headers=H)
    pid = client.post("/ops/purchase-order",                 # approval_required
                       json={"item_name": "Bolt", "current_stock": 2}, headers=H).json()["id"]
    client.post("/ops/approve", json={
        "action_id": pid, "decision": "approved",
        "manual_fields": {"quantity": 5, "amount": 999.0},
    }, headers=H)

    history = client.get("/ops/history", headers=H).json()
    tools = {row["tool_name"] for row in history}
    assert tools == {"ops_status_summary", "vendor_status_update", "purchase_order_approval"}
    statuses = {row["tool_name"]: row["status"] for row in history}
    assert statuses["ops_status_summary"] == "auto_executed"
    assert statuses["vendor_status_update"] == "auto_executed"
    assert statuses["purchase_order_approval"] == "executed"
    # newest first
    assert history == sorted(history, key=lambda r: r["created_at"], reverse=True)


def test_every_tool_writes_one_agent_action_row(client, make_company, admin_conn):
    co = make_company()
    H = co["headers"]

    client.post("/ops/status-summary", json={}, headers=H)
    client.post("/ops/inventory-upload", json={"doc_text": "SKU A | on_hand 5"}, headers=H)
    client.post("/ops/inventory-qa", json={"question": "how many A?"}, headers=H)
    client.post("/ops/vendor-status", json={
        "vendor_name": "Acme", "template_key": "delivery_confirmed_v1",
        "details": {"vendor_name": "Acme", "order_ref": "1", "delivery_date": "2026-09-01", "company_name": "Co"},
    }, headers=H)
    client.post("/ops/purchase-order", json={"item_name": "Bolt", "current_stock": 2}, headers=H)
    client.post("/ops/workflow-exception", json={
        "request_description": "air freight", "justification": "deadline",
    }, headers=H)

    rows = _rows(admin_conn, co["company_id"])
    tools = [r[0] for r in rows]
    # inventory-upload does NOT create an agent_action (it only indexes) — 5 tool calls
    assert tools.count("ops_status_summary") == 1
    assert tools.count("inventory_qa") == 1
    assert tools.count("vendor_status_update") == 1
    assert tools.count("purchase_order_approval") == 1
    assert tools.count("workflow_exception_approval") == 1
    assert len(rows) == 5


def test_bucket_to_status_mapping(client, make_company, admin_conn):
    co = make_company()
    H = co["headers"]
    client.post("/ops/status-summary", json={}, headers=H)          # auto
    client.post("/ops/vendor-status", json={                         # template_restricted
        "vendor_name": "Acme", "template_key": "delivery_confirmed_v1",
        "details": {"vendor_name": "Acme", "order_ref": "1", "delivery_date": "2026-09-01", "company_name": "Co"},
    }, headers=H)
    client.post("/ops/purchase-order", json={"item_name": "Bolt", "current_stock": 2}, headers=H)  # approval

    by_tool = {r[0]: r for r in _rows(admin_conn, co["company_id"])}
    assert by_tool["ops_status_summary"][2] == "auto_executed"
    assert by_tool["vendor_status_update"][2] == "auto_executed"
    assert by_tool["purchase_order_approval"][2] == "pending_approval"


def test_reject_retains_row_and_preserves_draft(client, make_company, admin_conn):
    co = make_company()
    H = co["headers"]
    pid = client.post("/ops/purchase-order",
                      json={"item_name": "Nut", "current_stock": 1}, headers=H).json()["id"]
    before = admin_conn.execute(text(
        "SELECT draft_output FROM agent_action WHERE id = :i"), {"i": pid}).scalar()

    r = client.post("/ops/approve", json={"action_id": pid, "decision": "rejected"}, headers=H)
    assert r.status_code == 200 and r.json()["status"] == "rejected"

    after = admin_conn.execute(text(
        "SELECT status, draft_output, final_output FROM agent_action WHERE id = :i"),
        {"i": pid}).fetchone()
    assert after is not None                      # not deleted
    assert after[0] == "rejected"
    assert after[1] == before                     # draft untouched
    assert after[2] is None                       # nothing "executed"


def test_approve_merges_manual_fields_without_losing_draft(client, make_company, admin_conn):
    co = make_company()
    H = co["headers"]
    pid = client.post("/ops/purchase-order",
                      json={"item_name": "Gasket", "current_stock": 4}, headers=H).json()["id"]
    draft_before = admin_conn.execute(text(
        "SELECT draft_output FROM agent_action WHERE id = :i"), {"i": pid}).scalar()

    client.post("/ops/approve", json={
        "action_id": pid, "decision": "approved",
        "manual_fields": {"quantity": 250, "amount": 9999.5},
    }, headers=H)

    row = admin_conn.execute(text(
        "SELECT status, draft_output, final_output FROM agent_action WHERE id = :i"),
        {"i": pid}).fetchone()
    assert row[0] == "executed"
    assert row[1] == draft_before                      # draft still intact
    assert row[2]["quantity"] == 250                   # human's numbers recorded
    assert row[2]["amount"] == 9999.5
    # the AI's justification carried into final_output too
    assert "agent_output" in row[2]
