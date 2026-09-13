from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from db.session import get_admin_db
from models.schemas import CompanySignup, CompanyResponse
from models.db_models import Company, AppUser, Department
from routers.auth import hash_password

router = APIRouter(tags=["company"])

@router.post("/company/signup", response_model=CompanyResponse)
def signup(payload: CompanySignup, db: Session = Depends(get_admin_db)):
    """Company signup uses admin DB session since the tenant doesn't exist yet."""
    # 1. Create company
    company = Company(
        name=payload.name,
        industry=payload.industry,
        size=payload.size,
        udyam_number=payload.udyam_number
    )
    db.add(company)
    db.flush() # flush to get company.id

    # 2. Create owner
    owner = AppUser(
        company_id=company.id,
        name=payload.owner_name,
        email=payload.owner_email,
        password_hash=hash_password(payload.password),
        role="owner_admin"
    )
    db.add(owner)

    # 3. Create Ops department (active by default)
    ops_dept = Department(
        company_id=company.id,
        type="ops",
        active=True
    )
    db.add(ops_dept)

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="An account with this email already exists.")
    return {"company_id": str(company.id)}
