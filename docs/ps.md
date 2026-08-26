# handled.ai — Problem Statement

## 1. Problem Statement
Small and mid-size Indian companies (roughly 10–100 employees) routinely operate without dedicated departmental staff — HR, admin, support, ops — because hiring a full-time specialist for each function isn't affordable at their scale. Operations/logistics coordination — tracking task status, monitoring stock, chasing vendors for delayed shipments, raising purchase orders — is one of the most immediate instances: it happens informally, inconsistently, or falls entirely on the owner.

## 2. Background & Motivation
Existing "AI employee" and AI-copilot products either assume a company already has staff to *assist*, or offer full autonomy with no credible way to earn a small business owner's trust with no oversight — a model shown to struggle with retention even among well-funded players, because most operational work involves judgment and consequences that shouldn't run unsupervised. Neither model fits a company with *no* existing ops staff and *low* tolerance for an unsupervised AI committing to a purchase order or vendor agreement in its name.

## 3. Objectives
- Give companies with no dedicated ops/logistics staff a way to get that work done via an AI agent, without needing to hire before they can afford to.
- Keep a human explicitly in control of anything external-facing, financially binding, or hard to undo.
- Build this so it scales to multiple departments (HR included, later) without the safety model breaking down.

## 4. Scope (2-month prototype)
**In scope:**
- Single department module: **Ops**.
- Company registration, role-based access (Owner/Admin, Department Head, Staff).
- 5 Ops tools spanning all three autonomy buckets: `ops_status_summary` (auto), `inventory_qa` (auto/RAG), `vendor_status_update` (template-restricted), `purchase_order_approval` (approval-required, manual quantity/amount entry), `workflow_exception_approval` (approval-required).
- Approval queue with inline edit and mandatory manual entry of key numbers on binding drafts.
- Third-party AI API for generation (explicit, scoped exception — see Decisions Log).

**Out of scope for the prototype:**
- Self-hosted/fine-tuned model (Phase 2).
- HR or any other department module (deprioritized, not abandoned — see Decisions Log).
- Company-configurable approval thresholds.
- Code-signing, auto-update, and other production-distribution concerns.

## 5. Target Users
- **Owner/Admin** — a small business owner without budget for a dedicated ops/logistics hire.
- **Department Head** — whoever ends up owning ops-adjacent responsibility, often informally.
- **Staff** — day-to-day requesters of AI-assisted ops tasks.

## 6. Proposed Solution (summary)
A registered company activates a pre-built Ops module. Low-risk internal actions (status summaries, inventory Q&A grounded in the company's own stock records) execute automatically. External-facing but low-stakes actions (a vendor delay notification) are restricted to pre-approved templates. Anything binding or hard to undo (a purchase order, an SOP exception) is drafted by the AI but requires a human — who manually enters key figures — to approve. See `arch.md`.

## 7. Success Criteria (for the 2-month demo)
- A company can register, activate Ops, and use all 5 tools end-to-end.
- All three autonomy buckets are demonstrably distinct in the live demo.
- No cross-company data leakage under adversarial testing.
- The approval queue is usable enough for a non-technical evaluator to operate without explanation.

## 8. Honest Risks & Limitations
- **This is the second department pivot.** HR work is not wasted (the underlying architecture is identical, department-agnostic) but Ops-specific tool prompts/testing start from zero.
- **No SME-department AI category is genuinely uncontested in 2026** — logistics/shipping-aggregator tools (Shiprocket, Pickrr, ClickPost) are a mature, funded, adjacent field, though they solve outbound e-commerce shipping, not internal ops/inventory/PO coordination specifically, which is a narrower and less mapped slice.
- **The prototype cannot yet make its self-hosted/data-sovereignty claim true** — third-party API only, roadmap item not a working fact, per Decisions Log.
- **Solo/small-team execution risk against a hard 2-month deadline**, now further compressed by this pivot.

## 9. Timeline Summary
2-year total project. Prototype compressed to a **2-month, 8-week window** — same phase structure as before (foundation → tool buildout, hardest-first → hardening → demo prep), now built against Ops tools instead of HR. See `arch.md` and `Implementation_Plan.md`.
