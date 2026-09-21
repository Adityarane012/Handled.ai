import math

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload
from datetime import datetime, timezone

from db.session import get_db
from routers.auth import get_tenant_ctx
from models.schemas import ApprovalRequest, AgentActionResponse
from models.db_models import AgentAction

router = APIRouter()


@router.get("/stats")
def action_stats(db: Session = Depends(get_db), ctx=Depends(get_tenant_ctx)):
    """
    Aggregate counts for the dashboard — the tiered-autonomy model expressed
    in numbers rather than prose: how much ran without a human, how much
    needed one, and what the human actually decided when asked.

    Counts are grouped in SQL rather than pulled into Python so this stays
    cheap as the audit trail grows.
    """
    by_bucket = dict(
        db.query(AgentAction.action_type, func.count(AgentAction.id))
        .filter(AgentAction.company_id == ctx.company_id)
        .group_by(AgentAction.action_type)
        .all()
    )
    by_status = dict(
        db.query(AgentAction.status, func.count(AgentAction.id))
        .filter(AgentAction.company_id == ctx.company_id)
        .group_by(AgentAction.status)
        .all()
    )

    total = sum(by_bucket.values())
    # "Ran without a human" = the auto + template buckets. Approval-required
    # actions always cost a human a decision, by design.
    hands_off = by_bucket.get("auto", 0) + by_bucket.get("template_restricted", 0)
    approved = by_status.get("executed", 0)
    rejected = by_status.get("rejected", 0)
    decided = approved + rejected

    return {
        "total_actions": total,
        "by_bucket": {
            "auto": by_bucket.get("auto", 0),
            "template_restricted": by_bucket.get("template_restricted", 0),
            "approval_required": by_bucket.get("approval_required", 0),
        },
        "by_status": by_status,
        "pending_approval": by_status.get("pending_approval", 0),
        "approved": approved,
        "rejected": rejected,
        # Share of all actions that never needed a human. None (not 0) when
        # there's nothing to divide by, so the UI can show "—" instead of a
        # misleading 0%.
        "hands_off_rate": round(hands_off / total, 3) if total else None,
        # Of the decisions a human actually made, how many they rejected —
        # evidence the approval step is real judgment, not rubber-stamping.
        "rejection_rate": round(rejected / decided, 3) if decided else None,
    }

@router.get("/history", response_model=list[AgentActionResponse])
def list_action_history(db: Session = Depends(get_db), ctx=Depends(get_tenant_ctx), limit: int = 200):
    """
    Full audit trail for the current company — every agent_action row
    regardless of bucket or status, newest first. Unlike /approvals (pending
    only), this is what makes the tiered-autonomy story visible: what ran
    automatically, what went out under a template, and what a human
    approved/rejected.
    """
    # joinedload so rendering "requested by / approved by" names doesn't fire
    # a query per row.
    actions = (
        db.query(AgentAction)
        .options(joinedload(AgentAction.requester), joinedload(AgentAction.approver))
        .filter(AgentAction.company_id == ctx.company_id)
        .order_by(AgentAction.created_at.desc())
        .limit(limit)
        .all()
    )

    return actions

@router.get("/approvals", response_model=list[AgentActionResponse])
def list_pending_approvals(db: Session = Depends(get_db), ctx=Depends(get_tenant_ctx)):
    """List all actions pending approval for the current company."""
    # RLS enforces isolation here implicitly, but we add company_id for clarity
    actions = db.query(AgentAction).filter(
        AgentAction.company_id == ctx.company_id,
        AgentAction.status == "pending_approval"
    ).order_by(AgentAction.created_at.desc()).all()
    
    return actions

def _usable_po_figures(fields: dict) -> tuple[int, float]:
    """
    Server-side twin of the app's manualFiguresAreUsable(): quantity a positive
    whole number, amount a positive finite number. The button gating in Flutter
    is a convenience — this is the rule, since the API can be called directly.
    """
    quantity, amount = fields.get("quantity"), fields.get("amount")
    # bool is a subclass of int in Python — True must not pass as quantity 1.
    if isinstance(quantity, bool) or not isinstance(quantity, int) or quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be a whole number greater than 0")
    if (isinstance(amount, bool) or not isinstance(amount, (int, float))
            or not math.isfinite(amount) or amount <= 0):
        raise HTTPException(status_code=400, detail="Amount must be a number greater than 0")
    return quantity, amount


@router.post("/approve")
def approve_action(payload: ApprovalRequest, db: Session = Depends(get_db), ctx=Depends(get_tenant_ctx)):
    """
    Approve or reject a pending action.
    The frontend must pass the manual_fields (e.g. quantity, amount) for approval_required tools.
    """
    # FOR UPDATE: two people deciding the same action at once would otherwise
    # both read "pending" and both write — the second silently overwriting the
    # first's decision (seen: a row marked rejected still carrying an approved
    # quantity). The lock makes the second request wait, re-read, and get 400.
    action = db.query(AgentAction).filter(
        AgentAction.id == payload.action_id,
        AgentAction.company_id == ctx.company_id
    ).with_for_update().first()

    if not action:
        raise HTTPException(status_code=404, detail="Action not found")
        
    if action.status != "pending_approval":
        raise HTTPException(status_code=400, detail="Action is not pending approval")

    # If approved, validate manual fields
    if payload.decision == "approved":
        if action.tool_name == "purchase_order_approval":
            if not payload.manual_fields or "quantity" not in payload.manual_fields or "amount" not in payload.manual_fields:
                raise HTTPException(status_code=400, detail="Quantity and amount are required for PO approval")
            quantity, amount = _usable_po_figures(payload.manual_fields)

            # Combine the AI's draft reasoning with the human's hard numbers.
            # Only the two figures are merged — any other key in manual_fields
            # could otherwise overwrite the AI's draft in the approved record.
            final_output = dict(action.draft_output or {})
            final_output.update({"quantity": quantity, "amount": amount})
            action.final_output = final_output
            # No real external send in the prototype — approval IS the send, so
            # go straight to `executed` rather than parking at `approved`.
            action.status = "executed"

        else:
            action.final_output = action.draft_output
            action.status = "executed"
            
    elif payload.decision == "rejected":
        action.status = "rejected"

    action.approved_by = ctx.user_id
    # Recorded for both outcomes, not just rejections — "approved because the
    # vendor confirmed the price" is worth keeping too.
    if payload.note and payload.note.strip():
        action.decision_note = payload.note.strip()
    # tz-aware: a naive utcnow() is read as the DB server's local zone (IST
    # here), which filed every approval 5.5h before the action was triggered.
    action.approved_at = datetime.now(timezone.utc)
    
    db.commit()
    return {"status": action.status, "action_id": str(action.id)}
