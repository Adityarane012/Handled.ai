from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from db.session import get_db
from routers.auth import get_tenant_ctx
from models.schemas import PurchaseOrderRequest
from agent.crew import run_tool

router = APIRouter()


@router.post("/purchase-order")
def draft_purchase_order(
    payload: PurchaseOrderRequest,
    db: Session = Depends(get_db),
    ctx=Depends(get_tenant_ctx),
):
    """
    Trigger a Purchase Order draft.

    The agent writes only the justification. Quantity and amount are left BLANK —
    the Department Head types them in the approval queue (core safety rule).
    Row is persisted as `pending_approval`.
    """
    action = run_tool("purchase_order_approval", payload.dict(), ctx.company_id, db)
    return {
        "id": str(action.id),
        "status": action.status,
        "tool_name": action.tool_name,
        "draft_output": action.draft_output,
    }
