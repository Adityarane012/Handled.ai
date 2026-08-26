# handled.ai — Decisions Log

A record of what's been decided and why — so nothing already settled gets re-litigated or re-suggested by mistake.

---

## Naming & Direction
| Decision | Status |
|---|---|
| Project idea | Pivoted from **TradeIQ** (fintech education) → **Sambandh AI** (BD agent for EPC SMEs) → **handled.ai** (general multi-department AI platform) |
| Final project name | **handled.ai** — confirmed, final |
| Insteel Engineers involvement | **Fully dropped.** Was only ever a placeholder pilot partner during the Sambandh AI phase. Not part of this project. Its data/logins must never be reused here (confidentiality risk from the separate internship). |

## Explicitly Rejected (do not re-suggest)
| Rejected | Reasoning |
|---|---|
| Training an LLM from scratch | Too expensive and too slow — infeasible even across the full 2-year timeline. |
| Self-hosting/fine-tuning within the 2-month prototype window | Re-raised and re-rejected a second time — correctly identified as too time-consuming for this phase both times. Third-party API stands for the prototype; self-hosting is Phase 2, post-prototype, no exceptions. |
| Third-party AI APIs in the **final, real product** | Real client data must never leave the company's own servers — core to the DPDP-compliance pitch. |
| React / React Native for the app | Flutter gives phone + desktop from one codebase; React/RN would need Electron bolted on for desktop plus RN separately for mobile. |
| Mixing the marketing website with the product app | Kept as fully separate components. |
| Letting companies invent their own custom departments | Safety decision — risk classification has to be centrally and reliably judged, not left to the AI or to each company. |

## Explicit Exception (allowed, scoped narrowly)
| Decision | Reasoning |
|---|---|
| **Third-party AI API allowed for the 2-month prototype only** (Claude or GPT) | No real company data involved yet, so the privacy concern doesn't apply. Frees up time for building the actual product instead of a fine-tuning pipeline this early. Self-hosted model remains the Phase 2 plan. |

## Confirmed Technical Direction
| Area | Decision |
|---|---|
| App framework | Flutter (Dart) |
| Backend | FastAPI (Python) |
| Database | PostgreSQL with Row-Level Security |
| Agent orchestration | CrewAI (primary), LangGraph (fallback) |
| Fine-tuning tool (Phase 2 only) | Unsloth (primary), LLaMA-Factory (backup) |
| Serving | Ollama (dev), vLLM (concurrent load) |
| Boilerplate strategy | No combined Flutter+FastAPI SaaS starter exists (confirmed via research) — FastAPI SaaS backend starter + separate Flutter starter, connected manually |

## Auto vs. Approval Rule (stable across all department pivots — this is department-agnostic)
- Three buckets: auto → template-restricted (fixed/legally-reviewed wording only) → approval-required (binding, hard to undo, or freely AI-generated external wording).
- For any action involving money or dates, the human approver types the actual number in themselves — never a single-click approval on an AI-guessed number.
- Every action logged permanently regardless of bucket, non-negotiable.
- Risk classification hard-coded per action in code, never decided by the AI at runtime.
- Company-configurable approval thresholds: post-prototype "someday" feature, confirmed to stay out of scope.

## Department Scope for the Demo — REVISED (pivot #2)
- **v1:** Two modules considered (Support/Client Comms + Ops/Tracking).
- **v2:** Narrowed to a single department — **HR** — based on real ERPNext HR configuration experience.
- **v3 (current, final):** **Pivoted from HR to Ops.** Reasoning:
  - Mentor is advising against HR ahead of the incubator review — this is a direct external constraint, not just a strategic preference, and takes precedence.
  - Independent competitive research (done before this pivot) found HR crowded at the "general AI employee" layer (Zencia AI, an unnamed YC company) but not specifically on the tiered-autonomy/audit-trail architecture — the HR gap was about positioning, not a dead end. Ops was not disqualified by research; it simply wasn't chosen at that point.
  - Broader finding from that research, still true and still the operating thesis: **every SME-department AI category in India is crowded to some degree by 2026** (HR, logistics/shipping, WhatsApp support — the last one especially, since Meta shipped native "Business AI" into WhatsApp Business itself — procurement, and general back-office/ops automation, which is fragmented across implementer agencies rather than owned by one dominant product). The differentiator was never going to be "picked an empty department" — it's the fixed-catalog + tiered-autonomy + audit-trail **architecture**, which holds regardless of which department is built first.
- **Ops tools (5, mirroring the proven HR structure — 2 auto / 1 template-restricted / 2 approval-required):**
  - `ops_status_summary` (auto) — summarizes task/workflow status from raw activity logs.
  - `inventory_qa` (auto, RAG) — answers stock/inventory questions grounded in the company's own inventory records.
  - `vendor_status_update` (template_restricted) — delay/status notification to a vendor using pre-approved templates.
  - `purchase_order_approval` (approval_required, manual_fields: quantity, amount) — drafts a PO when a reorder trigger fires; human types in quantity/amount.
  - `workflow_exception_approval` (approval_required) — flags and drafts reasoning when a request breaks standard SOP (e.g. expedited order, vendor substitution).
- HR is not abandoned — deprioritized to a later department addition, pending further research, once the catalog architecture (Phase 6 in the Implementation Plan) is in place.
