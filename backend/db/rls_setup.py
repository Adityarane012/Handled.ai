"""
RLS (Row-Level Security) setup for handled.ai.
Run this AFTER tables are created, BEFORE any API routes touch data.

Per arch.md §5: RLS is the independent backstop layer. Even if the app-layer
WHERE clause is missing, RLS alone prevents cross-tenant data leakage.

Usage:
    python -c "from db.rls_setup import apply_rls; apply_rls()"
    OR
    Called automatically from the init_db script.
"""
from sqlalchemy import text
from db.session import engine


RLS_SETUP_SQL = """
-- Enable RLS on tenant-scoped tables (idempotent — safe to re-run)
ALTER TABLE app_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE department ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_action ENABLE ROW LEVEL SECURITY;

-- Drop existing policies first (idempotent re-run safety)
DROP POLICY IF EXISTS tenant_isolation_user ON app_user;
DROP POLICY IF EXISTS tenant_isolation_dept ON department;
DROP POLICY IF EXISTS tenant_isolation_action ON agent_action;

-- Create isolation policies
-- These check the session variable set by set_tenant_context() in session.py
CREATE POLICY tenant_isolation_user ON app_user
    USING (company_id = current_setting('app.current_company_id', true)::UUID);

CREATE POLICY tenant_isolation_dept ON department
    USING (company_id = current_setting('app.current_company_id', true)::UUID);

CREATE POLICY tenant_isolation_action ON agent_action
    USING (company_id = current_setting('app.current_company_id', true)::UUID);

-- IMPORTANT: The 'true' parameter in current_setting makes it return NULL
-- instead of erroring when the variable isn't set. This means:
-- - Superuser/migration connections (no tenant set) bypass RLS by default
-- - App connections with the variable set get filtered correctly
-- - App connections WITHOUT the variable set get NO rows (safe default)
"""


def apply_rls():
    """Apply RLS policies to all tenant-scoped tables."""
    with engine.connect() as conn:
        # Execute as raw SQL — RLS is a Postgres feature, not ORM
        for statement in RLS_SETUP_SQL.split(";"):
            statement = statement.strip()
            if statement:
                conn.execute(text(statement))
        conn.commit()
    print("✅ RLS policies applied successfully.")


if __name__ == "__main__":
    apply_rls()
