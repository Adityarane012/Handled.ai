"""
SQLAlchemy ORM models for handled.ai.
Maps directly to the schema in arch.md §2.4 / Implementation_Plan.md §1.2.
"""
import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Column, String, Integer, Boolean, DateTime, ForeignKey, Text, CheckConstraint
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship, declarative_base

Base = declarative_base()


class Company(Base):
    __tablename__ = "company"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(Text, nullable=False)
    industry = Column(Text)
    size = Column(Integer)
    udyam_number = Column(Text)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    # Relationships
    users = relationship("AppUser", back_populates="company", cascade="all, delete-orphan")
    departments = relationship("Department", back_populates="company", cascade="all, delete-orphan")
    actions = relationship("AgentAction", back_populates="company", cascade="all, delete-orphan")


class AppUser(Base):
    __tablename__ = "app_user"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    company_id = Column(UUID(as_uuid=True), ForeignKey("company.id", ondelete="CASCADE"), nullable=False)
    name = Column(Text, nullable=False)
    email = Column(Text, unique=True, nullable=False)
    password_hash = Column(Text, nullable=False)
    role = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        CheckConstraint("role IN ('owner_admin', 'department_head', 'staff')", name="valid_role"),
    )

    # Relationships
    company = relationship("Company", back_populates="users")


class Department(Base):
    __tablename__ = "department"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    company_id = Column(UUID(as_uuid=True), ForeignKey("company.id", ondelete="CASCADE"), nullable=False)
    type = Column(Text, nullable=False)  # 'ops', 'hr', etc. — fixed catalog
    active = Column(Boolean, default=True)
    activated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    # Relationships
    company = relationship("Company", back_populates="departments")
    actions = relationship("AgentAction", back_populates="department")


class AgentAction(Base):
    __tablename__ = "agent_action"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    company_id = Column(UUID(as_uuid=True), ForeignKey("company.id", ondelete="CASCADE"), nullable=False)
    department_id = Column(UUID(as_uuid=True), ForeignKey("department.id"))
    tool_name = Column(Text, nullable=False)
    action_type = Column(Text, nullable=False)
    status = Column(Text, nullable=False, default="drafted")
    draft_output = Column(JSONB)
    final_output = Column(JSONB)
    approved_by = Column(UUID(as_uuid=True), ForeignKey("app_user.id"))
    approved_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        CheckConstraint(
            "action_type IN ('auto', 'template_restricted', 'approval_required')",
            name="valid_action_type"
        ),
        CheckConstraint(
            "status IN ('drafted', 'auto_executed', 'pending_approval', 'approved', 'rejected', 'executed')",
            name="valid_status"
        ),
    )

    # Relationships
    company = relationship("Company", back_populates="actions")
    department = relationship("Department", back_populates="actions")
    approver = relationship("AppUser", foreign_keys=[approved_by])
