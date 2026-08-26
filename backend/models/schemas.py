"""
Pydantic request/response schemas for handled.ai API.
"""
from pydantic import BaseModel, EmailStr, Field
from typing import Optional, Any
from uuid import UUID
from datetime import datetime


# ─── Auth ───────────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    email: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


# ─── Company Signup ─────────────────────────────────────────────────────────

class CompanySignup(BaseModel):
    # Company fields
    name: str = Field(..., min_length=1, max_length=200)
    industry: Optional[str] = None
    size: Optional[int] = Field(None, ge=1, le=10000)
    udyam_number: Optional[str] = None
    # Owner fields
    owner_name: str = Field(..., min_length=1, max_length=200)
    owner_email: str
    password: str = Field(..., min_length=8)


class CompanyResponse(BaseModel):
    company_id: str


# ─── Agent Actions ──────────────────────────────────────────────────────────

class AgentActionResponse(BaseModel):
    id: str
    tool_name: str
    action_type: str
    status: str
    draft_output: Optional[Any] = None
    final_output: Optional[Any] = None
    approved_by: Optional[str] = None
    approved_at: Optional[datetime] = None
    created_at: datetime

    class Config:
        from_attributes = True


class ApprovalRequest(BaseModel):
    """Used when a Department Head approves a pending action."""
    action_id: str
    manual_fields: Optional[dict] = None  # e.g. {"quantity": 100, "amount": 50000}
    decision: str = Field(..., pattern="^(approved|rejected)$")


# ─── Ops Tool Requests ─────────────────────────────────────────────────────

class PurchaseOrderRequest(BaseModel):
    """Trigger a PO draft — item details, current stock, vendor info."""
    item_name: str
    current_stock: int
    reorder_reason: Optional[str] = None
    preferred_vendor: Optional[str] = None


class ExceptionRequest(BaseModel):
    """Request for a workflow exception — what SOP is being broken and why."""
    request_description: str
    sop_reference: Optional[str] = None
    justification: str


class InventoryQuestion(BaseModel):
    """Question about the company's inventory, answered via RAG."""
    question: str


class VendorUpdateRequest(BaseModel):
    """Request to send a vendor status update using a pre-approved template."""
    vendor_name: str
    template_key: str  # Must match one of TOOL_REGISTRY templates
    details: Optional[dict] = None  # Template fill values
