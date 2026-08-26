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
from db.session import engine
from db.rls_setup import apply_rls


def init_database():
    """Create all tables and apply RLS policies."""
    print("Creating tables...")
    Base.metadata.create_all(bind=engine)
    print("✅ Tables created.")

    print("Applying RLS policies...")
    apply_rls()

    print("\n🎉 Database initialized successfully!")
    print("Next step: verify RLS with the test script (test_rls_manual.py)")


if __name__ == "__main__":
    init_database()
