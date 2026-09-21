"""
Team members — the owner adds department heads and staff to their company.

This is what makes "junior drafts, senior approves" real: staff can trigger
any tool, only APPROVER_ROLES can decide, and every action row names who
triggered it and who decided it, so the owner sees everyone's work in History.

Both endpoints run on the RLS-enforced session with the tenant context set,
so a new user can only ever be created inside the caller's own company.
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from db.session import get_db
from models.db_models import AppUser
from models.schemas import TeamMemberCreate, TeamMemberResponse
from routers.auth import get_tenant_ctx, hash_password, TEAM_ADMIN_ROLES

router = APIRouter(tags=["team"])


@router.get("/company/users", response_model=list[TeamMemberResponse])
def list_team(db: Session = Depends(get_db), ctx=Depends(get_tenant_ctx)):
    """Everyone in the caller's company. Visible to all roles."""
    return (
        db.query(AppUser)
        .filter(AppUser.company_id == ctx.company_id)
        .order_by(AppUser.created_at)
        .all()
    )


@router.post("/company/users", response_model=TeamMemberResponse)
def add_team_member(payload: TeamMemberCreate, db: Session = Depends(get_db), ctx=Depends(get_tenant_ctx)):
    """Owner-only. company_id comes from the token, never from the request."""
    if ctx.role not in TEAM_ADMIN_ROLES:
        raise HTTPException(status_code=403, detail="Only the company owner can add team members.")

    member = AppUser(
        company_id=ctx.company_id,
        name=payload.name.strip(),
        email=payload.email.strip(),
        password_hash=hash_password(payload.password),
        role=payload.role,
    )
    db.add(member)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="An account with this email already exists.")
    return member
