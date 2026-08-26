# handled.ai — Comprehensive Phase-wise Implementation Plan

> **Project:** handled.ai — Fixed-catalog, multi-department AI assistant platform for Indian SMEs (Ops module first)
> **Stack:** Flutter (Dart) · FastAPI (Python) · PostgreSQL + RLS · CrewAI · Third-party LLM API (prototype) → self-hosted LoRA-fine-tuned open-weight model via vLLM (Phase 2)
> **Timeline:** 2-year total project (remaining 4 semesters). Prototype window: 2 months (8 weeks).
> **Reference docs (same Drive folder):** `ps.md`, `arch.md`, `handled.ai - Decisions Log.md`, `handled.ai - Current Tasks.md`, `handled.ai - Project Context.md`

---

## 🗺️ Project Overview

handled.ai gives small Indian companies with no dedicated departmental staff an AI agent that handles routine work automatically, drafts anything risky for human approval, and never acts unsupervised on anything binding or hard to undo.

### What's Already Done
- ✅ **Problem Statement** (`ps.md`) — objectives, scope, personas, honest risk register
- ✅ **Architecture** (`arch.md`) — 4-layer system design, data model, request lifecycle, risk classification table
- ✅ **Decisions Log** — every rejected/confirmed/exception decision with reasoning, so nothing gets re-litigated
- ✅ **Persona Development, Ideation Doc, Stakeholder Matrix** — earlier course-template deliverables
- ✅ Naming, tool selection (5 Ops tools across all 3 autonomy buckets), tech stack, role model all confirmed

### What Needs to Be Built
- 🔲 FastAPI backend (auth, tenant scoping, RLS-backed data layer)
- 🔲 Flutter app (signup, Ops dashboard, per-tool screens, approval queue)
- 🔲 CrewAI orchestration layer + tool risk-classification table
- 🔲 5 Ops tools wired end-to-end via third-party LLM API
- 🔲 Adversarial multi-tenant isolation testing
- 🔲 Phase 2: synthetic data → LoRA fine-tune → self-hosted serving
- 🔲 Phase 3: second department module + real catalog picker
- 🔲 Phase 4: production-distribution concerns (code-signing, auto-update)

---

## 📐 Architecture Recap

```mermaid
flowchart LR
  APP[Flutter App
  screens only] -->|API calls| API(FastAPI
  auth + roles + tenant scoping)
  API --> AGENT(Agent Layer)
  AGENT --> ORCH[CrewAI Orchestration
  risk classification + RAG]
  ORCH --> LLM[LLM Generation
  3rd-party API now /
  self-hosted vLLM later]
  ORCH --> DB[(PostgreSQL
  RLS-enforced)]
  DB --> API
```

Full layer responsibilities, data model, and request lifecycle are in `arch.md` — this plan builds against that design without repeating it verbatim.

---

## Phase 0 — Environment & Tooling Setup 🧰

> **Goal:** Every tool, dependency, and credential needed for Phase 1 is installed and verified before any feature code is written.

### 0.1 — Backend Environment
```bash
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install fastapi uvicorn python-multipart sqlalchemy psycopg2-binary \
  python-jose[cryptography] passlib[bcrypt] pydantic crewai crewai-tools \
  anthropic openai python-dotenv chromadb pypdf
pip freeze > requirements.txt
```

### 0.2 — Database
```bash
# Local Postgres via Docker for dev
docker run --name handled-db -e POSTGRES_PASSWORD=devpass \
  -e POSTGRES_DB=handled_dev -p 5432:5432 -d postgres:16
```

### 0.3 — Flutter
```bash
flutter create handled_app --platforms=windows,macos,linux,android,ios,web
cd handled_app
flutter pub add http provider go_router flutter_secure_storage intl
```

### 0.4 — Environment Variables (`.env`)
```env
# Database
DATABASE_URL=postgresql://postgres:devpass@localhost:5432/handled_dev

# Auth
JWT_SECRET=<generate-a-real-secret>
JWT_EXPIRY_MINUTES=60

# LLM (prototype only — see Decisions Log for why this is scoped to prototype)
LLM_PROVIDER=anthropic
ANTHROPIC_API_KEY=sk-ant-...
LLM_MODEL=claude-haiku-4-5   # cheap model for dev; swap for demo runs only
LLM_MONTHLY_SPEND_CAP_USD=20

# CrewAI safety
CREW_MAX_ITER=6
CREW_MAX_RPM=10
```

### 0.5 — Verification
```bash
uvicorn main:app --reload  # → http://localhost:8000/health returns {"status":"ok"}
flutter run -d chrome      # → app shell loads, hits /health successfully
```

---

## Phase 1 — Foundation (Weeks 1–2) 🏗️

> **Goal:** Auth, multi-tenant data model with RLS from day one, company signup, and app shell — no tool logic yet.

### 1.1 — Monorepo Layout
```
handled-ai/
├── backend/
│   ├── main.py
│   ├── routers/
│   │   ├── auth.py
│   │   ├── company.py
│   │   └── ops/              ← Ops tools live here
│   │       ├── __init__.py
│   │       ├── status.py
│   │       ├── inventory.py
│   │       ├── vendor.py
│   │       ├── purchase.py
│   │       └── exception.py
│   ├── models/
│   │   ├── schemas.py       ← Pydantic request/response models
│   │   └── db_models.py     ← SQLAlchemy ORM models
│   ├── db/
│   │   ├── session.py
│   │   └── migrations/      ← Alembic
│   ├── agent/
│   │   ├── crew.py          ← CrewAI orchestration
│   │   └── tool_registry.py ← risk classification table (Section 2.1)
│   └── requirements.txt
├── handled_app/              ← Flutter
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   │   ├── signup_screen.dart
│   │   │   ├── login_screen.dart
│   │   │   ├── dashboard_screen.dart
│   │   │   └── approval_queue_screen.dart
│   │   ├── services/api_client.dart
│   │   └── models/
│   └── pubspec.yaml
├── docs/                      ← ps.md, arch.md, Decisions Log, Current Tasks
└── tests/
    ├── test_rls.py
    └── test_tenant_isolation.py
```

### 1.2 — Database Schema with RLS (built in now, per `arch.md` Section 5 — not retrofitted later)
```sql
CREATE TABLE company (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    industry TEXT,
    size INT,
    udyam_number TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE app_user (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES company(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('owner_admin', 'department_head', 'staff')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE department (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES company(id) ON DELETE CASCADE,
    type TEXT NOT NULL,           -- 'ops', 'hr', 'support', ... (fixed catalog, see arch.md §4)
    active BOOLEAN DEFAULT TRUE,
    activated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE agent_action (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES company(id) ON DELETE CASCADE,
    department_id UUID REFERENCES department(id),
    tool_name TEXT NOT NULL,
    action_type TEXT NOT NULL CHECK (action_type IN ('auto','template_restricted','approval_required')),
    status TEXT NOT NULL DEFAULT 'drafted'
      CHECK (status IN ('drafted','auto_executed','pending_approval','approved','rejected','executed')),
    draft_output JSONB,
    final_output JSONB,
    approved_by UUID REFERENCES app_user(id),
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Row-Level Security: the real backstop against a missed WHERE clause
ALTER TABLE app_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE department ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_action ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_user ON app_user
  USING (company_id = current_setting('app.current_company_id')::UUID);
CREATE POLICY tenant_isolation_dept ON department
  USING (company_id = current_setting('app.current_company_id')::UUID);
CREATE POLICY tenant_isolation_action ON agent_action
  USING (company_id = current_setting('app.current_company_id')::UUID);
```

### 1.3 — Setting the Tenant Context per Request (FastAPI dependency)
```python
# backend/db/session.py
from sqlalchemy import text

def set_tenant_context(db_session, company_id: str):
    db_session.execute(text("SET LOCAL app.current_company_id = :cid"), {"cid": company_id})
```
Called on every request after auth resolves the user's `company_id` — this is the glue between the JWT and the RLS policies above. Uses `SET LOCAL` (transaction-scoped) instead of `SET` to prevent connection pool leaks.

### 1.4 — Auth (JWT)
```python
# backend/routers/auth.py
from fastapi import APIRouter, Depends, HTTPException
from jose import jwt
from datetime import datetime, timedelta

router = APIRouter()

@router.post("/login")
def login(email: str, password: str, db=Depends(get_db)):
    user = authenticate(db, email, password)  # verify password_hash
    if not user:
        raise HTTPException(401, "Invalid credentials")
    token = jwt.encode(
        {"sub": str(user.id), "company_id": str(user.company_id),
         "role": user.role, "exp": datetime.utcnow() + timedelta(minutes=60)},
        JWT_SECRET, algorithm="HS256"
    )
    return {"access_token": token}
```

### 1.5 — Company Signup Flow
```python
@router.post("/company/signup")
def signup(payload: CompanySignup, db=Depends(get_db)):
    company = Company(name=payload.name, industry=payload.industry,
                       size=payload.size, udyam_number=payload.udyam_number)
    db.add(company); db.flush()
    owner = AppUser(company_id=company.id, name=payload.owner_name,
                     email=payload.owner_email,
                     password_hash=hash_password(payload.password),
                     role="owner_admin")
    db.add(owner)
    # Ops active by default for the prototype — no module picker UI yet (arch.md §1 note)
    ops_dept = Department(company_id=company.id, type="ops", active=True)
    db.add(ops_dept)
    db.commit()
    return {"company_id": str(company.id)}
```

### ✅ Phase 1 Exit Criteria
- [ ] A company can sign up and immediately has Ops active
- [ ] Login returns a valid JWT with correct `company_id` and `role`
- [ ] A second test company genuinely cannot see the first's data (manual spot check — full adversarial test is Phase 3)
- [ ] Flutter app shell hits `/health` and renders a signup form

---

## Phase 2 — Core Tool Buildout (Weeks 3–5) 🤖

> **Goal:** All 5 Ops tools working end-to-end, hardest bucket built first per the revised phase plan in `ps.md`/Decisions Log.

### 2.1 — Risk Classification Table (code, not model judgment — `arch.md` §4)
```python
# backend/agent/tool_registry.py
TOOL_REGISTRY = {
    "ops_status_summary":        {"action_type": "auto"},
    "inventory_qa":              {"action_type": "auto"},
    "vendor_status_update":      {"action_type": "template_restricted",
                                   "templates": ["delay_notification_v1",
                                                 "delivery_confirmed_v1",
                                                 "quality_issue_v1"]},
    "purchase_order_approval":   {"action_type": "approval_required",
                                   "manual_fields": ["quantity", "amount"]},
    "workflow_exception_approval": {"action_type": "approval_required"},
}
```
Adding a tool later = adding a row here with an explicit decision. Never inferred at runtime.

### 2.2 — CrewAI Orchestration Skeleton
```python
# backend/agent/crew.py
from crewai import Agent, Task, Crew

ops_agent = Agent(
    role="Ops Assistant",
    goal="Handle routine ops tasks accurately and flag anything risky for approval",
    backstory="An operations agent for a small company with no dedicated ops/logistics staff.",
    max_iter=int(os.getenv("CREW_MAX_ITER", 6)),
    max_rpm=int(os.getenv("CREW_MAX_RPM", 10)),
)

def run_tool(tool_name: str, context: dict, company_id: str) -> dict:
    tool_def = TOOL_REGISTRY[tool_name]
    task = Task(description=build_prompt(tool_name, context), agent=ops_agent)
    result = Crew(agents=[ops_agent], tasks=[task]).kickoff()
    action_type = tool_def["action_type"]
    row = save_agent_action(company_id, tool_name, action_type, draft=result)
    if action_type == "auto":
        execute(row); row.status = "auto_executed"
    elif action_type == "template_restricted":
        result = select_template(tool_def["templates"], result)
        execute(row); row.status = "auto_executed"
    else:  # approval_required
        row.status = "pending_approval"
    return row
```

### 2.3 — Purchase Order Tool (built first, paired with approval queue — the hardest case)
```python
@router.post("/ops/purchase-order")
def draft_purchase_order(payload: PurchaseOrderRequest, ctx=Depends(get_tenant_ctx)):
    draft = run_tool("purchase_order_approval", payload.dict(), ctx.company_id)
    return draft  # item, vendor, draft justification — quantity/amount fields left BLANK for manual entry
```
```dart
// handled_app/lib/screens/approval_queue_screen.dart (skeleton)
class ApprovalQueueScreen extends StatelessWidget {
  // For approval_required actions with manual_fields (e.g. purchase_order_approval):
  //   render TextFormField widgets, EMPTY, never pre-filled with AI's guess.
  //   Approve button disabled until all manual_fields are filled by the human.
}
```

### 2.4 — Workflow Exception Tool (reuses the approval queue built in 2.3)
```python
@router.post("/ops/workflow-exception")
def evaluate_workflow_exception(payload: ExceptionRequest, ctx=Depends(get_tenant_ctx)):
    # Agent checks request against standard SOP limits
    # If it breaks SOP → approval_required, drafted with reasoning for the Department Head
    return run_tool("workflow_exception_approval", payload.dict(), ctx.company_id)
```

### 2.5 — Ops Status Summary (auto)
```python
@router.post("/ops/status-summary")
def ops_status_summary(ctx=Depends(get_tenant_ctx)):
    # Summarizes task/workflow status from raw activity logs
    return run_tool("ops_status_summary", {}, ctx.company_id)
```

### 2.6 — Inventory Q&A (auto, RAG-grounded — the tool that proves "understanding," not just fluency)
```python
@router.post("/ops/inventory-qa")
def answer_inventory_question(payload: InventoryQuestion, ctx=Depends(get_tenant_ctx)):
    context_docs = retrieve_inventory_chunks(ctx.company_id, payload.question)
    return run_tool("inventory_qa",
                     {"question": payload.question, "context": context_docs},
                     ctx.company_id)
```

### 2.7 — Vendor Status Update (template-restricted — the bucket that's easy to forget exists)
```python
@router.post("/ops/vendor-status")
def draft_vendor_update(payload: VendorUpdateRequest, ctx=Depends(get_tenant_ctx)):
    return run_tool("vendor_status_update", payload.dict(), ctx.company_id)
    # Generation constrained to selecting/filling ONE of TOOL_REGISTRY's fixed templates —
    # never free-generated wording (that's what makes this bucket distinct from auto/approval)
```

### ✅ Phase 2 Exit Criteria
- [ ] All 5 tools callable end-to-end from the Flutter app
- [ ] Approval queue shows drafts, blank manual-entry fields for money/quantity, and Approve/Edit/Reject actions
- [ ] Every tool call writes a permanent `agent_action` row regardless of bucket
- [ ] **Fallback checkpoint:** if behind schedule here, cut `workflow_exception_approval` first (per Decisions Log) — do not cut RLS work or the PO approval flow

---

## Phase 3 — Hardening & Integration (Week 6) 🔒

> **Goal:** Prove the safety model actually holds under adversarial conditions, not just in the happy path.

### 3.1 — Adversarial Cross-Tenant Test
```python
# tests/test_tenant_isolation.py
def test_company_b_cannot_see_company_a_actions(client, company_a, company_b):
    token_b = login_as(company_b)
    resp = client.get(f"/agent-actions?company_id={company_a.id}",
                       headers={"Authorization": f"Bearer {token_b}"})
    assert resp.status_code in (403, 404)
    assert resp.json() == {} or "detail" in resp.json()

def test_rls_blocks_even_with_missing_app_filter(db_session, company_a, company_b):
    # Deliberately skip the app-layer WHERE clause to prove RLS alone still blocks it
    set_tenant_context(db_session, company_b.id)
    rows = db_session.query(AgentAction).filter(AgentAction.company_id == company_a.id).all()
    assert rows == []  # RLS should return nothing even though the query "asked" for company_a
```

### 3.2 — Cost Control Verification
```python
def test_crewai_respects_max_iter():
    # Simulate a prompt likely to trigger re-planning loops; assert execution halts at CREW_MAX_ITER
    ...
```
Manually confirm the provider-side hard spend cap ($20/month per Current Tasks doc) is set in the Anthropic billing dashboard — this is not testable in code, log it as a manual checklist item.

### 3.3 — Full Audit Log Pass
Every `agent_action` row, across all 5 tools and all 3 buckets, retained and queryable — spot-check that nothing is silently deleted or overwritten on reject/edit.

### ✅ Phase 3 Exit Criteria
- [ ] Adversarial isolation tests pass
- [ ] API spend cap confirmed set on provider dashboard
- [ ] `CREW_MAX_ITER`/`CREW_MAX_RPM` confirmed enforced
- [ ] Full audit trail verified end-to-end for all 5 tools

---

## Phase 4 — Demo Prep (Weeks 7–8) 🎤

> **Goal:** A rehearsed, narratable demo that makes the three-bucket safety model the star, not just "an AI that writes text."

### 4.1 — Seed Demo Data
Two test companies (to demo isolation live if asked), sample inventory doc for the RAG tool, a realistic PO reorder scenario, and a pre-populated workflow-exception scenario.

### 4.2 — Demo Script Outline
1. Sign up "Company A," show Ops active by default.
2. Trigger `ops_status_summary` (auto) — instant result, no queue.
3. Ask an inventory question via `inventory_qa` (auto/RAG) — show it's grounded in *this* company's uploaded inventory, not generic.
4. Trigger `vendor_status_update` (template-restricted) — show the constrained template selection, explicitly call out this is a *third*, distinct bucket.
5. **Flagship moment:** trigger `purchase_order_approval` (approval-required) — show the draft, show the blank quantity/amount fields, manually type them in, approve, show the permanent log entry.
6. If time allows: `workflow_exception_approval`, showing the agent's SOP-violation reasoning.
7. Briefly show a second company logged in, unable to see Company A's data.

### ✅ Phase 4 Exit Criteria
- [ ] Full script rehearsed at least twice end-to-end
- [ ] Fallback plan documented if a live LLM call fails mid-demo (pre-recorded backup / cached response)

---

## Phase 5 — Self-Hosted Model Migration (Months 4–6, post-prototype) 🖥️

> **Goal:** Make the "data never leaves our servers" claim actually true — swap the generation call only, per `arch.md`'s forward-compatibility design.

### 5.1 — Synthetic Training Data Generation
```python
# scripts/generate_training_data.py
# Per Decisions Log: NEVER use real company data — synthetic only.
made_up_inventory = load("synthetic_ops_scenarios.md")  # self-written, realistic but fake
qa_pairs = []
for scenario in chunk(made_up_inventory):
    prompt = f"Generate 5 realistic ops questions and ideal agent responses based on: {scenario}"
    qa_pairs += llm_generate_pairs(prompt)  # bootstraps 200–500 pairs, self-supervising via the API
save_jsonl(qa_pairs, "ops_training_data.jsonl")
```

### 5.2 — LoRA Fine-Tuning via Unsloth
```python
from unsloth import FastLanguageModel

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.1-8b-bnb-4bit", max_seq_length=2048, load_in_4bit=True
)
model = FastLanguageModel.get_peft_model(model, r=16, lora_alpha=16,
                                          target_modules=["q_proj","k_proj","v_proj","o_proj"])
# ... standard SFT training loop on ops_training_data.jsonl ...
```

### 5.3 — Evaluation Loop
Hold out 15–20% of the synthetic pairs; compare fine-tuned model output against them manually (human judgment at this scale, per `arch.md`); iterate 2–3 rounds per the Decisions Log estimate.

### 5.4 — Deployment via vLLM
```bash
python -m vllm.entrypoints.openai.api_server \
  --model ./handled-ops-lora-merged --port 8001
```

### 5.5 — Swap the Generation Call (orchestration untouched)
```python
# Only this changes — CrewAI orchestration, tool registry, risk classification: untouched
LLM_ENDPOINT = "http://localhost:8001/v1"  # was the third-party API base URL
```

### ✅ Phase 5 Exit Criteria
- [ ] All 5 tools re-validated against the self-hosted model with no orchestration code changes
- [ ] "Data never leaves our servers" is now a true claim, not a roadmap item

---

## Phase 6 — Multi-Department Expansion (Months 7–12) 🧩

> **Goal:** Prove the fixed-catalog architecture actually scales to a second department without breaking the safety model.

### 6.1 — Second Department Module
Build a full tool registry + agent definition for HR (deprioritized, not abandoned — see Decisions Log), reusing the exact `TOOL_REGISTRY` pattern from Phase 2.

### 6.2 — Real Catalog/Module-Picker UI
Only now justified — with two modules, "Ops active by default" no longer covers it.
```dart
// handled_app/lib/screens/module_picker_screen.dart
// Owner/Admin toggles modules on/off from the fixed catalog — no custom module creation.
```

### 6.3 — Approval-Threshold Configurability
The "someday" feature from Decisions Log — now has two real departments to validate against before generalizing the config schema.

### ✅ Phase 6 Exit Criteria
- [ ] Second department fully operational with its own risk-classified tool set
- [ ] Catalog picker UI live
- [ ] No regression in Phase 1–5 functionality

---

## Phase 7 — Real-World Readiness (remaining runway to 2-year mark) 🚀

> **Goal:** Production-distribution concerns, deferred until there's a real pilot user, not before.

### 7.1 — Code-Signing Certificate
Only pursued once installing on a real pilot company's machine (see earlier honest-tradeoff discussion — skip for the academic prototype).

### 7.2 — Auto-Update Mechanism
Manual redownload was fine through the prototype; revisit with a proper update channel once there are real, non-technical end users.

### 7.3 — Startup India / DPIIT Recognition
Only pursued if this becomes a real company post-graduation.

---

## 📅 Full Project Gantt (2-Year Span)

```mermaid
gantt
  title handled.ai — Full Project Timeline
  dateFormat YYYY-MM-DD
  axisFormat %b %Y

  section Prototype (Sem 5/6)
  Phase 0 - Setup            :done, p0, 2026-08-26, 3d
  Phase 1 - Foundation       :p1, after p0, 14d
  Phase 2 - Tool Buildout    :p2, after p1, 21d
  Phase 3 - Hardening        :p3, after p2, 7d
  Phase 4 - Demo Prep        :p4, after p3, 14d

  section Post-Prototype (Sem 6/7)
  Phase 5 - Self-Hosted Model :p5, after p4, 90d

  section Expansion (Sem 7/8)
  Phase 6 - Multi-Department  :p6, after p5, 180d

  section Real-World (Sem 8+)
  Phase 7 - Prod Readiness    :p7, after p6, 90d
```

---

## ⚠️ Edge Cases & Failure Modes

Explicitly called out per module rather than left implicit:

**Data isolation**
- New table added later without an RLS policy → silent tenant leak. Mitigation: RLS policy is part of the migration checklist template, not optional.
- Two Department Heads approve the same queued item simultaneously (race condition) → row-level `SELECT ... FOR UPDATE` or optimistic locking on `agent_action.status` transitions.

**Agent/LLM layer**
- LLM API call times out or errors mid-task → task marked `drafted`/failed, not silently retried indefinitely (bounded by `CREW_MAX_ITER`); surfaced to the user as a retry option, not an auto-loop.
- Fine-tuned model (Phase 5) performs *worse* than the API baseline on some tool → rollback plan: keep the API-based path available behind a feature flag until the fine-tuned model matches baseline quality on held-out eval.

**Company/module lifecycle**
- Owner deactivates Ops module while actions are still `pending_approval` → those actions should be frozen (visible, not executable) rather than deleted, preserving audit continuity.
- Udyam number fails format validation at signup → signup should not hard-block on this for the prototype (light verification, per `arch.md`), but should flag the field for correction.

**Ops-specific edge cases**
- PO draft triggered for an item with no vendor on file → agent should surface this explicitly, not hallucinate a vendor name.
- Inventory Q&A asked a question about an item not in the uploaded data → RAG retrieval returns nothing relevant → agent should say "no matching inventory record found" rather than fabricating an answer.
- Vendor status update template selected but vendor contact info missing → fail gracefully with a clear error, not send a blank notification.

**Cost/ops**
- API monthly spend cap is hit mid-demo → have the stronger model's cap set generously for demo day specifically (separate from dev-phase cap), and a cached/pre-recorded fallback response for the demo script (Phase 4.2) as a last resort.

**Empty states**
- Approval queue with zero pending items should render a clear empty state, not a blank/broken screen — trivial but easy to skip and embarrassing live.

---

## 🔗 Key File References

| File | Purpose |
|---|---|
| `ps.md` | Problem statement, scope, personas, honest risk register |
| `arch.md` | 4-layer architecture, data model, request lifecycle, risk classification design |
| `handled.ai - Decisions Log.md` | Every confirmed/rejected decision with reasoning — do not re-litigate |
| `handled.ai - Current Tasks.md` | Immediate blockers, Ops tool candidates, learning resources |
| `handled.ai - Project Context.md` | Stable full-picture reference |
| This document | Phase-by-phase build plan, full project span, edge cases |

---
*End*
