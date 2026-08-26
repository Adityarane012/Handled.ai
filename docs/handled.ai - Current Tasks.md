# handled.ai — Current Tasks

## Immediate Decisions Needed
1. **Set an API-call budget/limit** for development — a hard monthly spend cap on the provider dashboard ($15–20/month) plus CrewAI `max_iter`/`max_rpm` caps.
2. **Postgres RLS** — confirmed decision, build it in Week 1, not retrofitted later.
3. **Code-signing certificate** — skip for the prototype, revisit at real-pilot stage.
4. **App-update mechanism** — manual redownload fine for the prototype.

## Ops Tool Candidates (5, all in scope — mirrors the proven HR bucket split)

**Auto — AI does it, no approval needed:**
- `ops_status_summary` — summarizes task/workflow status from raw activity logs
- `inventory_qa` — answers stock/inventory questions, RAG-grounded against the company's own inventory records

**Template-restricted:**
- `vendor_status_update` — delay/status notification to a vendor, using a small fixed set of pre-approved templates, never freely generated wording

**Needs a Department Head's approval first:**
- `purchase_order_approval` — AI drafts a PO when a reorder trigger fires; Department Head must manually type in quantity and amount before it can be sent (same manual-number-entry rule as HR's offer letter)
- `workflow_exception_approval` — AI evaluates a request against standard SOP and flags/drafts reasoning when it's an exception (e.g. an expedited order, a vendor substitution)

## Month 1 Build Plan (unchanged in structure, Week 3 content updated for Ops)
- **Week 1:** FastAPI skeleton + database tables + login system + Postgres RLS. Flutter skeleton wired to a health check.
- **Week 2:** Company sign-up flow end-to-end, roles/permissions, Udyam number field.
- **Week 3:** Ops module turn-on flow + dashboard + `purchase_order_approval` + approval queue (hardest case, built first).
- **Week 4:** Remaining 4 Ops tools wired end-to-end via the third-party API.

## Phase 2 (post-prototype, not urgent yet)
- Confirmed to start only *after* the prototype.
- Collect 200–500 synthetic "situation → ideal AI response" pairs for Ops (self-written realistic scenarios + AI-generated pairs — never real company data, per Decisions Log).
- LoRA fine-tune via Unsloth, evaluate against held-out examples, deploy via vLLM.

## Concepts Worth Learning While Building This
- **How LLMs work:** *The Illustrated Transformer* (Jay Alammar); Karpathy's "Let's build GPT."
- **Prompt engineering:** Anthropic's prompt engineering guide.
- **AI agents/tools in practice:** Anthropic's "Building Effective Agents."
- **LoRA/fine-tuning** (Phase 2): Unsloth's docs; the original LoRA paper.
- **RAG:** any beginner "RAG from scratch" tutorial; Pinecone's learning center.
- **Multi-tenant isolation & Postgres RLS:** Postgres official docs.
- **FastAPI:** the official tutorial.
- **Claude Code**, since it's now the build tool: `code.claude.com/docs` — start with "How Claude Code works."
