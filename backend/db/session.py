"""
Database session management for handled.ai.
Handles connection, session creation, and tenant context (RLS glue).

Per arch.md §5 and Implementation_Plan.md §1.3:
- SET LOCAL scopes the tenant context to the current transaction only
- This prevents connection pool leaks between tenants
"""
import os
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:devpass@localhost:5432/handled_dev")

DATABASE_URL_ADMIN = os.getenv("DATABASE_URL_ADMIN", "postgresql://postgres:devpass@localhost:5432/handled_dev")

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

admin_engine = create_engine(DATABASE_URL_ADMIN, pool_pre_ping=True)
AdminSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=admin_engine)


def get_db():
    """FastAPI dependency — yields a DB session with RLS enabled, closes it after the request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def get_admin_db():
    """FastAPI dependency — yields a superuser DB session for login/auth where tenant is not yet known."""
    db = AdminSessionLocal()
    try:
        yield db
    finally:
        db.close()


def set_tenant_context(db_session: Session, company_id: str):
    """
    Sets the RLS tenant context for this transaction.
    Must be called on every authenticated request before any query.
    Uses SET LOCAL so the context is automatically cleared when the
    transaction ends — safe for connection pooling.
    """
    db_session.execute(
        text("SET LOCAL app.current_company_id = :cid"),
        {"cid": str(company_id)}
    )
