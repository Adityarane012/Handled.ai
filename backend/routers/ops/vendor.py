from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from db.session import get_db
from routers.auth import get_tenant_ctx
from models.schemas import VendorUpdateRequest
from agent.crew import run_tool

router = APIRouter()


@router.post("/vendor-status")
def draft_vendor_update(
    payload: VendorUpdateRequest,
    db: Session = Depends(get_db),
    ctx=Depends(get_tenant_ctx),
):
    """
    `vendor_status_update` (template_restricted bucket). The agent NEVER writes
    wording — it only selects one of the fixed TOOL_REGISTRY templates (or the
    caller names it), and we fill the blanks from `details`. Sent/logged
    immediately; if a template field is missing it's saved as `drafted` with an
    error instead of sending a blank notification.
    """
    action = run_tool("vendor_status_update", payload.dict(), ctx.company_id, db, requested_by=ctx.user_id)
    return {
        "id": str(action.id),
        "status": action.status,
        "tool_name": action.tool_name,
        "message": action.draft_output,
    }
