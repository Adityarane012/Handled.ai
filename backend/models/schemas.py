"""
Pydantic request/response schemas for handled.ai API.
"""
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from typing import Optional, Any, List
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
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tool_name: str
    action_type: str
    status: str
    department_id: Optional[UUID] = None
    draft_output: Optional[Any] = None
    final_output: Optional[Any] = None
    requested_by: Optional[UUID] = None
    approved_by: Optional[UUID] = None
    requested_by_name: Optional[str] = None
    approved_by_name: Optional[str] = None
    approved_at: Optional[datetime] = None
    created_at: datetime


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


class InventoryUpload(BaseModel):
    """The company's inventory document — chunked + embedded for inventory_qa."""
    doc_text: str = Field(..., min_length=1)
    source: str = "upload"


class OpsStatusSummaryRequest(BaseModel):
    """Optional raw activity log to summarise. If omitted, the router supplies recent agent_action rows."""
    activity_log: Optional[str] = None


class VendorUpdateRequest(BaseModel):
    """
    Request a vendor status update. Wording is NEVER free-generated — either
    `template_key` names one of the fixed templates, or `situation` is given and
    the agent only classifies which template applies. `details` fills the blanks.
    """
    vendor_name: str
    template_key: Optional[str] = None
    situation: Optional[str] = None
    details: Optional[dict] = None
