"""
Evidence for the architectural claim in arch.md §4 — that the safety engine is
department-agnostic, so adding a department is "adding rows to this same table"
rather than rewriting the risk model.

That claim is worth testing rather than asserting: until recently `run_tool`
hard-coded `Department.type == "ops"`, which meant a second department's tools
would have silently attached their audit rows to the Ops department.

These tests register a throwaway tool for a hypothetical second department at
runtime (never shipped in TOOL_REGISTRY — per the Decisions Log, real
departments are a Phase 6 decision and are never invented by users or by the
model) and assert the existing engine handles it with no changes: correct
bucket, correct department row, correct approval gating, permanent audit entry.
"""
import uuid

import pytest
from sqlalchemy import text

from agent import crew
from agent.tool_registry import TOOL_REGISTRY
from db.session import admin_engine
from models.db_models import Department


@pytest.fixture
def second_department(monkeypatch):
    """
    Register a hypothetical 'procurement' department tool for the duration of
    one test. Uses the same registry the engine already reads — the point is
    that nothing about the engine needs to know this tool exists in advance.
    """
    tool = "procurement_contract_renewal"
    monkeypatch.setitem(TOOL_REGISTRY, tool, {
        "action_type": "approval_required",   # binding -> must queue for a human
        "department": "procurement",
        "description": "Hypothetical second-department tool, test-only",
    })
    monkeypatch.setitem(
        crew._PROMPT_BUILDERS, tool,
        lambda ctx: ("Draft a contract renewal note.", "A short note."),
    )
    return tool


def _add_department(company_id, dept_type):
    dept_id = uuid.uuid4()
    with admin_engine.begin() as conn:
        conn.execute(
            text("INSERT INTO department (id, company_id, type, active) "
                 "VALUES (:i, :c, :t, true)"),
            {"i": str(dept_id), "c": company_id, "t": dept_type},
        )
    return dept_id


def test_second_department_tool_routes_to_its_own_department(
    client, make_company, admin_conn, second_department
):
    co = make_company()
    proc_dept_id = _add_department(co["company_id"], "procurement")

    from db.session import SessionLocal
    db = SessionLocal()
    try:
        db.execute(text("SET LOCAL app.current_company_id = :c"), {"c": co["company_id"]})
        action = crew.run_tool(second_department, {}, co["company_id"], db)
        action_id = str(action.id)
    finally:
        db.close()

    row = admin_conn.execute(text(
        "SELECT tool_name, action_type, status, department_id "
        "FROM agent_action WHERE id = :i"), {"i": action_id}).fetchone()

    assert row[0] == second_department
    # The bucket came from the registry row, not from anything Ops-specific.
    assert row[1] == "approval_required"
    # Binding -> queued for a human, exactly as an Ops approval tool would be.
    assert row[2] == "pending_approval"
    # ...and it was filed under *procurement*, not silently under Ops.
    assert str(row[3]) == str(proc_dept_id)


def test_ops_tools_still_file_under_ops(client, make_company, admin_conn):
    """The department lookup change must not move existing Ops rows."""
    co = make_company()
    pid = client.post("/ops/purchase-order",
                      json={"item_name": "Bolt", "current_stock": 2},
                      headers=co["headers"]).json()["id"]

    dept_id = admin_conn.execute(text(
        "SELECT department_id FROM agent_action WHERE id = :i"), {"i": pid}).scalar()
    ops_id = admin_conn.execute(text(
        "SELECT id FROM department WHERE company_id = :c AND type = 'ops'"),
        {"c": co["company_id"]}).scalar()
    assert str(dept_id) == str(ops_id)


def test_every_shipped_tool_declares_its_department_and_bucket():
    """
    No tool may rely on a default. The registry is the one place a human
    decides both of these, so an omission should be loud.
    """
    valid_buckets = {"auto", "template_restricted", "approval_required"}
    for name, cfg in TOOL_REGISTRY.items():
        assert cfg.get("action_type") in valid_buckets, f"{name} has no valid action_type"
        assert cfg.get("department"), f"{name} does not declare a department"
