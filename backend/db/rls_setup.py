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
from db.session import admin_engine


RLS_SETUP_SQL = """
-- Enable RLS on tenant-scoped tables (idempotent — safe to re-run)
ALTER TABLE company ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE department ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_action ENABLE ROW LEVEL SECURITY;

-- Drop existing policies first (idempotent re-run safety)
DROP POLICY IF EXISTS tenant_isolation_company ON company;
DROP POLICY IF EXISTS tenant_isolation_user ON app_user;
DROP POLICY IF EXISTS tenant_isolation_dept ON department;
DROP POLICY IF EXISTS tenant_isolation_action ON agent_action;

-- Create isolation policies
-- These check the session variable set by set_tenant_context() in session.py
-- NULLIF(..., '') is required: once a dotted GUC has been SET in a session,
-- Postgres reverts it to an EMPTY STRING (not NULL) when the SET LOCAL scope
-- ends. Without NULLIF, a query that runs after the request's transaction has
-- committed would evaluate ''::UUID and raise, instead of simply matching no
-- rows.
-- company has no company_id column of its own — it IS the tenant, so the
-- policy matches on its own primary key. Only company.signup/login use the
-- admin (RLS-bypassing) engine to touch this table today, so this is a
-- backstop for any future runtime-role query, not a fix for a live bug.
CREATE POLICY tenant_isolation_company ON company
    USING (id = NULLIF(current_setting('app.current_company_id', true), '')::UUID);

CREATE POLICY tenant_isolation_user ON app_user
    USING (company_id = NULLIF(current_setting('app.current_company_id', true), '')::UUID);

CREATE POLICY tenant_isolation_dept ON department
    USING (company_id = NULLIF(current_setting('app.current_company_id', true), '')::UUID);

CREATE POLICY tenant_isolation_action ON agent_action
    USING (company_id = NULLIF(current_setting('app.current_company_id', true), '')::UUID);

-- Behaviour:
-- - Superuser/migration connections (no tenant set) bypass RLS by default
-- - App connections with the variable set get filtered correctly
-- - App connections WITHOUT it set (or reset to '') get NO rows — safe default,
--   and no error
"""


def _has_sql(fragment: str) -> bool:
    """True if the fragment has a real statement once SQL line-comments are stripped."""
    body = "\n".join(
        ln for ln in fragment.splitlines() if not ln.strip().startswith("--")
    )
    return bool(body.strip())


def apply_rls():
    """
    Apply RLS policies to all tenant-scoped tables.

    Uses the admin (superuser) connection — ALTER TABLE / CREATE POLICY require
    table ownership, which the runtime `handled_app` role does not have.
    """
    with admin_engine.connect() as conn:
        for statement in RLS_SETUP_SQL.split(";"):
            if _has_sql(statement):
                conn.execute(text(statement))
        conn.commit()
    print("RLS policies applied successfully.")


if __name__ == "__main__":
    apply_rls()
