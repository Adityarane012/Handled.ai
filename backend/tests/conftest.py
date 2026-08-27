"""
Shared pytest fixtures for handled.ai Phase 3 hardening tests.

Runs the real FastAPI app in-process (TestClient) against the local Postgres in
backend/.env. The LLM call is stubbed (see `_stub_llm`) so tests exercise
orchestration / persistence / isolation, not model quality or network.
"""
import os
import sys
import uuid

import pytest

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND)
os.chdir(BACKEND)

from dotenv import load_dotenv
load_dotenv(os.path.join(BACKEND, ".env"))

from fastapi.testclient import TestClient
from sqlalchemy import text

import main
from db.session import admin_engine


CANNED_LLM_OUTPUT = "[test] canned agent output"


def pytest_configure(config):
    config.addinivalue_line(
        "markers", "real_llm: do not stub agent.crew._generate for this test"
    )


@pytest.fixture(autouse=True)
def _stub_llm(request, monkeypatch):
    """Make every LLM generation deterministic and instant (unless @real_llm)."""
    if request.node.get_closest_marker("real_llm"):
        return
    monkeypatch.setattr("agent.crew._generate", lambda *a, **k: CANNED_LLM_OUTPUT)


@pytest.fixture
def client():
    return TestClient(main.app)


@pytest.fixture
def make_company(client):
    """
    Factory: sign up a fresh company, return a dict with company_id / token /
    headers / owner_email. All companies created in a test are deleted afterwards.
    """
    created: list[str] = []

    def _make(name: str | None = None):
        email = f"t-{uuid.uuid4().hex[:10]}@handled.test"
        pw = "test-pass-12345"
        r = client.post("/company/signup", json={
            "name": name or f"Co {uuid.uuid4().hex[:6]}",
            "owner_name": "Test Owner", "owner_email": email, "password": pw,
        })
        assert r.status_code == 200, r.text
        cid = r.json()["company_id"]
        created.append(cid)
        tok = client.post("/auth/login", json={"email": email, "password": pw}).json()["access_token"]
        return {
            "company_id": cid,
            "token": tok,
            "headers": {"Authorization": f"Bearer {tok}"},
            "owner_email": email,
        }

    yield _make

    with admin_engine.begin() as conn:
        for cid in created:
            conn.execute(text("DELETE FROM agent_action WHERE company_id = :c"), {"c": cid})
            conn.execute(text("DELETE FROM app_user WHERE company_id = :c"), {"c": cid})
            conn.execute(text("DELETE FROM department WHERE company_id = :c"), {"c": cid})
            conn.execute(text("DELETE FROM company WHERE id = :c"), {"c": cid})


@pytest.fixture
def admin_conn():
    """Raw superuser connection for direct DB assertions (bypasses RLS)."""
    with admin_engine.connect() as conn:
        yield conn
