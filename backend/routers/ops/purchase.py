from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ...db.session import get_db
from ...routers.auth import get_tenant_ctx
from ...models.schemas import PurchaseOrderRequest
from ...models.db_models import AgentAction, Department
from ...agent.crew import draft_purchase_order_justification

router = APIRouter()

@router.post("/purchase-order")
def draft_purchase_order(payload: PurchaseOrderRequest, db: Session = Depends(get_db), ctx=Depends(get_tenant_ctx)):
    """
    Trigger a Purchase Order draft.
    Runs the agent to justify the order, then saves as pending_approval.
    """
    # 1. Run the AI tool
    draft = draft_purchase_order_justification(
        item_name=payload.item_name,
        current_stock=payload.current_stock,
        reorder_reason=payload.reorder_reason,
        preferred_vendor=payload.preferred_vendor
    )

    # 2. Get the Ops department ID
    ops_dept = db.query(Department).filter(
        Department.company_id == ctx.company_id,
        Department.type == "ops"
    ).first()

    dept_id = ops_dept.id if ops_dept else None

    # 3. Save to database as pending_approval (enforces safety rule)
    action = AgentAction(
        company_id=ctx.company_id,
        department_id=dept_id,
        tool_name="purchase_order_approval",
        action_type="approval_required",
        status="pending_approval",
        draft_output=draft
    )

    db.add(action)
    db.commit()
    db.refresh(action)

    # Returning the created action allows the UI to instantly jump to the approval screen if desired
    return {
        "id": str(action.id),
        "status": action.status,
        "tool_name": action.tool_name,
        "draft_output": action.draft_output
    }
