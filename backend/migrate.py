"""
Bring an existing handled_dev database up to the current schema.

init_db.py only creates tables that don't exist yet — create_all() never
alters a table that's already there. So a database created before these
changes keeps its old shape, and every request that writes agent_action
fails with `column "requested_by" does not exist`. This script is the
missing ALTER step, written to be safe to re-run on any machine.

Covers:
  1. agent_action.requested_by  — who triggered the action (audit trail)
  2. UNIQUE (company_id, type) on department
  3. index agent_action (company_id, status) — the approval-queue filter
  4. RLS policy on company      — via apply_rls() (idempotent)
  5. approve -> 'executed'      — code-only, no DDL needed
  +  agent_action.decision_note — why a human approved/rejected

Run from backend/:  ..\\venv\\Scripts\\python migrate.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from sqlalchemy import text
from db.session import admin_engine
from db.rls_setup import apply_rls


MIGRATION_SQL = [
    # 1 — who triggered
    """
    ALTER TABLE agent_action
        ADD COLUMN IF NOT EXISTS requested_by UUID REFERENCES app_user(id)
    """,
    # decision note
    """
    ALTER TABLE agent_action
        ADD COLUMN IF NOT EXISTS decision_note TEXT
    """,
    # 2 — one department row per type per company. Postgres has no
    # ADD CONSTRAINT IF NOT EXISTS, hence the catalog check.
    """
    DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conname = 'uq_department_company_type'
        ) THEN
            ALTER TABLE department
                ADD CONSTRAINT uq_department_company_type UNIQUE (company_id, type);
        END IF;
    END $$
    """,
    # 3 — approval-queue index
    """
    CREATE INDEX IF NOT EXISTS ix_agent_action_company_status
        ON agent_action (company_id, status)
    """,
]


def migrate():
    with admin_engine.begin() as conn:
        dupes = conn.execute(text(
            "SELECT company_id, type, count(*) FROM department "
            "GROUP BY 1, 2 HAVING count(*) > 1"
        )).all()
        if dupes:
            # Don't guess which duplicate to keep — that's a data decision.
            raise SystemExit(
                f"Duplicate department rows block the UNIQUE constraint: {dupes}. "
                "Resolve them by hand, then re-run."
            )
        for statement in MIGRATION_SQL:
            conn.execute(text(statement))
    print("Schema migration applied.")

    # 4 — company RLS policy (apply_rls drops + recreates all policies)
    apply_rls()


if __name__ == "__main__":
    migrate()
