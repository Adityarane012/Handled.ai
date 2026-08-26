# handled.ai — Architecture

Scope: the 2-month prototype only (single Ops department, third-party AI API). The 4-layer architecture is unchanged from the HR version — it was designed to be department-agnostic from the start; only the tool registry (Section 4) is Ops-specific now.

## 1. System Overview
```
 Flutter App  →  FastAPI Backend  →  Agent Layer  →  PostgreSQL
 (screens only)   (auth, roles,      (CrewAI +        (source of truth,
                   tenant scoping)    LLM API call)     RLS-enforced)
```

## 2. Layer Responsibilities
### 2.1 Client — Flutter
No business logic. Screens: signup/login, Ops dashboard, per-tool trigger screens, approval queue.

### 2.2 API — FastAPI
Auth (JWT), role check, tenant scoping at the query level (backed by Postgres RLS), routes to the Agent layer.

### 2.3 Agent — CrewAI orchestration + LLM API call
Orchestration decides which tool is invoked, assembles RAG context (company's own inventory data, for `inventory_qa`), builds the prompt, classifies the resulting action against the fixed taxonomy (Section 4) before executing or queuing. Generation is a pure third-party API call with no DB/rules awareness — swappable for a self-hosted model in Phase 2 without touching orchestration.

### 2.4 Data — PostgreSQL
Same four core tables as the HR version — `company`, `user`, `department`, `agent_action` — unchanged, since the schema was already department-agnostic:
```
company        (id, name, industry, size, udyam_number, created_at)
user           (id, company_id, name, email, role, created_at)
department     (id, company_id, type, active, activated_at)
agent_action   (id, company_id, department_id, tool_name, action_type,
                requires_approval, status, draft_output, final_output,
                approved_by, approved_at, created_at)
```

## 3. Request Lifecycle
Unchanged from the HR version (see prior design) — staff triggers a tool → auth/role/tenant check → RAG context retrieval → LLM draft → risk-classification lookup → auto-execute / template-restrict / queue for approval → Department Head reviews (manual number entry required on binding drafts) → approve/reject → permanent log.

## 4. Risk Classification — Tool Definition Table (Ops, replaces the HR table)
| Tool | action_type |
|---|---|
| `ops_status_summary` | `auto` |
| `inventory_qa` (RAG) | `auto` |
| `vendor_status_update` | `template_restricted` |
| `purchase_order_approval` | `approval_required` (manual_fields: quantity, amount) |
| `workflow_exception_approval` | `approval_required` |

Adding HR (or any other department) back later means adding its own rows to this same table under a `department_id` scope — the table structure doesn't change, which is exactly why the department pivot didn't require an architecture rewrite, only a content swap.

## 5. Data Isolation
Unchanged: application-level `company_id` scoping + Postgres RLS as the independent backstop layer. Confirmed to be built in Week 1, not retrofitted.

## 6. Approval Queue — Design Priority
Unchanged design requirements: full draft shown, money/date fields render empty and editable (never pre-filled), Approve/Edit/Reject with permanent logging, no batch approval for the prototype. `purchase_order_approval` is now the tool this design has to work best for — it plays the same role the offer-letter tool played in the HR version.

## 7. Non-Functional Notes
Unchanged: append-only audit logging, hard API spend cap + CrewAI `max_iter`/`max_rpm`, multi-department routing/config-thresholds/self-hosted serving/code-signing all explicitly deferred, not architecturally blocked.
