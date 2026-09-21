"""
Phase 3.3 — audit-log integrity.

Every tool call writes a permanent agent_action row regardless of bucket, and
reject/edit never delete or overwrite the original draft.
"""
import pytest
from sqlalchemy import text


def _rows(admin_conn, company_id):
    return admin_conn.execute(text(
        "SELECT tool_name, action_type, status, draft_output, final_output "
        "FROM agent_action WHERE company_id = :c ORDER BY created_at"
    ), {"c": company_id}).fetchall()


def test_decision_note_is_recorded_for_both_outcomes(client, make_company):
    """
    "Rejected" alone is a weak audit record. The reason the human gave is kept
    permanently alongside the action, for approvals as well as rejections.
    """
    co = make_company()
    H = co["headers"]

    rejected = client.post("/ops/purchase-order",
                           json={"item_name": "Bolt", "current_stock": 2}, headers=H).json()["id"]
    client.post("/ops/approve", json={
        "action_id": rejected, "decision": "rejected",
        "note": "  Vendor not approved this quarter - use Nandi instead.  ",
    }, headers=H)

    approved = client.post("/ops/purchase-order",
                           json={"item_name": "Nut", "current_stock": 1}, headers=H).json()["id"]
    client.post("/ops/approve", json={
        "action_id": approved, "decision": "approved",
        "manual_fields": {"quantity": 10, "amount": 500.0},
        "note": "Price confirmed by phone.",
    }, headers=H)

    by_id = {r["id"]: r for r in client.get("/ops/history", headers=H).json()}
    # Stored trimmed, and reaches the client that renders the trail.
    assert by_id[rejected]["decision_note"] == "Vendor not approved this quarter - use Nandi instead."
    assert by_id[approved]["decision_note"] == "Price confirmed by phone."


def test_decision_note_is_optional_and_blank_is_not_stored(client, make_company):
    """A decision is never blocked on writing a note — it just stays null."""
    co = make_company()
    H = co["headers"]

    no_note = client.post("/ops/purchase-order",
                          json={"item_name": "Washer", "current_stock": 4}, headers=H).json()["id"]
    r = client.post("/ops/approve", json={"action_id": no_note, "decision": "rejected"}, headers=H)
    assert r.status_code == 200

    blank = client.post("/ops/purchase-order",
                        json={"item_name": "Gasket", "current_stock": 4}, headers=H).json()["id"]
    client.post("/ops/approve", json={
        "action_id": blank, "decision": "rejected", "note": "   ",
    }, headers=H)

    by_id = {r["id"]: r for r in client.get("/ops/history", headers=H).json()}
    assert by_id[no_note]["decision_note"] is None
    # Whitespace-only is not a reason; don't pretend one was given.
    assert by_id[blank]["decision_note"] is None


def test_stats_counts_buckets_and_decision_rates(client, make_company):
    co = make_company()
    H = co["headers"]

    client.post("/ops/status-summary", json={}, headers=H)   # auto
    client.post("/ops/vendor-status", json={                  # template_restricted
        "vendor_name": "Acme", "template_key": "delivery_confirmed_v1",
        "details": {"vendor_name": "Acme", "order_ref": "1", "delivery_date": "2026-09-01", "company_name": "Co"},
    }, headers=H)
    approved = client.post("/ops/purchase-order",             # approval -> approved
                           json={"item_name": "Bolt", "current_stock": 2}, headers=H).json()["id"]
    client.post("/ops/approve", json={
        "action_id": approved, "decision": "approved",
        "manual_fields": {"quantity": 5, "amount": 100.0},
    }, headers=H)
    rejected = client.post("/ops/workflow-exception",         # approval -> rejected
                           json={"request_description": "x", "justification": "y"}, headers=H).json()["id"]
    client.post("/ops/approve", json={"action_id": rejected, "decision": "rejected"}, headers=H)
    client.post("/ops/purchase-order",                        # approval -> left pending
                json={"item_name": "Nut", "current_stock": 1}, headers=H)

    s = client.get("/ops/stats", headers=H).json()
    assert s["total_actions"] == 5
    assert s["by_bucket"] == {"auto": 1, "template_restricted": 1, "approval_required": 3}
    assert s["approved"] == 1 and s["rejected"] == 1 and s["pending_approval"] == 1
    # 2 of 5 actions never needed a human
    assert s["hands_off_rate"] == 0.4
    # of the 2 decisions actually made, 1 was a rejection
    assert s["rejection_rate"] == 0.5


def test_stats_are_null_not_zero_when_there_is_no_data(client, make_company):
    """A fresh company should read '—', not a misleading 0%."""
    s = client.get("/ops/stats", headers=make_company()["headers"]).json()
    assert s["total_actions"] == 0
    assert s["hands_off_rate"] is None
    assert s["rejection_rate"] is None


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


@pytest.mark.parametrize("fields", [
    {"quantity": 0, "amount": 0},
    {"quantity": 10, "amount": 0},
    {"quantity": -5, "amount": 500.0},
    {"quantity": "abc", "amount": 500.0},
    {"quantity": True, "amount": 500.0},
    {"quantity": 2.5, "amount": 500.0},
    {"quantity": 10, "amount": None},
    {"quantity": 10, "amount": "500"},
])
def test_approve_rejects_unusable_po_figures(client, make_company, admin_conn, fields):
    # The app gates the button on manualFiguresAreUsable(), but the API is the
    # rule: a direct call with a zero/garbage figure must not execute a PO.
    co = make_company()
    H = co["headers"]
    pid = client.post("/ops/purchase-order",
                      json={"item_name": "Gasket", "current_stock": 4}, headers=H).json()["id"]

    r = client.post("/ops/approve", json={
        "action_id": pid, "decision": "approved", "manual_fields": fields,
    }, headers=H)

    assert r.status_code == 400
    status = admin_conn.execute(text(
        "SELECT status FROM agent_action WHERE id = :i"), {"i": pid}).scalar()
    assert status == "pending_approval"


def test_approve_cannot_overwrite_draft_via_manual_fields(client, make_company, admin_conn):
    co = make_company()
    H = co["headers"]
    pid = client.post("/ops/purchase-order",
                      json={"item_name": "Gasket", "current_stock": 4}, headers=H).json()["id"]
    agent_output = admin_conn.execute(text(
        "SELECT draft_output->>'agent_output' FROM agent_action WHERE id = :i"), {"i": pid}).scalar()

    client.post("/ops/approve", json={
        "action_id": pid, "decision": "approved",
        "manual_fields": {"quantity": 5, "amount": 100.0, "agent_output": "forged"},
    }, headers=H)

    final = admin_conn.execute(text(
        "SELECT final_output FROM agent_action WHERE id = :i"), {"i": pid}).scalar()
    assert final["agent_output"] == agent_output


def test_approved_at_is_not_before_created_at(client, make_company, admin_conn):
    # A naive datetime.utcnow() was read as the DB's local zone (IST), filing
    # approvals 5.5h *before* the action they approved.
    co = make_company()
    H = co["headers"]
    pid = client.post("/ops/purchase-order",
                      json={"item_name": "Gasket", "current_stock": 4}, headers=H).json()["id"]
    client.post("/ops/approve", json={
        "action_id": pid, "decision": "approved",
        "manual_fields": {"quantity": 5, "amount": 100.0},
    }, headers=H)

    created, approved = admin_conn.execute(text(
        "SELECT created_at, approved_at FROM agent_action WHERE id = :i"), {"i": pid}).fetchone()
    assert approved >= created


def test_concurrent_decisions_cannot_both_succeed(client, make_company, admin_conn):
    # Two people deciding the same action at the same moment: exactly one may
    # win. Before the row lock, both returned 200 and the second silently
    # overwrote the first — once leaving a row 'rejected' that still carried
    # an approved quantity.
    import threading

    co = make_company()
    H = co["headers"]
    for _ in range(5):
        pid = client.post("/ops/purchase-order",
                          json={"item_name": "Gasket", "current_stock": 4}, headers=H).json()["id"]
        bodies = [
            {"action_id": pid, "decision": "approved",
             "manual_fields": {"quantity": 10, "amount": 100.0}, "note": "approver"},
            {"action_id": pid, "decision": "rejected", "note": "rejecter"},
        ]
        codes = [None, None]
        barrier = threading.Barrier(2)

        def decide(i):
            barrier.wait()
            codes[i] = client.post("/ops/approve", json=bodies[i], headers=H).status_code

        threads = [threading.Thread(target=decide, args=(i,)) for i in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert sorted(codes) == [200, 400]
        status, note, final = admin_conn.execute(text(
            "SELECT status, decision_note, final_output FROM agent_action WHERE id = :i"),
            {"i": pid}).fetchone()
        winner = codes.index(200)
        # The stored row is entirely the winner's decision — nothing mixed in.
        if winner == 0:
            assert (status, note) == ("executed", "approver") and final["quantity"] == 10
        else:
            assert (status, note, final) == ("rejected", "rejecter", None)
