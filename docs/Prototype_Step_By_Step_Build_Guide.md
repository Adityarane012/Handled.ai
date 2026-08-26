# handled.ai — Prototype Step-by-Step Build Guide

Scope: **prototype only** (8 weeks / Phases 0–4 of `Implementation_Plan.md`). Not the full 2-year plan. This is the literal, linear "what do I do right now" walkthrough — each step is small enough to finish in one sitting and has a clear way to know it worked before moving to the next one. Detailed code/schema for each step lives in `Implementation_Plan.md`; this document is the execution order.

**How to use this:** work top to bottom. Don't skip ahead to Week 3 tool-building before Week 1's RLS check genuinely passes — the whole safety story depends on isolation being real before anything else is layered on top.

---

## Week 1 — Backend + Database Foundation

1. **Set up the Python environment.** Create the venv, install the Phase 0 dependency list from `Implementation_Plan.md` §0.1. *Done when:* `pip freeze` shows everything installed with no errors.
2. **Get local Postgres running.** Use the Docker command from §0.2. *Done when:* you can `psql` into it from your terminal.
3. **Write the SQLAlchemy models** for `company`, `app_user`, `department`, `agent_action` (§1.2 has the SQL — mirror it in ORM form).
4. **Run the first migration.** *Done when:* all four tables exist and you can see them via `\dt` in `psql`.
5. **Add the RLS policies from §1.2 immediately — before writing a single API route.** This order matters: RLS-first means you can never accidentally build against an unprotected table.
6. **Prove RLS works with raw SQL, no app code involved yet.** Manually insert two fake companies and rows for each, `SET app.current_company_id` to one, and confirm a query for the other returns nothing. *Done when:* you've seen isolation work with your own eyes before any API exists.
7. **Build the FastAPI skeleton + `/health` endpoint.**
8. **Verify:** `uvicorn main:app --reload`, hit `/health`, get `{"status": "ok"}`.

*If stuck on RLS specifically:* this is the one step worth not rushing — re-read `arch.md` §5 and the edge-case note on missing policies in `Implementation_Plan.md` before moving on.

---

## Week 2 — Auth, Signup, and the App Shell

9. **Build the JWT login endpoint** (§1.4).
10. **Build the tenant-context dependency** (§1.3) — this is what actually connects a logged-in user's JWT to the RLS policy at query time. Without this step, RLS is set up but nothing invokes it correctly per-request.
11. **Build the company signup endpoint** (§1.5) — creates company + owner + **Ops department active by default**.
12. **Test the whole backend auth flow with curl/Postman** before touching Flutter: signup → login → hit a protected route → confirm the JWT's `company_id` actually restricts results.
13. **Set up the Flutter project** (§0.3). *Done when:* `flutter run` shows a blank app with no errors, on whichever platform you're demoing on.
14. **Build the signup screen**, wire it to the backend signup endpoint.
15. **Build the login screen**, wire it to login, store the JWT in secure storage.
16. **End-to-end check:** sign up a company from the Flutter app itself, confirm the row lands correctly in Postgres, log back in successfully.

*Phase 1 is done when steps 1–16 all pass.* This matches the Phase 1 exit criteria in `Implementation_Plan.md` — don't move to tools until this is solid.

---

## Week 3 — Approval Queue + Purchase Order (hardest case, deliberately first)

17. **Write the `TOOL_REGISTRY`** (§2.1) — just the `purchase_order_approval` entry for now, rest come in Week 4.
18. **Set up the basic CrewAI agent + task runner** (§2.2), pointed at your third-party LLM API key (Claude Haiku for dev).
19. **Test the PO prompt standalone first** — call the LLM directly with a few sample reorder trigger inputs (item, current stock level, vendor info), read the raw output, before wiring any UI. You're checking prompt quality here, not plumbing.
20. **Wire the PO endpoint into FastAPI** (§2.3), writing to `agent_action` as `pending_approval`.
21. **Build the approval queue screen in Flutter** — list of pending items.
22. **Build the manual-entry fields** for quantity/amount — empty inputs, never pre-filled, per the core safety rule.
23. **Build Approve / Edit / Reject actions**, each updating the `agent_action` row.
24. **End-to-end check:** trigger a PO from the app → see it in the queue → type in quantity and amount yourself → approve → confirm the row flips to `executed` and is still visible in the log afterward.

*This is your flagship demo moment — worth getting genuinely solid before moving on, not just "technically working."*

---

## Week 4 — The Remaining Four Tools

25. **Workflow exception tool** (§2.4) — reuses the approval queue you already built; should be noticeably faster than steps 17–24.
26. **Ops status summary tool** (§2.5, auto bucket) — summarizes task/workflow status from raw activity logs; no approval needed, result logged immediately.
27. **Inventory Q&A / RAG tool** (§2.6) — upload one sample company inventory doc, chunk and embed it, wire basic retrieval, test with 3–4 real questions against it. Must prove real retrieval, not generic answers.
28. **Vendor status update tool** (§2.7, template-restricted) — build the small set of pre-approved templates first, then the selection logic; confirm it never free-generates wording.
29. **Run all 5 tools end-to-end from the app**, back to back, in one sitting — this is your first real dry run of what the demo will feel like.

*If you're behind schedule by the end of this week:* cut the `workflow_exception_approval` tool next, not RLS and not the PO approval flow.

---

## Week 5 — Catch-Up, Polish, Empty States

30. Finish anything from Weeks 3–4 that isn't solid yet — this week exists specifically as slack, don't fill it with new scope if you don't need to.
31. Polish the approval queue UX specifically (it's your highest-visibility screen).
32. Add empty states (zero pending approvals shouldn't look broken) and basic error handling (a failed LLM call shouldn't crash the screen).

---

## Week 6 — Hardening

33. **Write the adversarial cross-tenant tests** (§3.1) — two companies, confirm one genuinely cannot see the other's data, including the RLS-only test that bypasses the app-layer filter deliberately.
34. **Run them. Fix anything that fails** — this is not optional polish, it's the one failure mode that would actually be disqualifying in front of evaluators.
35. **Set the hard monthly spend cap** on your LLM provider's billing dashboard.
36. **Confirm `CREW_MAX_ITER`/`CREW_MAX_RPM`** are actually being respected — deliberately try to trigger a loop and watch it get cut off.
37. **Spot-check the full audit log** across all 5 tools and all 3 buckets — nothing silently missing or overwritten.

---

## Weeks 7–8 — Demo Prep

38. **Seed demo data** — two test companies, sample inventory doc for the RAG tool, a realistic PO reorder scenario, and a workflow exception scenario.
39. **Write the actual demo script**, narrating why each bucket matters, not just what each tool does (see `Implementation_Plan.md` §4.2 for the outline). Lead with `purchase_order_approval` as the flagship moment.
40. **Rehearsal run #1.** Note every hiccup, don't fix live.
41. **Fix what broke in run #1.**
42. **Rehearsal run #2** — should feel materially smoother than #1.
43. **Prepare a fallback** for a live LLM call failing mid-demo (a cached/pre-recorded response you can fall back to) — per the edge-cases section in `Implementation_Plan.md`.

---

## Quick Reference — When You're Stuck
- **RLS/isolation confusion →** `arch.md` §5 + step 6 above (re-verify with raw SQL, not through the app).
- **CrewAI looping/misbehaving →** check `CREW_MAX_ITER`/`CREW_MAX_RPM` are actually loaded from `.env`, not defaulted silently.
- **Not sure what to cut if behind →** Decisions Log: `workflow_exception_approval` first, never RLS, never the PO approval flow.
- **Unsure if a new idea belongs in the prototype →** check `ps.md` §4 "Out of scope" before building it.
