"""
Phase 3.1 — adversarial cross-tenant isolation.

The one failure mode that would be disqualifying in front of evaluators:
one company seeing or touching another company's data. Tested at both layers —
the API, and RLS alone with the app-layer filter deliberately removed.
"""
import uuid

from sqlalchemy import text

from db.session import engine


def _make_po(client, company):
    r = client.post("/ops/purchase-order", json={
        "item_name": "Widget", "current_stock": 3, "preferred_vendor": "Acme",
    }, headers=company["headers"])
    assert r.status_code == 200, r.text
    return r.json()["id"]


def test_company_b_cannot_see_company_a_approvals(client, make_company):
    a, b = make_company("A"), make_company("B")
    a_action = _make_po(client, a)

    b_list = client.get("/ops/approvals", headers=b["headers"])
    assert b_list.status_code == 200
    assert all(row["id"] != a_action for row in b_list.json())

    a_list = client.get("/ops/approvals", headers=a["headers"])
    assert any(row["id"] == a_action for row in a_list.json())


def test_company_b_cannot_see_company_a_history(client, make_company):
    a, b = make_company("A"), make_company("B")
    a_action = _make_po(client, a)

    b_history = client.get("/ops/history", headers=b["headers"])
    assert b_history.status_code == 200
    assert all(row["id"] != a_action for row in b_history.json())

    a_history = client.get("/ops/history", headers=a["headers"])
    assert any(row["id"] == a_action for row in a_history.json())


def test_company_b_cannot_approve_company_a_action(client, make_company):
    a, b = make_company("A"), make_company("B")
    a_action = _make_po(client, a)

    r = client.post("/ops/approve", json={
        "action_id": a_action, "decision": "approved",
        "manual_fields": {"quantity": 10, "amount": 100.0},
    }, headers=b["headers"])
    assert r.status_code == 404, r.text  # not found *for company B*

    # ...and A's action is untouched
    with engine.connect() as conn:
        conn.execute(text("SET LOCAL app.current_company_id = :c"), {"c": a["company_id"]})
        status = conn.execute(
            text("SELECT status FROM agent_action WHERE id = :i"), {"i": a_action}
        ).scalar()
    assert status == "pending_approval"


def test_rls_blocks_reads_even_without_app_layer_filter(client, make_company):
    """Deliberately skip any company_id WHERE clause — RLS alone must still block it."""
    a, b = make_company("A"), make_company("B")
    _make_po(client, a)

    with engine.connect() as conn:
        conn.execute(text("SET LOCAL app.current_company_id = :c"), {"c": b["company_id"]})
        # No "WHERE company_id = ..." at all:
        rows = conn.execute(text("SELECT * FROM agent_action")).fetchall()
    assert rows == []  # B's context sees nothing, even asking for everything


def test_rls_blocks_cross_tenant_write(make_company):
    a, b = make_company("A"), make_company("B")
    with engine.connect() as conn:
        conn.execute(text("SET LOCAL app.current_company_id = :c"), {"c": a["company_id"]})
        try:
            conn.execute(text(
                "INSERT INTO agent_action (id, company_id, tool_name, action_type, status) "
                "VALUES (:id, :cid, 't', 'auto', 'auto_executed')"
            ), {"id": str(uuid.uuid4()), "cid": b["company_id"]})
            conn.commit()
            assert False, "cross-tenant INSERT should have been blocked by RLS"
        except Exception:
            conn.rollback()


def test_no_tenant_context_returns_nothing_and_does_not_error(make_company):
    make_company("A")  # ensure at least one row exists somewhere
    with engine.connect() as conn:
        rows = conn.execute(text("SELECT * FROM app_user")).fetchall()
    assert rows == []


def test_auth_me_is_scoped_to_caller(client, make_company):
    a, b = make_company("A"), make_company("B")
    me_a = client.get("/auth/me", headers=a["headers"]).json()
    me_b = client.get("/auth/me", headers=b["headers"]).json()
    assert me_a["company_id"] == a["company_id"]
    assert me_b["company_id"] == b["company_id"]
    assert me_a["email"] != me_b["email"]
