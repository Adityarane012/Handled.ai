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
- **Roles are hard-coded too** (`routers/auth.py`): anyone in the company can trigger a tool; only `APPROVER_ROLES` (`owner_admin`, `department_head`) can decide an approval; only the owner adds people. Enforced in the backend (403); the app reads `can_approve`/`can_manage_team` from `/auth/me`.

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
    team.py                GET/POST /company/users — owner adds department_head/staff (RLS session)
    ops/
      purchase.py          POST /ops/purchase-order      (approval_required)
      approvals.py         GET /ops/approvals, POST /ops/approve, GET /ops/history, GET /ops/stats
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
  init_db.py               create tables + apply RLS (new DB only — create_all never ALTERs)
  migrate.py               idempotent ALTERs that bring an EXISTING DB up to the current schema
                           (requested_by, decision_note, dept UNIQUE, queue index, company RLS)
  test_rls_manual.py       raw-SQL cross-tenant isolation proof (fixtures via admin, asserts via runtime role)
  seed_demo.py             Phase 4.1 demo data — 2 companies via the real API (~50s), leaves 2
                           approvals PENDING on purpose for the live demo moment
  eval_injection.py        prompt-injection harness for inventory_qa; --compare scores the
                           pre-fencing prompt against the current one
  eval_ops_quality.py      behavioural eval vs the product's safety claims (PO figure
                           suppression, grounded refusal, no invented numbers/part codes)
  pytest.ini               testpaths=tests
  tests/                   `..\venv\Scripts\python -m pytest` (run from backend/) — 56 tests
    conftest.py            in-process app + Postgres; stubs agent.crew._generate (@real_llm opts out)
    test_tenant_isolation.py   Phase 3.1 adversarial cross-tenant (API + RLS-alone)
    test_audit_log.py          Phase 3.3 audit integrity + /ops/history + /ops/stats
    test_cost_controls.py      Phase 3.2 CREW_MAX_ITER/RPM loaded + applied; failure path bounded
    test_prompt_injection.py   untrusted RAG/log content is fenced, guarded, task restated after
    test_department_agnostic.py  a runtime-registered 2nd-department tool routes correctly
    test_team.py               roles: staff drafts but 403 on approve, dept head approves, owner-only add

handled_app/               Flutter (windows + web are the built platforms)
  lib/
    main.dart              go_router config, auth redirect, ShellRoute
    providers/auth_provider.dart   JWT in shared_preferences, /auth/me check
    services/api_service.dart      ApiService.get/post, baseUrl http://127.0.0.1:8000
    ops_labels.dart                shared bucket/status labels + colours, OpsBadge, StatCard, and
                                   manualFiguresAreUsable() — the approve-gating rule, kept as a
                                   pure function so it's unit-testable rather than in a build method
    screens/
      login_screen.dart, signup_screen.dart
      dashboard_shell.dart         sidebar nav (/ , /ops, /approvals, /history) + DashboardPlaceholder
                                   (autonomy analytics off /ops/stats + by-bucket breakdown)
      ops_tools_screen.dart        /ops — one card per tool, grouped by bucket; triggers all 5
                                   endpoints + inventory-doc upload; inline results
      approval_queue_screen.dart   pending list + _ApprovalCard with manual quantity/amount fields
      team_screen.dart             /team — members + roles; owner-only add-member form
      history_screen.dart          /history — full audit trail, bucket/status badges, filters;
                                   rows open action_detail.dart
      action_detail.dart           showActionDetail() — full record for one action: tier + why,
                                   agent output, what the human typed, trail (who/when/why), raw row
    theme.dart                     AppTheme dark theme; _fontFamily = 'Inter' (vendored in
                                   assets/fonts/, four weights + OFL licence — not google_fonts)
  test/                            `flutter test` — 40 tests
    approval_rules_test.dart       the approve-gating safety rule + tier/status wording coverage
    action_detail_test.dart        renders the audit dialog for each tool shape (catches the
                                   loosely-typed-JSON render errors `flutter build` can't)
    widget_test.dart               unauthenticated launch lands on login

docs/                      Source of truth for scope & decisions (see below)
```

## Environment / running it

- **Python venv:** `C:\Users\Aditya Rane\Downloads\Handled.ai\venv` (Windows: `venv\Scripts\python.exe`). `crewai`, `litellm`, `chromadb`, `anthropic`, `openai`, `pypdf` installed. `bcrypt` is pinned to `4.0.1` (5.x breaks passlib 1.7.4 — do not bump).
- **Backend:** `cd backend && ..\venv\Scripts\uvicorn main:app --reload` → http://localhost:8000 (`/health`, `/docs`).
- **DB:** local Postgres, db `handled_dev`. Runtime connects as non-superuser `handled_app` (RLS enforced); all DDL (`init_db.py`, `rls_setup.py`, startup `create_all`) uses the `postgres` superuser via `admin_engine`. Both URLs in `backend/.env`.
- **First-time DB setup:** `python init_db.py` then `python test_rls_manual.py` (must pass before building on top).
- **Existing DB / after pulling schema changes:** `python migrate.py` (idempotent, safe to re-run). Without it, any `agent_action` write fails with `column "requested_by" does not exist` — the live DB on one machine was migrated by hand, so a second machine needs this.
- **LLM — local Ollama, fine-tuned model:** `.env` has `LLM_PROVIDER=ollama`, `LLM_MODEL=handled-ops`, `OLLAMA_BASE_URL=http://localhost:11434`. `handled-ops:latest` is a fine-tuned Qwen2.5-3B (QLoRA, from `backend/training/`) registered in Ollama from `backend/training/models/handled-ops-qwen2.5-3b/handled-ops-qwen2.5-3b.Q4_K_M.gguf` (gitignored; `ollama create handled-ops -f Modelfile` in that dir). Start Ollama (installed at `C:\Users\Aditya Rane\AppData\Local\Programs\Ollama\ollama.EXE`) before running the backend. Fallbacks: `LLM_MODEL=llama3.2` (base, `ollama pull llama3.2`) or flip `LLM_PROVIDER` to `anthropic`/`openai`/`gemini` + key for a hosted model. If Ollama is down or the model is missing, tools return labelled fallback text — the app still works.
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

## Known issues / not yet done (as of 2026-09-21)

- **`flutter run -d windows` needs Windows Developer Mode ON** (plugin symlink support) — `start ms-settings:developers`. `-d chrome` / `build web` are unaffected.
- **Never re-add `google_fonts`** — its `objective_c` native-assets hook breaks on the space in `C:\Users\Aditya Rane\`. Inter is vendored in `assets/fonts/` instead.
- **PO-draft quality** — the 3B fine-tune has intermittently invented a threshold and mistyped a part code (`B55` → `B52`). Contained by design (human types quantity/amount), but see `eval_ops_quality.py` + `docs/Status_and_Approach.md` §3. Don't retrain unless a `--runs 10` eval shows suite A degrading.
- **Demo not yet rehearsed** — seed script + `docs/Demo_Script.md` exist; the Phase 4 exit criterion (2 end-to-end rehearsals + a practised Ollama-down fallback) is still open.
- **Team members: no email invites, no remove/role-change** — the owner sets a starting password and hands it over; there's no password-reset or deactivate yet. Role in the JWT is read at login, so a (future) role change would need a re-login.
- `crewai` prints noisy `Failed to connect to OpenAI API` lines when Ollama is down — cosmetic; the fallback still fires.
- `LICENSE` — none yet; deliberate (maintainer's call).

Resolved (kept here so nobody re-proposes them): real LLM generation via the fine-tuned `handled-ops` Ollama model (~10s/call); `inventory_qa` distance-cutoff (`agent/rag.py::_MAX_DISTANCE`); `backend/tests/` (56 green); dashboard analytics off `/ops/stats`; DB schema migration #1–5 + `decision_note` (`605b9f8`, `2912689`; `migrate.py` for other machines); Inter vendored; demo seed data + script; signup/login error handling (`75e9e7b`).

## Status (2026-09-21, Phases 0–3 done, Phase 4 ~half — rehearsal remaining)

- **Weeks 0–3** ✅ regression-checked (`scratchpad/verify_w0_w3.py`): deps, DB schema, RLS (enabled + NULLIF-hardened), `/health`, signup→owner+Ops, JWT login, `/auth/me`, tenant isolation, PO tool + approval queue (400 without numbers, approved with, reject retains row), Flutter safety UI. `test_rls_manual.py` was stale (seeded fixtures over the RLS role) — **rewritten** to seed via `admin_engine` + assert over the runtime role; now passes 7/7.
- **Phase 2 / Week 4** ✅ **all 5 Ops tools built + verified end-to-end** (smoke test: signup → 5 tools → approval queue → approve PO with manual numbers → 2nd-company isolation holds). Generic `run_tool()` dispatcher + `TOOL_REGISTRY` lookup + RAG retrieval working. Real LLM output pending Ollama.
- **Flutter builds** — `flutter build web` → `√ Built build\web`; `flutter analyze` clean (only pre-existing infos); `flutter test` passes.
- **Week 5** ✅ `OpsToolsScreen` (`/ops`) added — the app can now trigger all 5 tools + upload an inventory doc from the UI (previously only the approval queue was wired). Dashboard shows the real pending count.
- **Week 6 / Phase 3** ✅ `backend/tests/` pytest suite — 15 tests green (tenant isolation, audit-log integrity, cost-control caps). Run: `cd backend && ..\venv\Scripts\python -m pytest`.
- **Repo** ✅ Weeks 3–6 committed as a clean linear history and **pushed to `origin/main`** (`github.com/Adityarane012/Handled.ai`). Commits: `89610f2` W3, `01dbb50` W4, `88aac71` W5, `f75da91` W6, `4c356fa` docs, `e876603` README/.env.example/.gitignore, `c2cd27a` README polish, `3b3ebcb` QLoRA fine-tuning pipeline, `605b9f8` DB migration #1–5. Root `README.md` + `handled_app/README.md` + `backend/.env.example` in place. No `LICENSE` yet (deliberate — user's call).
- **Fine-tuned model** ✅ `handled-ops` (QLoRA on Qwen2.5-3B-Instruct) is pulled into Ollama and set as `LLM_MODEL` in `.env` (`LLM_PROVIDER=ollama`). Verified 2026-08-31: signup → login → `/ops/status-summary` returns real generated text (~10s/call), not fallback.
- **DB migration #1–5** ✅ applied to the live `handled_dev` DB and pushed (`605b9f8`) — `agent_action.requested_by`, `department` UNIQUE(company_id, type), `agent_action(company_id, status)` index, RLS policy on `company`, approve flips straight to `executed`. Both regression suites green after: `pytest` 15/15, `test_rls_manual.py` 7/7.
- **2026-09-19** ✅ audit trail + analytics + safety hardening (`4c78a6a`, `4c68080`, `1d77051`):
  - `/history` screen and `GET /ops/history` — the full audit trail, which is what actually makes the three-bucket story visible (previously only *pending* approvals were shown).
  - Dashboard analytics off `GET /ops/stats` — per-bucket/status counts, `hands_off_rate`, `rejection_rate` (null not 0 when there's no data).
  - `seed_demo.py` (Plan §4.1) + `docs/Demo_Script.md` (Plan §4.2, incl. the required fallback plan).
  - **Prompt-injection fencing** for RAG/log content, measured: unfenced 17/18 → fenced 18/18. The baseline miss was real (injected record made it report "9999" instead of 46 stock, 2/3 runs).
  - **Department routing fixed** — `run_tool` hard-coded `type == "ops"`, so `arch.md` §4's "just add rows" claim wasn't true in code. Department now comes from the registry row.
  - `eval_injection.py` + `eval_ops_quality.py` — the Plan §5.3 eval loop that training never had.
  - pytest **27/27**, `test_rls_manual.py` 7/7.
- **2026-09-19 (later)** ✅ app depth + polish pass (`e10f5ff` … `2912689`):
  - **Action detail view** (`action_detail.dart`) — clicking a History row shows the tier and why it applied, the agent's output, *what the human typed in* as its own section, the trail (who triggered / who decided / when / why), and the raw stored row. `/ops/history` now returns `requested_by_name` / `approved_by_name` (joinedload'ed).
  - **Approval card reworked** — the agent's draft and the human's figures are visually separate blocks, a confirmation line restates the commitment in the human's own numbers before the button, and a disabled Approve explains itself.
  - **`decision_note`** — why a human approved or rejected, stored permanently and shown in the trail. Live DB migrated.
  - **First-run empty states** — a new company gets the three tiers explained instead of a grid of zeros.
  - **Inter vendored** (4 weights + OFL licence) and switched on; `flutter analyze` now reports **No issues found!** (was 24 lints).
  - **`flutter test` 17** — the approve-gating rule extracted to `manualFiguresAreUsable()` and covered (incl. the "abc → 0" regression), plus widget tests that render the audit dialog for every tool shape.
  - pytest **34/34**.
- **2026-09-21** ✅ second-machine sync + live verification:
  - `migrate.py` — the hand-applied schema changes (#1–5 + `decision_note`) as an idempotent script; this laptop's DB was on the old shape and every `agent_action` write 500'd until it ran.
  - **PO approval enforced server-side** — `/ops/approve` only checked the keys existed, so a direct API call approved a PO for quantity 0 / ₹0 (the Flutter gate was the only guard). Now positive int quantity + positive finite amount, and only those two keys merge into `final_output` (a stray `agent_output` key could overwrite the AI draft in the approved record).
  - **Audit-trail timestamps** — `approved_at` used naive `utcnow()`, which Postgres (tz `Asia/Calcutta`) read as IST, so approvals were filed 5.5h *before* their trigger. Flutter's detail dialog also showed UTC while the History list showed DB wall-clock. Both fixed; one shared `formatTimestamp()` does `toLocal()`.
  - Verified live on `handled-ops`: `seed_demo.py` (0 fallback rows), Flutter web UI (dashboard, approval gating incl. zeros, approve → History → detail trail), cross-tenant approve → 404. pytest **44/44**, `flutter test` **36/36**, `flutter analyze` clean, `test_rls_manual.py` 7/7.
  - **Concurrent decisions** — `/ops/approve` read-then-wrote with no lock; two people deciding at once both got 200 and the second overwrote the first (live: 4/5 trials, once a row marked `rejected` still holding an approved quantity). Now `SELECT … FOR UPDATE`; loser gets 400. pytest **45/45**.
  - **Team members + roles** — `routers/team.py` (owner adds `department_head`/`staff`), staff 403 on `/ops/approve`, `/auth/me` returns `can_approve`/`can_manage_team`, `/team` screen, approval cards say who requested them and are view-only for staff, History rows show "Requested by X · Approved by Y". `seed_demo.py` now adds Amit Patil (staff, drafts the 2 pending items) + Neha Kulkarni (dept head). pytest **56/56**, `flutter test` **40/40**; checked in the web build as staff and as owner.
  - This laptop's Flutter SDK (3.44.6) resolves older `intl`/`matcher` than the committed `pubspec.lock` — don't commit the lock churn from here.
- **Next:** rehearse the demo script end-to-end; address the PO-draft quality findings from `eval_ops_quality.py` (see Progress.md "Still open"). `docs/Status_and_Approach.md` has the per-category plan for the remaining weeks.

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
