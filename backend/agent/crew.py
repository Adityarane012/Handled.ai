"""
CrewAI orchestration layer for handled.ai — Ops department.

Two halves, kept deliberately separate (arch.md §2.3):
  - Orchestration (this file): picks the tool, builds the prompt, looks up the
    risk bucket in TOOL_REGISTRY, persists the agent_action row, decides
    auto-execute vs. queue-for-approval.
  - Generation: a plain LLM call with NO database or rules awareness. Provider
    is swappable via env (Ollama now, self-hosted vLLM in Phase 5) without
    touching orchestration.

`run_tool()` is the single entry point every Ops router calls.
"""
import os
from typing import Any, Dict, Optional

from crewai import Agent, Crew, Process, Task, LLM
from sqlalchemy.orm import Session

from agent.tool_registry import get_tool_config
from models.db_models import AgentAction, Department

# ─── Config ────────────────────────────────────────────────────────────────────

CREW_MAX_ITER = int(os.getenv("CREW_MAX_ITER", "6"))
CREW_MAX_RPM = int(os.getenv("CREW_MAX_RPM", "10"))
LLM_PROVIDER = os.getenv("LLM_PROVIDER", "ollama").lower()
LLM_MODEL = os.getenv("LLM_MODEL", "llama3.2")
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")


def _get_llm() -> LLM:
    """
    Build the CrewAI LLM handle for the configured provider.

    Ollama is the default for the no-cost local phase. `anthropic` / `openai` /
    `gemini` remain available by flipping LLM_PROVIDER + the matching API key.
    """
    if LLM_PROVIDER == "ollama":
        return LLM(model=f"ollama/{LLM_MODEL}", base_url=OLLAMA_BASE_URL)
    if LLM_PROVIDER == "anthropic":
        return LLM(model=f"anthropic/{LLM_MODEL}")
    if LLM_PROVIDER == "gemini":
        return LLM(model=f"gemini/{LLM_MODEL}")
    if LLM_PROVIDER == "openai":
        return LLM(model=LLM_MODEL)
    # Unknown provider — let CrewAI try the raw string.
    return LLM(model=LLM_MODEL)


def _ops_agent() -> Agent:
    return Agent(
        role="Operations Assistant",
        goal=(
            "Handle routine ops tasks accurately for a small company with no "
            "dedicated ops/logistics staff, and flag anything risky for human approval."
        ),
        backstory=(
            "An operations agent for a small Indian company. Careful, concise, and "
            "never invents facts (vendor names, stock figures, prices) that were not given."
        ),
        verbose=False,
        allow_delegation=False,
        max_iter=CREW_MAX_ITER,
        max_rpm=CREW_MAX_RPM,
        llm=_get_llm(),
    )


def _generate(description: str, expected_output: str) -> str:
    """
    Run a single-task crew and return its text output.

    On any failure (Ollama not running, model not pulled, timeout) we return a
    clearly-labelled fallback string instead of raising, so the prototype/demo
    never hard-crashes on an LLM problem. The caller still persists the row.
    """
    try:
        agent = _ops_agent()
        task = Task(description=description, expected_output=expected_output, agent=agent)
        crew = Crew(agents=[agent], tasks=[task], process=Process.sequential, verbose=False)
        return str(crew.kickoff()).strip()
    except Exception as e:  # noqa: BLE001 — deliberate catch-all for demo resilience
        return (
            f"[LLM unavailable — fallback text] Could not reach the {LLM_PROVIDER} "
            f"model '{LLM_MODEL}'. Start Ollama and `ollama pull {LLM_MODEL}`, or "
            f"switch LLM_PROVIDER in backend/.env. Error: {e}"
        )


# ─── Per-tool prompt builders ────────────────────────────────────────────────
# Each returns (description, expected_output). No DB access here — context is
# passed in already-assembled by the router.


def _prompt_ops_status_summary(ctx: Dict[str, Any]):
    activity = ctx.get("activity_log") or "No activity records were provided."
    return (
        "Summarise the current state of operations for a manager who has 30 seconds. "
        "Base the summary ONLY on the activity records below — do not invent tasks, "
        "numbers, or vendors.\n\n"
        f"Activity records:\n{activity}",
        "A tight 3-6 bullet status summary: what's on track, what's blocked, what "
        "needs attention. No preamble.",
    )


def _prompt_inventory_qa(ctx: Dict[str, Any]):
    question = ctx.get("question", "")
    passages = ctx.get("context_chunks") or []
    joined = "\n---\n".join(passages) if passages else ""
    if not joined:
        return (
            f"The user asked: {question!r}\n\n"
            "No matching inventory records were retrieved for this question. "
            "Reply that there is no matching inventory record on file — do NOT guess.",
            "One or two sentences stating no matching inventory record was found.",
        )
    return (
        "Answer the inventory question using ONLY the retrieved inventory records "
        "below. If the records don't contain the answer, say so plainly — never "
        "fabricate stock levels, SKUs, locations, or prices.\n\n"
        f"Question: {question}\n\n"
        f"Retrieved inventory records:\n{joined}",
        "A direct answer grounded in the records, quoting the relevant figures. "
        "If unanswerable from the records, say 'no matching inventory record found'.",
    )


def _prompt_workflow_exception(ctx: Dict[str, Any]):
    return (
        "A staff member has requested something that may break standard operating "
        "procedure. Evaluate it against the SOP reference and write reasoning for the "
        "Department Head who must approve or reject it. Do not approve it yourself. "
        "Do not invent policy details that were not provided.\n\n"
        f"Request: {ctx.get('request_description', '')}\n"
        f"SOP reference: {ctx.get('sop_reference') or 'Not provided.'}\n"
        f"Staff justification: {ctx.get('justification', '')}",
        "A short brief for the approver: (1) which SOP rule is at stake, (2) how far "
        "the request departs from it, (3) the trade-off, (4) a clear recommendation "
        "the human can accept or overrule.",
    )


def _prompt_purchase_order(ctx: Dict[str, Any]):
    return (
        "A reorder trigger has fired. Draft ONLY the justification paragraph for a "
        "purchase order. Do NOT state, guess, or imply a quantity to order or a "
        "total amount — those are entered by the human approver. If no vendor was "
        "given, note that a vendor still needs to be chosen; do not invent one.\n\n"
        f"Item: {ctx.get('item_name', '')}\n"
        f"Current stock: {ctx.get('current_stock', '')}\n"
        f"Reorder reason: {ctx.get('reorder_reason') or 'Stock is running low.'}\n"
        f"Preferred vendor: {ctx.get('preferred_vendor') or 'None on file.'}",
        "A short, professional justification for why this purchase order is needed. "
        "No quantities, no prices.",
    )


_PROMPT_BUILDERS = {
    "ops_status_summary": _prompt_ops_status_summary,
    "inventory_qa": _prompt_inventory_qa,
    "workflow_exception_approval": _prompt_workflow_exception,
    "purchase_order_approval": _prompt_purchase_order,
}


# ─── Template-restricted handling (no free generation) ────────────────────────


def _fill_template(tool_cfg: Dict[str, Any], ctx: Dict[str, Any]) -> Dict[str, Any]:
    """
    vendor_status_update: the LLM never writes wording. It only picks which
    pre-approved template applies; we fill the blanks from caller-supplied fields.
    """
    templates: Dict[str, Dict[str, str]] = tool_cfg["templates"]
    template_key = ctx.get("template_key")

    if template_key not in templates:
        # Ask the model to CLASSIFY only — pick one key from the fixed list.
        choice = _generate(
            "Pick the single best template for this vendor situation. Reply with "
            "EXACTLY one of these keys and nothing else: "
            f"{', '.join(templates)}.\n\nSituation: {ctx.get('situation', '')}",
            "One template key, verbatim, nothing else.",
        ).strip().strip(".'\"")
        template_key = choice if choice in templates else next(iter(templates))

    tpl = templates[template_key]
    fields = ctx.get("details") or {}
    try:
        subject = tpl["subject"].format(**fields)
        body = tpl["body"].format(**fields)
        missing = None
    except KeyError as e:
        subject, body = tpl["subject"], tpl["body"]
        missing = f"Missing template field: {e}. Notification not sent."

    return {
        "template_key": template_key,
        "subject": subject,
        "body": body,
        "vendor_name": ctx.get("vendor_name"),
        "error": missing,
    }


# ─── The single entry point ──────────────────────────────────────────────────


def run_tool(
    tool_name: str,
    context: Dict[str, Any],
    company_id: str,
    db: Session,
) -> AgentAction:
    """
    Execute an Ops tool end-to-end and return the persisted AgentAction row.

      auto                 -> generate, execute now, status = auto_executed
      template_restricted  -> pick + fill a fixed template, status = auto_executed
      approval_required    -> generate a draft, status = pending_approval
    """
    tool_cfg = get_tool_config(tool_name)  # KeyError if unknown — intentional
    action_type = tool_cfg["action_type"]

    ops_dept = (
        db.query(Department)
        .filter(Department.company_id == company_id, Department.type == "ops")
        .first()
    )

    if action_type == "template_restricted":
        draft_output: Dict[str, Any] = _fill_template(tool_cfg, context)
    else:
        builder = _PROMPT_BUILDERS.get(tool_name)
        if builder is None:
            raise KeyError(f"No prompt builder registered for tool: {tool_name}")
        description, expected_output = builder(context)
        text = _generate(description, expected_output)
        draft_output = {"input": context, "agent_output": text}

    if action_type == "auto":
        status, final_output = "auto_executed", draft_output
    elif action_type == "template_restricted":
        status = "auto_executed" if not draft_output.get("error") else "drafted"
        final_output = draft_output if status == "auto_executed" else None
    else:  # approval_required
        status, final_output = "pending_approval", None

    action = AgentAction(
        company_id=company_id,
        department_id=ops_dept.id if ops_dept else None,
        tool_name=tool_name,
        action_type=action_type,
        status=status,
        draft_output=draft_output,
        final_output=final_output,
    )
    db.add(action)
    db.flush()   # populate Python-side defaults (id, created_at) inside the txn
    db.commit()  # expire_on_commit=False keeps `action`'s attributes readable
    return action


# ─── Backwards-compat shim ───────────────────────────────────────────────────
# purchase.py historically imported this; keep it working via run_tool.


def draft_purchase_order_justification(
    item_name: str,
    current_stock: int,
    reorder_reason: Optional[str] = None,
    preferred_vendor: Optional[str] = None,
    company_id: Optional[str] = None,
    db: Optional[Session] = None,
) -> Dict[str, Any]:
    ctx = {
        "item_name": item_name,
        "current_stock": current_stock,
        "reorder_reason": reorder_reason,
        "preferred_vendor": preferred_vendor,
    }
    if db is not None and company_id is not None:
        action = run_tool("purchase_order_approval", ctx, company_id, db)
        return {"id": str(action.id), "status": action.status, **action.draft_output}
    # No DB context: just return a draft dict (used by ad-hoc scripts/tests).
    description, expected_output = _prompt_purchase_order(ctx)
    return {**ctx, "agent_justification": _generate(description, expected_output)}
