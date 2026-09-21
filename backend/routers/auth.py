from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError
from passlib.context import CryptContext
import os

from db.session import get_db, get_admin_db, set_tenant_context
from models.db_models import AppUser
from models.schemas import TokenResponse, LoginRequest
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

router = APIRouter(tags=["auth"])

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBearer()

JWT_SECRET = os.getenv("JWT_SECRET", "handled-dev-secret-change-in-production")
JWT_ALGORITHM = os.getenv("JWT_ALGORITHM", "HS256")
JWT_EXPIRY_MINUTES = int(os.getenv("JWT_EXPIRY_MINUTES", "60"))

# Who may do what — hard-coded, like the autonomy buckets, never inferred.
# Anyone in the company can trigger a tool (junior staff drafting work is the
# point); only these roles can decide an approval_required action.
APPROVER_ROLES = {"owner_admin", "department_head"}
# Only the owner adds people. Roles they can hand out — never another owner.
TEAM_ADMIN_ROLES = {"owner_admin"}
ASSIGNABLE_ROLES = {"department_head", "staff"}

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def hash_password(password):
    return pwd_context.hash(password)

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(minutes=JWT_EXPIRY_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, JWT_SECRET, algorithm=JWT_ALGORITHM)
    return encoded_jwt

@router.post("/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_admin_db)):
    """Login using admin DB session to bypass RLS initially."""
    user = db.query(AppUser).filter(AppUser.email == payload.email).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials"
        )
    
    token = create_access_token(data={
        "sub": str(user.id),
        "company_id": str(user.company_id),
        "role": user.role
    })
    return {"access_token": token, "token_type": "bearer"}

class TenantCtx:
    def __init__(self, user_id: str, company_id: str, role: str):
        self.user_id = user_id
        self.company_id = company_id
        self.role = role

def get_tenant_ctx(credentials: HTTPAuthorizationCredentials = Depends(security), db: Session = Depends(get_db)):
    """Validates JWT and sets Postgres tenant context on the session."""
    token = credentials.credentials
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_id = payload.get("sub")
        company_id = payload.get("company_id")
        role = payload.get("role")
        if user_id is None or company_id is None:
            raise HTTPException(status_code=401, detail="Invalid token payload")
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")
        
    # CRITICAL: Tie the JWT to the DB session for this request
    set_tenant_context(db, company_id)
    return TenantCtx(user_id, company_id, role)

@router.get("/auth/me")
def get_me(ctx: TenantCtx = Depends(get_tenant_ctx), db: Session = Depends(get_db)):
    """Tests that RLS is working by fetching the current user with the regular (non-admin) session."""
    user = db.query(AppUser).filter(AppUser.id == ctx.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found (or hidden by RLS)")
    return {
        "id": str(user.id),
        "name": user.name,
        "email": user.email,
        "role": user.role,
        "company_id": str(user.company_id),
        # The app reads these instead of re-deriving permissions from the role
        # string, so the rule lives in one place (here) and Flutter stays dumb.
        "can_approve": user.role in APPROVER_ROLES,
        "can_manage_team": user.role in TEAM_ADMIN_ROLES,
    }
