"""
Manual RLS verification for handled.ai — Build Guide Week 1, Step 6.
Prove cross-tenant isolation with raw SQL, no app/ORM code involved.

Design (matches the Phase 1B role split):
  - FIXTURES + CLEANUP run on the admin/superuser connection (`admin_engine`).
    Superusers bypass RLS — that's the correct way to seed test data.
  - ISOLATION ASSERTIONS run on the runtime connection (`engine`, role
    `handled_app`), which RLS actually governs, with `SET LOCAL
    app.current_company_id` as the per-transaction tenant context.

Run after init_db.py:  python test_rls_manual.py
"""
import sys
import os
import uuid

sys.path.insert(0, os.path.dirname(__file__))

from sqlalchemy import text
from db.session import engine, admin_engine

PASS, FAIL = "PASS", "FAIL"
_failed = []


def _log(tag, msg):
    if tag == FAIL:
        _failed.append(msg)
    print(f"  [{tag}] {msg}")


def _count(conn, sql, **params):
    return len(conn.execute(text(sql), params).fetchall())


def test_rls() -> bool:
    a, b = str(uuid.uuid4()), str(uuid.uuid4())

    # ─── Fixtures (admin: RLS bypassed) ──────────────────────────────────
    with admin_engine.begin() as adm:
        for cid, cname, uname in [(a, "RLS Co A", "Alice"), (b, "RLS Co B", "Bob")]:
            adm.execute(text("INSERT INTO company (id, name) VALUES (:id, :n)"),
                        {"id": cid, "n": cname})
            adm.execute(text(
                "INSERT INTO app_user (id, company_id, name, email, password_hash, role) "
                "VALUES (:id, :cid, :n, :e, 'x', 'owner_admin')"),
                {"id": str(uuid.uuid4()), "cid": cid, "n": uname,
                 "e": f"{uname.lower()}-{uuid.uuid4().hex[:8]}@rls.test"})
            adm.execute(text("INSERT INTO department (id, company_id, type) VALUES (:id, :cid, 'ops')"),
                        {"id": str(uuid.uuid4()), "cid": cid})
            adm.execute(text(
                "INSERT INTO agent_action (id, company_id, tool_name, action_type, status) "
                "VALUES (:id, :cid, 'ops_status_summary', 'auto', 'auto_executed')"),
                {"id": str(uuid.uuid4()), "cid": cid})

    try:
        # ─── Assertions (runtime role: RLS enforced) ─────────────────────
        with engine.connect() as conn:
            # 1. context A -> cannot see B's users
            conn.execute(text("SET LOCAL app.current_company_id = :c"), {"c": a})
            _log(PASS if _count(conn, "SELECT * FROM app_user WHERE company_id = :c", c=b) == 0
                 else FAIL, "context A: B's app_user rows -> 0")
            conn.rollback()

            # 2. context B -> cannot see A's users
            conn.execute(text("SET LOCAL app.current_company_id = :c"), {"c": b})
            _log(PASS if _count(conn, "SELECT * FROM app_user WHERE company_id = :c", c=a) == 0
                 else FAIL, "context B: A's app_user rows -> 0")
            conn.rollback()

            # 3. context A -> sees its own user (positive control)
            conn.execute(text("SET LOCAL app.current_company_id = :c"), {"c": a})
            _log(PASS if _count(conn, "SELECT * FROM app_user WHERE company_id = :c", c=a) == 1
                 else FAIL, "context A: A's own app_user rows -> 1")
            conn.rollback()

            # 4. context A -> cannot see B's departments
            conn.execute(text("SET LOCAL app.current_company_id = :c"), {"c": a})
            _log(PASS if _count(conn, "SELECT * FROM department WHERE company_id = :c", c=b) == 0
                 else FAIL, "context A: B's department rows -> 0")
            conn.rollback()

            # 5. context A -> cannot see B's agent_action rows (the audit table)
            conn.execute(text("SET LOCAL app.current_company_id = :c"), {"c": a})
            _log(PASS if _count(conn, "SELECT * FROM agent_action WHERE company_id = :c", c=b) == 0
                 else FAIL, "context A: B's agent_action rows -> 0")
            conn.rollback()

            # 6. no context set -> zero rows, and NO error (NULLIF hardening)
            try:
                n = _count(conn, "SELECT * FROM app_user")
                _log(PASS if n == 0 else FAIL, f"no tenant context: app_user rows -> 0 (got {n})")
            except Exception as e:  # noqa: BLE001
                _log(FAIL, f"no tenant context raised instead of returning 0 rows: {e}")
            conn.rollback()

            # 7. runtime role cannot INSERT a row for a tenant it isn't scoped to
            conn.execute(text("SET LOCAL app.current_company_id = :c"), {"c": a})
            try:
                conn.execute(text(
                    "INSERT INTO agent_action (id, company_id, tool_name, action_type, status) "
                    "VALUES (:id, :cid, 't', 'auto', 'auto_executed')"),
                    {"id": str(uuid.uuid4()), "cid": b})
                _log(FAIL, "cross-tenant INSERT was allowed (should be blocked by RLS WITH CHECK)")
            except Exception:
                _log(PASS, "cross-tenant INSERT blocked by RLS")
            conn.rollback()
    finally:
        # ─── Cleanup (admin) ────────────────────────────────────────────
        with admin_engine.begin() as adm:
            for cid in (a, b):
                adm.execute(text("DELETE FROM agent_action WHERE company_id = :c"), {"c": cid})
                adm.execute(text("DELETE FROM app_user WHERE company_id = :c"), {"c": cid})
                adm.execute(text("DELETE FROM department WHERE company_id = :c"), {"c": cid})
                adm.execute(text("DELETE FROM company WHERE id = :c"), {"c": cid})

    if _failed:
        print(f"\nRESULT: {len(_failed)} FAILED")
        return False
    print("\nRESULT: all RLS isolation checks passed — tenant isolation confirmed.")
    return True


if __name__ == "__main__":
    sys.exit(0 if test_rls() else 1)
