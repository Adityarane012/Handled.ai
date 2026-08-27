# handled.ai

An AI operations assistant for small Indian companies (roughly 10–100 employees)
that don't have dedicated ops/logistics staff. A company signs up, the **Ops**
department is active by default, and an AI agent handles routine work — while a
human stays firmly in control of anything binding or hard to undo.

The safety model *is* the product. Every AI action falls into one of three
hard-coded autonomy buckets, and the risk classification lives in code, never in
the model's judgement.

| Bucket | Rule | Ops tools |
|---|---|---|
| **auto** | Internal, low-risk, easily undone. Runs immediately, always logged. | `ops_status_summary`, `inventory_qa` (RAG) |
| **template-restricted** | External-facing but low-stakes. Wording is a fixed, pre-approved template — never freely generated. | `vendor_status_update` |
| **approval-required** | Binding, financial, hard to undo, or free external wording. The AI drafts; a human approves. | `purchase_order_approval`, `workflow_exception_approval` |

Non-negotiable rules:

- The bucket for each tool is hard-coded in `backend/agent/tool_registry.py`.
- **Every** action writes a permanent `agent_action` row, regardless of bucket.
- For money/dates the AI writes the wording, but the human **types the actual
  numbers in** at approval time — no rubber-stamping an AI guess.

> **Status:** academic prototype (B.Tech design project). It uses a third-party
> LLM API (or a local model) for generation — the "your data never leaves your
> servers" positioning is a later, self-hosted phase and is **not** true of this
> prototype.

## Architecture

```
 Flutter app   →   FastAPI backend   →   Agent layer        →   PostgreSQL
 (screens only)    (JWT auth, RBAC,      (CrewAI orchestration   (source of truth,
                    tenant scoping)       + LLM generation)        RLS-enforced)
```

The agent layer keeps orchestration (tool choice, prompt building, RAG, bucket
lookup, persistence) separate from generation (a plain LLM call with no DB or
rules awareness) so the model can be swapped without touching the rest.

Tenant isolation is enforced twice: application-level `company_id` scoping **and**
PostgreSQL Row-Level Security as an independent backstop. The runtime connects as
a non-superuser role so RLS always applies; a superuser connection is used only
for DDL.

## Repo layout

```
backend/            FastAPI service
  main.py             app + routers + /health
  routers/            auth, company, ops/ (one file per tool)
  agent/              crew.py (run_tool dispatcher), rag.py, tool_registry.py
  models/             SQLAlchemy ORM + Pydantic schemas
  db/                 session (engine + admin_engine), rls_setup
  tests/              Phase 3 hardening — pytest
handled_app/         Flutter app (Windows + Web)
  lib/screens/        login, signup, dashboard, ops tools, approval queue
docs/                problem statement, architecture, decisions log, plan, progress
CLAUDE.md            working notes for AI assistants / contributors
```

## Getting started

### Prerequisites

- Python 3.12, PostgreSQL 16
- Flutter 3.4+ (for the app)
- Optional: [Ollama](https://ollama.com) for local, no-cost LLM generation

### Backend

```bash
cd backend
python -m venv ../venv
../venv/Scripts/activate            # Windows;  source ../venv/bin/activate on *nix
pip install -r requirements.txt

cp .env.example .env                # then edit: DB URLs, JWT_SECRET, LLM provider
python init_db.py                   # create tables + apply RLS policies
python test_rls_manual.py           # prove tenant isolation before building on it

uvicorn main:app --reload           # http://localhost:8000  (/docs for Swagger)
```

Database roles: create a superuser DB `handled_dev` plus a non-superuser role
`handled_app` that owns nothing — the app connects as `handled_app` so RLS is
enforced; `init_db.py` / migrations use the superuser.

### LLM

Default is local Ollama (`LLM_PROVIDER=ollama`). Start Ollama and pull a model:

```bash
ollama pull llama3.2          # or a smaller tag: llama3.2:1b, qwen2.5:3b
```

Without a reachable model the tools still work — they return clearly-labelled
fallback text instead of crashing. Set `LLM_PROVIDER` to `anthropic` / `openai` /
`gemini` (plus the API key) to use a hosted model.

### Flutter app

```bash
cd handled_app
flutter pub get
flutter run -d chrome         # or -d windows (needs Windows Developer Mode ON)
```

## Testing

```bash
cd backend
../venv/Scripts/python -m pytest        # Phase 3: isolation, audit log, cost controls
python test_rls_manual.py               # raw-SQL RLS proof

cd ../handled_app
flutter analyze && flutter test
```

## Roadmap

- **Now** — 8-week prototype: 5 Ops tools, approval queue, multi-tenant isolation, demo.
- **Next** — self-hosted LoRA-fine-tuned model via vLLM (makes the data-sovereignty claim real).
- **Later** — second department module + a real module picker; configurable approval thresholds.

See `docs/Implementation_Plan.md` for the full phase plan and `docs/Progress.md`
for what's built.
