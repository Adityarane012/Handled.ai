"""
Team members and role enforcement — "junior drafts, senior approves".

Staff can trigger tools but never decide; department heads and the owner can.
Only the owner adds people, only into their own company, and every action row
names who triggered it so the owner sees staff work in History.
"""
import uuid

import pytest

PW = "member-pass-123"


def _add(client, headers, role, name="Member"):
    email = f"m-{uuid.uuid4().hex[:10]}@handled.test"
    r = client.post("/company/users", json={
        "name": name, "email": email, "password": PW, "role": role,
    }, headers=headers)
    return r, email


def _login(client, email):
    tok = client.post("/auth/login", json={"email": email, "password": PW}).json()["access_token"]
    return {"Authorization": f"Bearer {tok}"}


def _pending_po(client, headers):
    return client.post("/ops/purchase-order",
                       json={"item_name": "Gasket", "current_stock": 4}, headers=headers).json()["id"]


APPROVE = {"decision": "approved", "manual_fields": {"quantity": 5, "amount": 100.0}}


def test_owner_adds_members_who_can_log_in(client, make_company):
    co = make_company()
    r, email = _add(client, co["headers"], "staff", "Amit Patil")
    assert r.status_code == 200, r.text
    assert r.json()["role"] == "staff"

    me = client.get("/auth/me", headers=_login(client, email)).json()
    assert me["company_id"] == co["company_id"]
    assert (me["role"], me["can_approve"], me["can_manage_team"]) == ("staff", False, False)

    team = client.get("/company/users", headers=co["headers"]).json()
    assert {m["role"] for m in team} == {"owner_admin", "staff"}


def test_owner_permissions_reported(client, make_company):
    co = make_company()
    me = client.get("/auth/me", headers=co["headers"]).json()
    assert (me["can_approve"], me["can_manage_team"]) == (True, True)


@pytest.mark.parametrize("decision", [APPROVE, {"decision": "rejected"}])
def test_staff_can_draft_but_not_decide(client, make_company, admin_conn, decision):
    co = make_company()
    _, email = _add(client, co["headers"], "staff")
    staff = _login(client, email)

    pid = _pending_po(client, staff)            # staff may trigger the tool...
    r = client.post("/ops/approve", json={"action_id": pid, **decision}, headers=staff)
    assert r.status_code == 403                 # ...but not decide it

    from sqlalchemy import text
    status = admin_conn.execute(text("SELECT status FROM agent_action WHERE id = :i"),
                                {"i": pid}).scalar()
    assert status == "pending_approval"


def test_department_head_can_approve_staff_draft(client, make_company):
    co = make_company()
    _, s_email = _add(client, co["headers"], "staff", "Amit Patil")
    _, h_email = _add(client, co["headers"], "department_head", "Neha Kulkarni")
    staff, head = _login(client, s_email), _login(client, h_email)

    pid = _pending_po(client, staff)
    r = client.post("/ops/approve", json={"action_id": pid, **APPROVE}, headers=head)
    assert r.status_code == 200, r.text

    # The owner sees both names on the row — who drafted it, who decided it.
    row = next(h for h in client.get("/ops/history", headers=co["headers"]).json() if h["id"] == pid)
    assert (row["requested_by_name"], row["approved_by_name"]) == ("Amit Patil", "Neha Kulkarni")
    pending = client.get("/ops/approvals", headers=co["headers"]).json()
    assert all(p["id"] != pid for p in pending)


def test_pending_queue_names_the_requester(client, make_company):
    co = make_company()
    _, email = _add(client, co["headers"], "staff", "Amit Patil")
    pid = _pending_po(client, _login(client, email))
    card = next(p for p in client.get("/ops/approvals", headers=co["headers"]).json() if p["id"] == pid)
    assert card["requested_by_name"] == "Amit Patil"


@pytest.mark.parametrize("role", ["staff", "department_head"])
def test_only_owner_can_add_members(client, make_company, role):
    co = make_company()
    _, email = _add(client, co["headers"], role)
    r, _ = _add(client, _login(client, email), "staff")
    assert r.status_code == 403


def test_cannot_create_a_second_owner(client, make_company):
    co = make_company()
    r, _ = _add(client, co["headers"], "owner_admin")
    assert r.status_code == 422


def test_duplicate_email_is_a_clean_400(client, make_company):
    co = make_company()
    r = client.post("/company/users", json={
        "name": "Dup", "email": co["owner_email"], "password": PW, "role": "staff",
    }, headers=co["headers"])
    assert r.status_code == 400


def test_members_are_scoped_to_their_company(client, make_company):
    a, b = make_company(), make_company()
    _, email = _add(client, a["headers"], "staff")
    staff_a = _login(client, email)

    # A's staff member lives in A — B's owner can't see them...
    assert all(m["email"] != email for m in client.get("/company/users", headers=b["headers"]).json())
    # ...and can't touch B's approvals.
    pid_b = _pending_po(client, b["headers"])
    assert client.get("/ops/approvals", headers=staff_a).json() == []
    head_email = _add(client, a["headers"], "department_head")[1]
    r = client.post("/ops/approve", json={"action_id": pid_b, **APPROVE},
                    headers=_login(client, head_email))
    assert r.status_code == 404
