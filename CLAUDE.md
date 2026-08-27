# handled.ai

AI-assisted **Ops** module for small Indian SMEs (10–100 employees) with no dedicated ops/logistics staff. A company signs up, the Ops department is active by default, and an AI agent handles routine work. The safety model is the product: every AI action falls into one of three hard-coded autonomy buckets, and anything binding or hard to undo needs a human to approve it — and to type the key numbers in themselves.

- **Type:** B.Tech degree project (Design Experience, sem 4–8). Solo / small team. 2-year total timeline.
- **Now:** 8-week prototype (Phases 0–4). Shown to an incubator — the tiered-autonomy + audit-trail *architecture* is the differentiator, not the department chosen.
- **Today's north star:** all 5 Ops tools working end-to-end from the Flutter app, with real cross-tenant isolation.

## The three autonomy buckets (department-agnostic, never re-litigate)

| Bucket | Rule | Ops tools |
|---|---|---|
| `auto` | Internal, low-risk, easy to undo. Runs immediately, logged. | `ops_status_summary`, `inventory_qa` (RAG) |
| `template_restricted` | External-facing but low-stakes. Wording is a **fixed pre-approved template**, never freely AI-generated. | `vendor_status_update` |
| `approval_required` | Binding, financial, hard to undo, or free external wording. Drafted by AI, queued for a human. | `purchase_order_approval` (manual_fields: quantity, amount), `workflow_exception_approval` |

Non-negotiable rules:
- The bucket for each tool is **hard-coded in `backend/agent/tool_registry.py`** — the LLM never classifies its own action at runtime.
- **Every** action writes a permanent `agent_action` row, regardless of bucket. Never deleted or overwritten on reject/edit.
- For money/dates: the AI writes the wording, the **human types the actual number** in the approval screen. Fields render **empty, never pre-filled** with an AI guess. Approve button stays disabled until they're filled.
- No batch approval in the prototype.

## Architecture — 4 layers, kept separate on purpose

```
Flutter app  →  FastAPI backend  →  Agent layer  →  PostgreSQL
(screens only)   (auth, roles,      (CrewAI orch.    (source of truth,
                  tenant scoping)    + LLM API call)   RLS-enforced)
```

- **Flutter** — screens only, zero business logic. Every button is a backend request.
- **FastAPI** — JWT auth, role check, per-request tenant scoping (sets the Postgres RLS session var).
- **Agent layer** — two halves kept swappable: (a) CrewAI *orchestration* picks the tool, builds the prompt, does RAG, looks up the bucket; (b) *generation* is a plain third-party LLM call with no DB/rules awareness. Phase 5 swaps (b) for a self-hosted model without touching (a).
- **PostgreSQL** — 4 tables: `company`, `app_user`, `department`, `agent_action`. Schema is department-agnostic by design.

## Repo layout

```
backend/
  main.py                  FastAPI entrypoint, registers routers, /health
  routers/
    auth.py                /auth/login (admin session), /auth/me, get_tenant_ctx dependency
    company.py             /company/signup — creates company + owner_admin + active Ops dept
    ops/
      purchase.py          POST /ops/purchase-order      (approval_required)
      approvals.py         GET /ops/approvals, POST /ops/approve
      status.py            POST /ops/status-summary      (auto)
      inventory.py         POST /ops/inventory-upload, POST /ops/inventory-qa  (auto/RAG)
      vendor.py            POST /ops/vendor-status       (template_restricted)
      exception.py         POST /ops/workflow-exception  (approval_required)
  agent/
    tool_registry.py       TOOL_REGISTRY — the hard-coded risk table. get_tool_config/get_action_type
    crew.py                run_tool(tool_name, ctx, company_id, db) — the ONE entry point every ops
                           router calls. Per-tool prompt builders + template fill. Provider via
                           LLM_PROVIDER (ollama default). _generate() never raises — returns
                           labelled fallback text when the model is unreachable.
    rag.py                 inventory_qa store: Chroma persistent client (backend/.chroma/),
                           per-company collection. index_inventory_document / retrieve_inventory_chunks
  models/
    db_models.py           SQLAlchemy ORM (Base, Company, AppUser, Department, AgentAction)
    schemas.py             Pydantic request/response models
  db/
    session.py             engine (handled_app role, RLS on) + admin_engine (postgres, RLS bypass).
                           get_db / get_admin_db / set_tenant_context (SET LOCAL)
    rls_setup.py           apply_rls() — idempotent policy DDL
  init_db.py               create tables + apply RLS
  test_rls_manual.py       raw-SQL cross-tenant isolation proof (fixtures via admin, asserts via runtime role)
  pytest.ini               testpaths=tests
  tests/                   Phase 3 hardening — `..\venv\Scripts\python -m pytest` (run from backend/)
    conftest.py            in-process app + Postgres; stubs agent.crew._generate (@real_llm opts out)
    test_tenant_isolation.py   Phase 3.1 adversarial cross-tenant (API + RLS-alone)
    test_audit_log.py          Phase 3.3 every tool writes a row; reject/approve preserve the draft
    test_cost_controls.py      Phase 3.2 CREW_MAX_ITER/RPM loaded + applied; failure path bounded

handled_app/               Flutter (windows + web are the built platforms)
  lib/
    main.dart              go_router config, auth redirect, ShellRoute
    providers/auth_provider.dart   JWT in shared_preferences, /auth/me check
    services/api_service.dart      ApiService.get/post, baseUrl http://127.0.0.1:8000
    screens/
      login_screen.dart, signup_screen.dart
      dashboard_shell.dart         sidebar nav (/ , /ops, /approvals) + DashboardPlaceholder
                                   (real pending-approvals count + quick links)
      ops_tools_screen.dart        /ops — one card per tool, grouped by bucket; triggers all 5
                                   endpoints + inventory-doc upload; inline results
      approval_queue_screen.dart   pending list + _ApprovalCard with manual quantity/amount fields
    theme.dart                     AppTheme dark theme (bundled font; _fontFamily switch for Inter)

docs/                      Source of truth for scope & decisions (see below)
```

## Environment / running it

- **Python venv:** `C:\Users\Aditya Rane\Downloads\Handled.ai\venv` (Windows: `venv\Scripts\python.exe`). `crewai`, `litellm`, `chromadb`, `anthropic`, `openai`, `pypdf` installed. `bcrypt` is pinned to `4.0.1` (5.x breaks passlib 1.7.4 — do not bump).
- **Backend:** `cd backend && ..\venv\Scripts\uvicorn main:app --reload` → http://localhost:8000 (`/health`, `/docs`).
- **DB:** local Postgres, db `handled_dev`. Runtime connects as non-superuser `handled_app` (RLS enforced); all DDL (`init_db.py`, `rls_setup.py`, startup `create_all`) uses the `postgres` superuser via `admin_engine`. Both URLs in `backend/.env`.
- **First-time DB setup:** `python init_db.py` then `python test_rls_manual.py` (must pass before building on top).
- **LLM — local Ollama (no-cost phase):** `.env` has `LLM_PROVIDER=ollama`, `LLM_MODEL=llama3.2`, `OLLAMA_BASE_URL=http://localhost:11434`. To get real generation: start Ollama (installed at `C:\Users\Aditya Rane\AppData\Local\Programs\Ollama\ollama.EXE`) and `ollama pull llama3.2` (or a smaller tag like `llama3.2:1b` / `qwen2.5:3b`). Until then, tools return labelled fallback text — the app still works. Flip `LLM_PROVIDER` back to `anthropic`/`openai`/`gemini` + set the key to use a hosted model.
- **`inventory_qa` RAG:** first call downloads the MiniLM ONNX embedding model (~80 MB, one-time, then offline). Vectors persist in `backend/.chroma/` (gitignored).
- **Flutter:** `cd handled_app && flutter run -d windows` (or `-d chrome`). SDK at `C:\Users\Aditya Rane\flutter`.
- **CrewAI caps:** `CREW_MAX_ITER=6`, `CREW_MAX_RPM=10`, `LLM_MONTHLY_SPEND_CAP_USD=20` (only relevant on a paid provider).
- **Third-party LLM API is a scoped prototype-only exception.** The real product self-hosts (Phase 5). Don't market the prototype as "data never leaves our servers" — not true yet.

## Conventions

- **Backend imports are absolute**, rooted at `backend/` (e.g. `from db.session import get_db`, `from routers.auth import get_tenant_ctx`). Do **not** use relative imports in routers.
- Any new tenant-scoped table **must** get an RLS policy in `rls_setup.py` in the same change — it's part of the migration, not a follow-up.
- New tool = new explicit row in `TOOL_REGISTRY` with a human-decided `action_type`. Never infer it.
- Route the agent through `crew.py`; keep generation free of any DB or rules knowledge.
- Flutter stays logic-free — new behavior goes in the backend.
- Timeline pressure is real. When behind, cut `workflow_exception_approval` first — **never** cut RLS work or the PO approval flow.

## Known issues / not yet done (as of 2026-08-28)

- **LLM generation is fallback-text only until Ollama runs** — start Ollama + `ollama pull llama3.2`, then re-run the smoke test.
- **`flutter run -d windows` needs Windows Developer Mode ON** (plugin symlink support) — `start ms-settings:developers`. `-d chrome` / `build web` are unaffected.
- `google_fonts` was removed (its `objective_c` native-assets hook breaks on the space in `C:\Users\Aditya Rane\`). Theme uses the bundled default font; flip `_fontFamily` in `theme.dart` to `'Inter'` after vendoring `Inter-*.ttf` into `assets/fonts/` + declaring it in `pubspec.yaml`.
- **`inventory_qa` retrieval has no distance threshold** — Chroma always returns the nearest chunks, so "no matching record" relies on the prompt telling the model to refuse. Add a score cutoff in `agent/rag.py::retrieve_inventory_chunks` before the demo.
- **`tests/` is still empty** — Phase 3 adversarial cross-tenant tests not written. `scratchpad/smoke_week4.py` (in the session scratchpad) is the current stopgap; port it into `tests/` with pytest.
- `dashboard_shell.dart` stat cards are placeholder literals (`3`, `2`, `14`); no dashboard screen calls the tool endpoints yet — only the approval queue is wired.
- Signup/login screens not reviewed in depth.
- `crewai` prints noisy `Failed to connect to OpenAI API` lines when Ollama is down — cosmetic; the fallback still fires.
- Auth strategy not finalised — see below.

## Status (2026-08-28, Weeks 0–6 done)

- **Weeks 0–3** ✅ regression-checked (`scratchpad/verify_w0_w3.py`): deps, DB schema, RLS (enabled + NULLIF-hardened), `/health`, signup→owner+Ops, JWT login, `/auth/me`, tenant isolation, PO tool + approval queue (400 without numbers, approved with, reject retains row), Flutter safety UI. `test_rls_manual.py` was stale (seeded fixtures over the RLS role) — **rewritten** to seed via `admin_engine` + assert over the runtime role; now passes 7/7.
- **Phase 2 / Week 4** ✅ **all 5 Ops tools built + verified end-to-end** (smoke test: signup → 5 tools → approval queue → approve PO with manual numbers → 2nd-company isolation holds). Generic `run_tool()` dispatcher + `TOOL_REGISTRY` lookup + RAG retrieval working. Real LLM output pending Ollama.
- **Flutter builds** — `flutter build web` → `√ Built build\web`; `flutter analyze` clean (only pre-existing infos); `flutter test` passes.
- **Week 5** ✅ `OpsToolsScreen` (`/ops`) added — the app can now trigger all 5 tools + upload an inventory doc from the UI (previously only the approval queue was wired). Dashboard shows the real pending count.
- **Week 6 / Phase 3** ✅ `backend/tests/` pytest suite — 15 tests green (tenant isolation, audit-log integrity, cost-control caps). Run: `cd backend && ..\venv\Scripts\python -m pytest`.
- **Repo** ✅ Weeks 3–6 committed as a clean linear history and **pushed to `origin/main`** (`github.com/Adityarane012/Handled.ai`). Commits: `89610f2` W3, `01dbb50` W4, `88aac71` W5, `f75da91` W6, `4c356fa` docs, `e876603` README/.env.example/.gitignore, `c2cd27a` README polish. Root `README.md` + `handled_app/README.md` + `backend/.env.example` in place. No `LICENSE` yet (deliberate — user's call).
- **Next:** Week 7–8 demo prep (seed data, demo script, rehearsals) — see `Implementation_Plan.md` §4. Start Ollama + `ollama pull llama3.2` for real LLM output. Provider-side spend cap is a manual checklist item (only matters on a paid provider). Optional: the DB migration #1–5 from the schema review below.

### DB schema migration #1–5 (proposed, not applied)

Small migration worth doing before the demo — details in `docs/Progress.md`:
1. `agent_action.requested_by UUID REFERENCES app_user(id)` — audit trail wants "who triggered", not just "who approved".
2. `UNIQUE (company_id, type)` on `department` — nothing stops two `ops` rows.
3. Index `agent_action (company_id, status)` — the approval-queue query filters on exactly this.
4. RLS policy on `company` too (`id = NULLIF(current_setting('app.current_company_id', true), '')::UUID`) — the one tenant table with no policy; signup/login use the superuser engine so unaffected.
5. On approve, flip status `approved` → `executed` after the (simulated) send — the `executed` state exists in the enum but is never reached.

## Auth — decided

**Self-hosted JWT for the prototype** (confirmed 2026-08-28): `python-jose` HS256 + `passlib`/`bcrypt`, users in `app_user`. Works, free, no third-party dependency. Clerk was considered (hosted login UI / social / MFA) but deferred — revisit only if the incubator wants polished onboarding; it would need Clerk-JWT verification in `get_tenant_ctx` + a webhook to mirror users into `app_user` so RLS/FKs still hold.

## Doc map (`docs/`)

| File | What it's for |
|---|---|
| `ps.md` | Problem statement, scope in/out, personas, honest risks |
| `arch.md` | 4-layer architecture, data model, request lifecycle, **risk classification table (§4)** |
| `Implementation_Plan.md` | Phase-by-phase build plan (0–7), code sketches per tool, edge cases, Gantt |
| `Prototype_Step_By_Step_Build_Guide.md` | Linear week-by-week "what do I do next", 43 numbered steps |
| `handled.ai - Decisions Log.md` | Every confirmed/rejected decision + why — **check before proposing anything "new"** |
| `handled.ai - Current Tasks.md` | Immediate decisions, tool candidates, learning resources |
| `handled.ai - Project Context.md` | Stable full-picture reference (note: still HR-worded in places; Ops is current) |
| `Progress.md` | Running progress log |
| `project.md` | Early combined summary (HR-era; superseded by the Ops pivot) |

**Pivot history:** TradeIQ (fintech-ed) → Sambandh AI (BD agent for EPC) → handled.ai. Department: two modules → HR → **Ops** (current, final — mentor advised against HR before the incubator review). HR is deprioritized, not abandoned (Phase 6). Insteel Engineers is fully dropped; never reuse its data/logins.

## External tools

- **One CLI (`one`)** is installed — use it for any third-party platform/API interaction (Gmail, Slack, Stripe, GitHub, etc.). See `.agents/rules/one_cli.md`.
