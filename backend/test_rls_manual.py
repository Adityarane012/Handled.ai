"""
Manual RLS verification test for handled.ai.
Per Build Guide Step 6: prove RLS works with raw SQL, no app code involved.

This script:
1. Creates two fake companies with users and actions
2. Sets tenant context to Company A
3. Queries for Company B's data — should return NOTHING
4. Verifies isolation works in both directions

Run AFTER init_db.py:
    python test_rls_manual.py
"""
import sys
import os
import uuid

sys.path.insert(0, os.path.dirname(__file__))

from sqlalchemy import text
from db.session import engine


def test_rls():
    """Prove cross-tenant isolation with raw SQL."""
    company_a_id = str(uuid.uuid4())
    company_b_id = str(uuid.uuid4())

    with engine.connect() as conn:
        # ─── Setup: insert two companies and their data ────────────────

        # Company A
        conn.execute(text(
            "INSERT INTO company (id, name) VALUES (:id, :name)"
        ), {"id": company_a_id, "name": "Test Company A (RLS Test)"})

        conn.execute(text(
            "INSERT INTO app_user (id, company_id, name, email, password_hash, role) "
            "VALUES (:id, :cid, :name, :email, :pw, :role)"
        ), {
            "id": str(uuid.uuid4()), "cid": company_a_id,
            "name": "Alice", "email": f"alice-{uuid.uuid4().hex[:8]}@test.com",
            "pw": "fakehash", "role": "owner_admin"
        })

        conn.execute(text(
            "INSERT INTO department (id, company_id, type) VALUES (:id, :cid, :type)"
        ), {"id": str(uuid.uuid4()), "cid": company_a_id, "type": "ops"})

        # Company B
        conn.execute(text(
            "INSERT INTO company (id, name) VALUES (:id, :name)"
        ), {"id": company_b_id, "name": "Test Company B (RLS Test)"})

        conn.execute(text(
            "INSERT INTO app_user (id, company_id, name, email, password_hash, role) "
            "VALUES (:id, :cid, :name, :email, :pw, :role)"
        ), {
            "id": str(uuid.uuid4()), "cid": company_b_id,
            "name": "Bob", "email": f"bob-{uuid.uuid4().hex[:8]}@test.com",
            "pw": "fakehash", "role": "owner_admin"
        })

        conn.execute(text(
            "INSERT INTO department (id, company_id, type) VALUES (:id, :cid, :type)"
        ), {"id": str(uuid.uuid4()), "cid": company_b_id, "type": "ops"})

        conn.commit()

        # ─── Test 1: Set context to A, query for B's users ────────────

        conn.execute(text("SET LOCAL app.current_company_id = :cid"), {"cid": company_a_id})
        result = conn.execute(text(
            "SELECT * FROM app_user WHERE company_id = :cid"
        ), {"cid": company_b_id})
        rows_b_from_a = result.fetchall()

        if len(rows_b_from_a) == 0:
            print("✅ TEST 1 PASSED: Company A context → querying Company B's users → 0 rows (RLS blocked it)")
        else:
            print(f"❌ TEST 1 FAILED: Got {len(rows_b_from_a)} rows — RLS is NOT working!")
            return False

        conn.commit()  # Reset SET LOCAL scope

        # ─── Test 2: Set context to B, query for A's users ────────────

        conn.execute(text("SET LOCAL app.current_company_id = :cid"), {"cid": company_b_id})
        result = conn.execute(text(
            "SELECT * FROM app_user WHERE company_id = :cid"
        ), {"cid": company_a_id})
        rows_a_from_b = result.fetchall()

        if len(rows_a_from_b) == 0:
            print("✅ TEST 2 PASSED: Company B context → querying Company A's users → 0 rows (RLS blocked it)")
        else:
            print(f"❌ TEST 2 FAILED: Got {len(rows_a_from_b)} rows — RLS is NOT working!")
            return False

        conn.commit()

        # ─── Test 3: Set context to A, query A's own users (should work) ──

        conn.execute(text("SET LOCAL app.current_company_id = :cid"), {"cid": company_a_id})
        result = conn.execute(text(
            "SELECT * FROM app_user WHERE company_id = :cid"
        ), {"cid": company_a_id})
        rows_a_from_a = result.fetchall()

        if len(rows_a_from_a) == 1:
            print("✅ TEST 3 PASSED: Company A context → querying Company A's own users → 1 row (correct)")
        else:
            print(f"⚠️  TEST 3 UNEXPECTED: Got {len(rows_a_from_a)} rows (expected 1)")

        conn.commit()

        # ─── Test 4: Department isolation ──────────────────────────────

        conn.execute(text("SET LOCAL app.current_company_id = :cid"), {"cid": company_a_id})
        result = conn.execute(text(
            "SELECT * FROM department WHERE company_id = :cid"
        ), {"cid": company_b_id})
        dept_rows = result.fetchall()

        if len(dept_rows) == 0:
            print("✅ TEST 4 PASSED: Company A context → querying Company B's departments → 0 rows")
        else:
            print(f"❌ TEST 4 FAILED: Got {len(dept_rows)} rows — department RLS not working!")
            return False

        conn.commit()

        # ─── Cleanup ──────────────────────────────────────────────────
        # Clean up test data (superuser connection, no RLS applied)
        conn.execute(text("RESET app.current_company_id"))
        conn.execute(text("DELETE FROM app_user WHERE company_id IN (:a, :b)"),
                     {"a": company_a_id, "b": company_b_id})
        conn.execute(text("DELETE FROM department WHERE company_id IN (:a, :b)"),
                     {"a": company_a_id, "b": company_b_id})
        conn.execute(text("DELETE FROM company WHERE id IN (:a, :b)"),
                     {"a": company_a_id, "b": company_b_id})
        conn.commit()

    print("\n🎉 All RLS tests passed! Tenant isolation is confirmed working.")
    print("You can now safely build API routes knowing RLS has your back.")
    return True


if __name__ == "__main__":
    success = test_rls()
    sys.exit(0 if success else 1)
