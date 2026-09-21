from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from db.session import get_db
from routers.auth import get_tenant_ctx
from models.schemas import ExceptionRequest
from agent.crew import run_tool

router = APIRouter()


@router.post("/workflow-exception")
def evaluate_workflow_exception(
    payload: ExceptionRequest,
    db: Session = Depends(get_db),
    ctx=Depends(get_tenant_ctx),
):
    """
    `workflow_exception_approval` (approval_required bucket). The agent evaluates
    a request against SOP and drafts reasoning for the Department Head. It never
    approves anything itself — the row lands as `pending_approval` in the same
    queue the PO tool uses.
    """
    action = run_tool("workflow_exception_approval", payload.dict(), ctx.company_id, db, requested_by=ctx.user_id)
    return {
        "id": str(action.id),
        "status": action.status,
        "tool_name": action.tool_name,
        "draft_output": action.draft_output,
    }
