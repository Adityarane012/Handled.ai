# Handled.ai Progress Report
**Date:** 2026-08-27 (Week 4 wrap-up)

## Update — 2026-09-19: audit trail, analytics, injection hardening, evals

Five pushes (`4c78a6a`, `4c68080`, `1d77051` and the two fix commits before them).

- **History screen + `GET /ops/history`.** The app could only show *pending*
  approvals — nothing surfaced what ran automatically or what was already
  approved/rejected, i.e. the tiered-autonomy story was invisible. Now: every
  action, bucket + status badges, per-bucket filters.
- **Dashboard analytics + `GET /ops/stats`.** Replaces two near-static cards.
  Aggregates in SQL: per-bucket and per-status counts, `hands_off_rate` (share
  that never needed a human) and `rejection_rate` (of decisions actually made —
  evidence approval isn't a rubber stamp). Both null rather than 0 when there's
  nothing to divide by, so the UI shows "—" not a misleading 0%.
- **`seed_demo.py`** (Plan §4.1): two companies for the live isolation demo, a
  realistic fastener/bearing inventory doc, and a deliberate mix of finished
  history and *pending* approvals so the flagship manual-entry moment is still
  live to perform. Runs through the real API in ~50s, so seeded rows hold
  genuine model output — which doubles as the §4 fallback if a live call fails.
- **`docs/Demo_Script.md`** (Plan §4.2): rehearsable 8–10 min walkthrough with
  what to say during the ~10s generation gaps, plus the documented fallback
  plan the Phase 4 exit criteria require.
- **Prompt-injection hardening.** Uploaded documents are attacker-reachable, so
  retrieved passages are now fenced (BEGIN/END markers, delimiter neutralised
  inside the payload, task restated after the data). Measured against the
  unfenced baseline: **17/18 → 18/18**. The baseline miss was real — an
  injected record made the model report a stock figure of "9999" instead of 46
  in 2 of 3 runs. Small sample; evidence, not a statistical claim.
- **Department routing made real.** `arch.md` §4 claims adding a department is
  "adding rows to this table", but `run_tool` hard-coded `type == "ops"` — a
  second department's audit rows would have filed under Ops. Department now
  comes from the tool's registry row; tests prove the unchanged engine handles
  a second-department tool correctly.
- **Evals added.** `eval_injection.py` and `eval_ops_quality.py`. The latter
  addresses the Plan §5.3 gap: training used all 600 synthetic examples with
  no held-out split, so there was no eval loop at all.

Tests: pytest **27/27**, `test_rls_manual.py` **7/7**.

### Still open
- **Model quality on PO drafts** — see the behavioural eval; the fine-tune
  sometimes restates figures loosely and has produced a wrong part code
  (`B55` → `B52`) at least once. Part codes on an approved PO are a real-world
  wrong-order risk. Worth a dataset pass before the review.
- Visual polish (Inter font is still un-vendored; `withOpacity` deprecations).
- Second department as a *shipped* module is deliberately still Phase 6 — only
  the engine's department-agnosticism has been proven, not an HR/procurement UI.

## Update — 2026-08-31: DB migration applied, real generation confirmed, docs de-staled

- **DB schema migration #1–5 applied** to the live `handled_dev` DB and pushed (`605b9f8`): `agent_action.requested_by`, `UNIQUE(company_id, type)` on `department`, index on `agent_action(company_id, status)`, RLS policy on `company`, approve now flips straight `pending_approval` → `executed` (no intermediate `approved` state — approval IS the send in this prototype). Verified via `pytest` (15/15) and `test_rls_manual.py` (7/7) before pushing.
- **Real LLM generation confirmed working end-to-end** — `handled-ops` (the QLoRA fine-tune from the 2026-08-30 session, commit `3b3ebcb`) is pulled into Ollama and set as `LLM_MODEL`. Smoke test: signup → login → `POST /ops/status-summary` returned real generated bullet-point text (~10s/call), not fallback.
- **Two "known issues" turned out to already be fixed**, just not logged: `inventory_qa`'s distance cutoff (`agent/rag.py::_MAX_DISTANCE`) shipped with the QLoRA commit; `dashboard_shell.dart`'s stat cards already call `/ops/approvals` for a real pending count (not the old placeholder literals). Updated `CLAUDE.md`'s "Known issues" section to drop stale entries so they don't get re-proposed.
- **Still open:** Week 7–8 demo prep (seed data, walkthrough script, rehearsals) — not started.

## Update — 2026-08-27: Phase 2 / Week 4 complete + local-LLM switch

### LLM: switched to local Ollama (no-cost phase)
- `crew.py` now selects the provider from `LLM_PROVIDER` — `ollama` (default), `anthropic`, `openai`, `gemini`. Ollama uses `crewai.LLM(model="ollama/<model>", base_url=OLLAMA_BASE_URL)`.
- `backend/.env`: `LLM_PROVIDER=ollama`, `LLM_MODEL=llama3.2`, `OLLAMA_BASE_URL=http://localhost:11434` (old Anthropic values kept as `# was:` comments).
- **`litellm` was missing** from the venv (CrewAI needs it for every LLM call) — installed (`litellm==1.98.0`).
- If the model/Ollama is unreachable, tools return clearly-labelled fallback text instead of crashing.
- **User action still needed:** install/start Ollama and `ollama pull llama3.2` (or a smaller tag) to get real generation.

### All 5 Ops tools built and wired end-to-end
- New generic dispatcher `agent/crew.py::run_tool(tool_name, context, company_id, db)` — builds the per-tool prompt, looks up the bucket in `TOOL_REGISTRY`, persists the `agent_action` row, sets status.
- `ops_status_summary` (auto) — `POST /ops/status-summary`; summarises recent `agent_action` rows if no log passed.
- `inventory_qa` (auto/RAG) — `POST /ops/inventory-upload` + `POST /ops/inventory-qa`; new `agent/rag.py` (Chroma persistent store at `backend/.chroma/`, per-company collection, default MiniLM embeddings). Retrieval verified.
- `vendor_status_update` (template_restricted) — `POST /ops/vendor-status`; fills one fixed `TOOL_REGISTRY` template, never free-generates. Verified.
- `purchase_order_approval` (approval_required) — refactored onto `run_tool`; quantity/amount stay out of the draft.
- `workflow_exception_approval` (approval_required) — `POST /ops/workflow-exception`; lands in the same approval queue.

### Bugs fixed this session
- `routers/ops/purchase.py` + `approvals.py`: 3-dot relative imports → absolute (app couldn't boot).
- **Auth**: `bcrypt` 5.0.0 broke `passlib` 1.7.4 (72-byte error on hash) → pinned `bcrypt==4.0.1`.
- **RLS post-commit crash**: after `db.commit()` the dotted session GUC reverts to `''`, so `''::UUID` in the policy raised on the next read. Fixed with `NULLIF(current_setting(...), '')::UUID` in `rls_setup.py` (re-applied to the live DB) + `expire_on_commit=False` on both sessions + `flush()`-then-`commit()` in `run_tool`.
- `AgentActionResponse`: `id`/`approved_by` typed `str` vs ORM `UUID` → now `UUID`, `ConfigDict(from_attributes=True)`.
- `ApiService`: added `getList()` for `GET /ops/approvals` (returns an array, not an object).
- `init_db.py` / `rls_setup.py` / `main.py` startup now use the admin (superuser) engine for DDL; `apply_rls()` skips comment-only fragments.
- `requirements.txt` regenerated (was stale UTF-16).

### Verified (in-process TestClient smoke test against local Postgres)
signup → login → `/auth/me` → all 5 tools → approval queue (2 pending) → approve PO with manual quantity+amount → queue drops to 1 → **second company sees 0 of company one's approvals (RLS holds)**. LLM output is fallback text pending Ollama.

### Weeks 0–3 regression check (2026-08-27)
Ran a full Build-Guide Weeks 0–3 verification (`scratchpad/verify_w0_w3.py`, in-process against local Postgres):

**Backend — all PASS:** Phase 0 deps import; `bcrypt` 4.0.x; Postgres reachable as both `postgres` and `handled_app`; 4 tables + columns/constraints; RLS enabled + 3 NULLIF-hardened policies; `/health`; signup → owner_admin + active Ops dept; `/auth/login` JWT with sub/company_id/role; `/auth/me` with & without token; second company's `/ops/approvals` empty (isolation); `TOOL_REGISTRY` PO entry + manual_fields; CrewAI agent constructs; `POST /ops/purchase-order` → `pending_approval` with no quantity/amount in the draft; queue lists it; approve without numbers → 400; approve with numbers → `approved` + `final_output`/approver/timestamp persisted; reject → `rejected` and row retained; Flutter approval-queue safety UI (empty controllers, Approve gated, empty state).

**`test_rls_manual.py` — was FAILing, now fixed & PASSing.** It predated the Phase 1B role split: it seeded fixtures over the RLS-enforced `handled_app` connection with no tenant context, which the hardened policy correctly blocks (`new row violates row-level security policy`). Rewrote it to seed/clean via `admin_engine` and assert isolation over the runtime role; added checks for "no context → 0 rows, no error" and "cross-tenant INSERT blocked". All 7 checks pass.

**Flutter — was broken on this machine (SDK/tooling), now FIXED.** `flutter test` / `flutter build web` were dying in the `objective_c` native-assets hook (transitive via `google_fonts` → `path_provider_foundation`) — the hook path isn't quoted and `C:\Users\Aditya Rane\` has a space (`'C:\Users\Aditya' is not recognized`). Fix applied: **removed `google_fonts`** (only consumer of that chain), theme now uses the bundled default font with a single `_fontFamily` switch in `theme.dart` to re-enable Inter later by vendoring the .ttf. Result: `flutter build web` → `√ Built build\web`. Also replaced the stale `test/widget_test.dart` (referenced a non-existent `MyApp` counter from `flutter create`) with a real smoke test (unauthenticated launch → login screen).

Note: `flutter run -d windows` additionally needs Windows **Developer Mode ON** (plugin symlink support); `-d chrome` / `build web` don't.

---

## Update — 2026-08-27: Week 5 polish + Week 6 (Phase 3) hardening

### Phase 3 test suite — `backend/tests/` (pytest, 15 tests, all green in ~31s)
`pytest` installed; `backend/pytest.ini` added. `conftest.py` runs the real app in-process against local Postgres, stubs `agent.crew._generate` for speed/determinism (opt out with `@pytest.mark.real_llm`), and cleans up every company it creates.
- **`test_tenant_isolation.py`** (Phase 3.1) — B can't see A's approvals; B can't approve A's action (404, A untouched); RLS blocks reads with the app-layer filter removed; RLS blocks cross-tenant INSERT; no-context → 0 rows no error; `/auth/me` scoped to caller.
- **`test_audit_log.py`** (Phase 3.3) — each of the 5 tools writes exactly one `agent_action` row (`inventory-upload` writes none — it only indexes); bucket→status mapping (`auto`/`template` → `auto_executed`, `approval` → `pending_approval`); reject retains the row and preserves `draft_output`, leaves `final_output` null; approve merges the human's quantity/amount into `final_output` without touching `draft_output`.
- **`test_cost_controls.py`** (Phase 3.2) — `CREW_MAX_ITER`/`CREW_MAX_RPM` loaded from `.env` and applied to the agent object; caps within sane bounds; `allow_delegation=False`; `_generate` returns labelled text (doesn't raise/hang) when the model is unreachable; spend-cap env var present.

Manual checklist item still outstanding: set the hard monthly spend cap on the provider billing dashboard (only relevant once back on a paid provider).

### Week 5 — Flutter polish
- **New `OpsToolsScreen`** (`/ops` route, "Ops Tools" in the sidebar) — one card per tool grouped by bucket, with the right input fields, an inventory-doc upload for the RAG tool, inline results for auto/template tools, and "sent to the approval queue" for approval tools. This closes the gap where the app had no way to *trigger* any tool (only the queue was wired) — the demo flow now works end-to-end from the UI.
- **Dashboard** now fetches the real pending-approvals count (was hardcoded `3`/`2`/`14`) and has quick-links to Ops Tools / Approvals.

### Still open
- Real LLM generation needs Ollama running + a model pulled (`ollama pull llama3.2`).
- `inventory_qa` retrieval has no distance threshold — always returns nearest chunks; the "no matching record" refusal relies on the prompt. Add a score cutoff before the demo.
- DB schema migration #1–5 (see below) — proposed, not applied.
- `LICENSE` — none yet; deliberate (maintainer's call).

### Decided
- **Auth: self-hosted JWT for the prototype.** Clerk deferred (revisit only if the incubator wants polished onboarding).

---

## Update — 2026-08-28: Git history + GitHub-ready

- Weeks 3–6 were all uncommitted (the earlier session's Week 3 work was never committed either). Split into a clean linear history and **pushed to `origin/main`** — one commit per week (`89610f2` W3, `01dbb50` W4, `88aac71` W5, `f75da91` W6) plus `4c356fa` docs, `e876603` (README + `.env.example` + `.gitignore` tidy), `c2cd27a` (README polish). Verified the final tree is byte-identical to the pre-split snapshot.
- Added root `README.md` (badges, Mermaid diagrams, quickstart, docs table), rewrote `handled_app/README.md` (was `flutter create` boilerplate), added `backend/.env.example`.
- `.gitignore`: added `.pytest_cache/`, Flutter plugin lockfiles, `.antigravity/`; dropped the empty root `tests/` dir (tests live in `backend/tests/`).

### DB schema migration #1–5 (proposed, not applied)
1. `agent_action.requested_by UUID REFERENCES app_user(id)` — record who triggered an action, not just who approved it.
2. `UNIQUE (company_id, type)` on `department` — prevent duplicate `ops` rows.
3. Index `agent_action (company_id, status)` — the approval-queue query filters on exactly this pair.
4. RLS policy on `company` (`id = NULLIF(current_setting('app.current_company_id', true), '')::UUID`) — the one tenant table without one; signup/login use the superuser engine so unaffected.
5. On approve, flip `approved` → `executed` after the (simulated) send — `executed` exists in the enum but is never reached.

---

## Original report — 2026-08-26

## What has been accomplished so far:

### Phase 0: Foundations (Completed)
- **Backend structure**: Verified `main.py`, models, and database sessions.
- **Tool Registry**: Validated the hard-coded tool autonomy levels (`tool_registry.py`).
- **Dependencies**: Verified Python `venv` environment and necessary backend libraries (FastAPI, SQLAlchemy, psycopg2).

### Phase 1: Prototype Core (In Progress)
- **Phase 1A: Database Foundation (Completed)**
  - Created the `handled_dev` database on PostgreSQL.
  - Reset the Postgres superuser password to `devpass`.
  - Created core tables: `company`, `app_user`, `department`, `agent_action`.
  - Enabled **Row Level Security (RLS)** and created tenant isolation policies.
  - Created a dedicated `handled_app` Postgres role so RLS is strictly enforced at the connection level.
  - Wrote and passed cross-tenant SQL isolation tests.

- **Phase 1B: Auth & Signup (Completed)**
  - Updated `session.py` to route main queries through `handled_app` (RLS) and auth queries through a superuser admin connection.
  - Built `auth.py` router with JWT generation (`/auth/login`) and RLS-tied context (`/auth/me`).
  - Built `company.py` router (`/company/signup`) for new tenant onboarding.
  - Downgraded `bcrypt` to fix a Passlib hashing bug.
  - Successfully tested end-to-end API signup and login with JWTs via Uvicorn.

- **Phase 1C: Flutter App Shell (Started)**
  - Discovered the Flutter SDK at `C:\Users\Aditya Rane\flutter`.
  - Initialized the `handled_app` frontend project for Windows and Web platforms.

## Next Steps
- Build the Flutter UI screens: Signup, Login, and Dashboard Shell.
- Wire the Flutter app to the FastAPI backend using `http` package and JWT interceptors.
- Move to Phase 2: Building the actual Ops Module and Agent Tools.
