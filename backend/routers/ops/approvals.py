from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime, timezone

from db.session import get_db
from routers.auth import get_tenant_ctx
from models.schemas import ApprovalRequest, AgentActionResponse
from models.db_models import AgentAction

router = APIRouter()

@router.get("/approvals", response_model=list[AgentActionResponse])
def list_pending_approvals(db: Session = Depends(get_db), ctx=Depends(get_tenant_ctx)):
    """List all actions pending approval for the current company."""
    # RLS enforces isolation here implicitly, but we add company_id for clarity
    actions = db.query(AgentAction).filter(
        AgentAction.company_id == ctx.company_id,
        AgentAction.status == "pending_approval"
    ).order_by(AgentAction.created_at.desc()).all()
    
    return actions

@router.post("/approve")
def approve_action(payload: ApprovalRequest, db: Session = Depends(get_db), ctx=Depends(get_tenant_ctx)):
    """
    Approve or reject a pending action.
    The frontend must pass the manual_fields (e.g. quantity, amount) for approval_required tools.
    """
    action = db.query(AgentAction).filter(
        AgentAction.id == payload.action_id,
        AgentAction.company_id == ctx.company_id
    ).first()
    
    if not action:
        raise HTTPException(status_code=404, detail="Action not found")
        
    if action.status != "pending_approval":
        raise HTTPException(status_code=400, detail="Action is not pending approval")

    # If approved, validate manual fields
    if payload.decision == "approved":
        if action.tool_name == "purchase_order_approval":
            if not payload.manual_fields or "quantity" not in payload.manual_fields or "amount" not in payload.manual_fields:
                raise HTTPException(status_code=400, detail="Quantity and amount are required for PO approval")
                
            # Combine the AI's draft reasoning with the human's hard numbers
            final_output = dict(action.draft_output or {})
            final_output.update(payload.manual_fields)
            action.final_output = final_output
            action.status = "approved"
            
        else:
            action.final_output = action.draft_output
            action.status = "approved"
            
    elif payload.decision == "rejected":
        action.status = "rejected"
        
    action.approved_by = ctx.user_id
    action.approved_at = datetime.utcnow()
    
    db.commit()
    return {"status": action.status, "action_id": str(action.id)}
