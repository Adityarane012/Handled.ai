"""
Database initialization script for handled.ai.
Creates tables + applies RLS in the correct order.

Run: python init_db.py
"""
import sys
import os

# Add backend to path so imports work
sys.path.insert(0, os.path.dirname(__file__))

from models.db_models import Base
from db.session import admin_engine
from db.rls_setup import apply_rls


def init_database():
    """Create all tables and apply RLS policies (both need superuser / table owner)."""
    print("Creating tables...")
    Base.metadata.create_all(bind=admin_engine)
    print("Tables created.")

    print("Applying RLS policies...")
    apply_rls()

    print("\nDatabase initialized successfully.")
    print("Next step: verify RLS with the test script (test_rls_manual.py)")


if __name__ == "__main__":
    init_database()
