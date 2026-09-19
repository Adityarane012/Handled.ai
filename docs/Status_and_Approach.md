# handled.ai — Status & Recommended Approach by Category

**As of 2026-09-19. Deadline: 2026-10-23 (~5 weeks).**

An honest read of where each part of the project actually stands, and the
approach I'd recommend for each — including what *not* to spend the remaining
weeks on. Written to be argued with, not just followed.

The organising judgement: **the prototype is functionally complete and the
architecture is defensible. The weakest link is now model output quality, and
the highest-leverage remaining work is rehearsal, not features.**

---

## 1. Core prototype — five tools, three buckets, audit trail

**Status: done, and genuinely working.** All five Ops tools run end-to-end from
the Flutter app against a locally fine-tuned model. Every action writes a
permanent `agent_action` row. Bucket assignment is hard-coded in
`tool_registry.py`; the model never classifies its own risk.

**Approach: freeze it.** This is the part that has to work on demo day, and it
does. Every further change here is risk without upside. The only edits worth
making between now and the review are bug fixes found during rehearsal.

**Do not:** add a sixth tool. Five already covers all three buckets, which is
the entire point. A sixth adds demo time and regression surface and proves
nothing new.

---

## 2. Safety & isolation — the actual differentiator

**Status: strongest part of the project.** Postgres RLS as an independent
backstop (proven by tests that deliberately remove the app-layer filter and
still get zero rows), manual-number-entry enforced on binding approvals,
permanent audit rows on every bucket, and now prompt-injection fencing on
attacker-reachable RAG content.

The injection work produced a real measured result rather than an assertion:
unfenced, an injected inventory row made the model report a stock figure of
**9999 instead of 46** in 2 of 3 runs. Fenced, that stopped. (`eval_injection.py
--compare`.)

**Approach: it's done — now make it *legible*.** The work exists but a reviewer
won't find it by reading code. Two cheap, high-return moves:
1. Be able to run `eval_injection.py --compare` live if a technical reviewer
   pushes on safety. It's a genuinely impressive 90 seconds.
2. Keep the honest framing in the Demo Script: the architecture caps the blast
   radius (bucket is hard-coded, generation has no tool access, RLS means other
   tenants aren't in context), and fencing addresses what's left, which is
   answer-content integrity. Claiming more than that invites a takedown.

**Do not:** claim "injection-proof." The sample is 18 checks. Say what was
measured.

---

## 3. Model quality — adequate on safety behaviours, with one hard limit

**Status: better than expected on the safety claims; one genuine capability
ceiling found and handled.**

`train_lora.py` put all 600 synthetic examples into training with **no held-out
split**, so the evaluation loop `Implementation_Plan.md` §5.3 asks for never
happened. `eval_ops_quality.py` now fills that gap with behavioural checks tied
to the product's own safety claims rather than a generic benchmark.

Measured (3 runs per case, `handled-ops` on the laptop GPU):

| Suite | Result |
|---|---|
| A. PO figure suppression | 9/9 |
| B. Grounded refusal | 9/9 |
| C. No invented numbers in summaries | 3/3 |
| D. No invented part codes | 9/9 |
| E. Declines cross-record questions | 9/9 |

**39/39** — every case either answered correctly or refused safely. Treat that
as "no unsafe output observed in 39 checks", not as "the model is safe": 39 is
a small sample, and earlier runs did surface the defects below.

Real defects seen in earlier runs — intermittent, so a clean sweep doesn't mean
they're gone:
- **Invented a threshold.** A PO draft asserted stock had "fallen below the
  threshold of 200 units" when the request never mentioned a threshold.
- **A wrong part code**, twice across ~20 drafts (`V-Belt B55` → `B52`). On an
  approved purchase order a mistyped SKU is a real wrong order.

> **A caution about this harness — read failures before believing them.** Four
> apparent "model defects" this session were bugs in my own checkers: a regex
> that flagged the model for correctly *restating* an input figure; asymmetric
> number extraction that flagged faithful PO references; and twice, a refusal
> detector that scored a perfectly safe refusal as a failure because the model
> had phrased it a new way. The harness prints the failing output for exactly
> this reason. A checker that cries wolf is worse than one that occasionally
> stays quiet.

**The one hard limit — cross-record questions.** Asked "which items are below
their reorder point", the model returned confident, *wrong* lists — naming
items whose stock was several times their reorder point, while displaying
arithmetic that contradicted its own conclusion. This matters more than a
rough draft, because `inventory_qa` is an **`auto` tool: nobody reviews it**.

Fixed on-thesis rather than by hoping: the tool is now instructed to decline
comparison/aggregation questions outright and tell the user to check the list.
Suite E measures that it actually declines. That refusal is a *feature* to
demo, not an apology — it is the same principle as the approval tiers, one
level down: be explicit about what the system may not attempt.

**Approach: do not retrain.** The evidence doesn't support it being the weak
link, and a retrain 5 weeks out is risk for a marginal gain. Instead:
1. Run both evals at `--runs 10` once (~20 min of GPU) for a tighter estimate
   than 3 runs gives.
2. If you want the fine-tuning story stronger, the cheap version is a *data*
   pass — add explicit negative examples for "never state a quantity or a
   threshold" — and retrain once, only if step 1 shows suite A degrading.

**Say this out loud in the review:** the architecture contains these defects by
design — a human types the real quantity and amount regardless of what the
draft says. *"It's a 3B model on a laptop GPU; here is precisely why a wrong
figure in a draft cannot become a wrong purchase order"* is a stronger answer
than pretending the drafts are flawless.

**Do not:** retrain repeatedly on the same 600 examples hoping for improvement.
Without new or corrected data, more epochs only overfit.

---

## 4. Frontend & UX

**Status: functional, consistent, no longer embarrassing.** The raw-JSON vendor
form is gone, errors surface real reasons instead of a generic string, the
approve button is gated on genuinely valid numbers, currency reads ₹, and there
are now History and analytics screens.

**Approach: one focused polish pass, then stop.** Remaining items are small:
vendor the Inter font (`theme.dart` has the switch ready), replace the
deprecated `withOpacity` calls, and add a first-run empty state for a brand-new
company (right now a fresh signup sees mostly zeros and "—"). That last one
matters more than it sounds, because it's literally the first screen a reviewer
sees if they sign up themselves.

**Do not:** redesign. The Linear-style dark theme is coherent and reads as
deliberate. A half-finished redesign three weeks before a review is a classic
self-inflicted wound.

---

## 5. Demo readiness — **highest leverage per hour from here**

**Status: materials ready, rehearsal not started.** `seed_demo.py` produces two
companies with realistic history in ~50s and deliberately leaves two approvals
pending so the flagship manual-entry moment is live. `docs/Demo_Script.md` has
the full walkthrough, lines to fill the ~10s generation gaps, and the fallback
plan the Phase 4 exit criteria require.

**Approach: rehearse twice, end to end, out loud, on the real machine.** This is
the single highest-return use of the remaining time and it is the thing most
likely to be skipped. Specifically:
1. Full cold run — including the startup sequence — timing each section.
2. A deliberate failure run: kill Ollama mid-demo and practise the fallback.
   The Phase 4 exit criteria ask for a documented fallback; a *practised* one is
   what actually saves the review.
3. Have someone else drive the app while you narrate, once. It exposes every
   place the UI needs explaining.

**Do not:** demo from a fresh, empty account. Empty screens make a working
system look unbuilt.

---

## 6. Architecture credibility — the "department-agnostic" claim

**Status: now actually true.** `arch.md` §4 claimed adding a department means
adding rows to the tool table, but `run_tool` hard-coded `Department.type ==
"ops"` — a second department's audit rows would have silently filed under Ops.
Department now comes from the tool's registry row, and tests register a
throwaway second-department tool at runtime to prove the unchanged engine
buckets it, gates it, and files it correctly.

**Approach: keep it as evidence, not as a feature.** The test *is* the artifact.
If asked "how hard is HR?", the answer is "here's a test that adds a
second-department tool and the safety engine handles it untouched."

**Do not:** ship a half-built HR or procurement module. The Decisions Log puts
real departments in Phase 6 and says HR needs further research first; a
skin-deep second department invites "so it doesn't really work yet" and
contradicts your own decision record.

---

## 7. Deliberately out of scope — leave these alone

| Item | Why it stays out |
|---|---|
| Supabase / hosted DB migration | Solves a convenience problem (DB visibility), not a product one. Local Postgres + RLS is the thing being demonstrated. A GUI client solves the same need in 10 minutes with zero architectural risk. |
| Clerk / third-party auth | Decided and deferred. Self-hosted JWT works; swapping auth 5 weeks out is pure risk. |
| Company-configurable thresholds | Explicitly post-prototype in the Decisions Log. |
| vLLM serving | Phase 5. Ollama is sufficient for a laptop demo. |
| A sixth tool / mobile build / LICENSE | No reviewer will ask; each costs time that rehearsal needs more. |

---

## Suggested ordering for the remaining ~5 weeks

1. **Week 1** — Re-seed the demo data (the seed script changed) and run both
   evals at `--runs 10` for a tighter read. UX polish pass (§4), including the
   first-run empty state. Then **freeze the code**.
2. **Week 2** — Rehearse (§5), twice, end to end, out loud, on the real machine.
3. **Week 3** — The deliberate-failure rehearsal: kill Ollama mid-demo and
   practise the fallback until it's boring. Fix only what rehearsal exposes.
4. **Weeks 4–5** — Buffer. Something will break; the buffer is the plan, not
   slack. If it genuinely doesn't, that's when a data pass + single retrain
   (§3) becomes worth considering — not before.

The temptation will be to keep adding. The project's problem is no longer
"not enough built" — it's "not enough practised."

---

## A note on how the findings above were produced

Most of the real defects this week were found by *building the measurement
first and then reading the failures*, not by inspection:

- The prompt-injection fix only proved itself because the harness could also
  run the **unfenced** prompt — which is how the 9999-instead-of-46 failure
  surfaced at all.
- The RAG chunking bug surfaced from checking the *seeded demo data* rather
  than the code; the tool was answering "no matching inventory record" to
  questions the document plainly answered.
- The cross-record capability ceiling only appeared *after* the chunking fix —
  the previous bug had been masking it behind a refusal that looked correct.
- Two apparent model defects turned out to be bugs in the checkers.

Worth keeping as a habit: when a result looks good, check whether the
measurement can fail; when it looks bad, check the measurement before the
model.
