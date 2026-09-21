from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from db.session import get_db
from routers.auth import get_tenant_ctx
from models.schemas import OpsStatusSummaryRequest
from models.db_models import AgentAction
from agent.crew import run_tool

router = APIRouter()


@router.post("/status-summary")
def ops_status_summary(
    payload: OpsStatusSummaryRequest | None = None,
    db: Session = Depends(get_db),
    ctx=Depends(get_tenant_ctx),
):
    """
    `ops_status_summary` (auto bucket). Summarises recent ops activity. Runs and
    logs immediately — no approval. If no activity_log is supplied, we build one
    from this company's recent agent_action rows.
    """
    activity_log = payload.activity_log if payload else None

    if not activity_log:
        recent = (
            db.query(AgentAction)
            .filter(AgentAction.company_id == ctx.company_id)
            .order_by(AgentAction.created_at.desc())
            .limit(25)
            .all()
        )
        if recent:
            activity_log = "\n".join(
                f"- {a.created_at:%Y-%m-%d %H:%M} | {a.tool_name} | {a.status}"
                for a in recent
            )

    action = run_tool("ops_status_summary", {"activity_log": activity_log}, ctx.company_id, db, requested_by=ctx.user_id)
    return {
        "id": str(action.id),
        "status": action.status,
        "tool_name": action.tool_name,
        "summary": action.draft_output.get("agent_output"),
    }
