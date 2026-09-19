# handled.ai — Incubator Demo Script

Phase 4.2 of `Implementation_Plan.md`. Target length **8–10 minutes** talking, plus questions.

The point of the demo is **not** "an AI that writes text." Every reviewer has seen that.
The point is: *this AI is not allowed to do whatever it wants, and we can prove it.*
Every step below exists to make one of the three autonomy buckets visible.

---

## 0. Before they walk in (15 min)

```bash
# 1. Postgres running, then start the model server
ollama serve                       # leave running
ollama list                        # confirm `handled-ops` is present

# 2. Backend
cd backend && ..\venv\Scripts\uvicorn main:app --port 8000

# 3. Seed two companies with realistic history (~50s)
cd backend && ..\venv\Scripts\python seed_demo.py
#    -> prints Company A + Company B logins. KEEP THIS TERMINAL OPEN.

# 4. Frontend
cd handled_app && flutter run -d chrome --web-port=5000
```

Checklist:
- [ ] Logged in as **Company A** already, sitting on the Overview screen
- [ ] Company B credentials pasted somewhere you can grab in one click
- [ ] The seed left **2 pending approvals** — do not approve them in rehearsal without re-seeding
- [ ] One rehearsal run completed today (model is warm; first call after a cold start is slow)

> **Timing note:** each generation takes roughly 10 seconds on the laptop GPU.
> Don't fill that silence with "it's loading" — use it. Scripted lines for the
> gap are marked ⏳ below.

---

## 1. Frame the problem (45s — no screen yet)

> "Small Indian manufacturers — 10 to 100 people — have no dedicated ops person.
> The owner is doing purchase orders between customer calls. There are plenty of
> AI tools that will write those emails for them. The reason they don't get
> adopted is the obvious one: nobody will let software send a binding purchase
> order to a supplier on their behalf.
>
> So the problem we picked isn't 'can the AI write it.' It's **'what is the AI
> allowed to do without asking.'** That's what we built."

---

## 2. Overview screen — the model in numbers (60s)

Point at the **by-bucket breakdown**.

> "Every action this agent has ever taken falls into exactly one of three tiers.
> Not chosen by the AI at runtime — the tier is hard-coded per tool in a table
> in our source. The model never classifies its own risk.
>
> Auto: internal, reversible, runs immediately. Template: goes outside the
> company but the wording is pre-approved and fixed. Approval-required: binding
> or hard to undo — a human has to say yes."

Point at **Ran without a human** and **Rejected by a human**.

> "That first number is the value proposition — most of the work never touches
> the owner. That second one is the safety proposition — when it does ask, the
> human genuinely says no sometimes. It's not a rubber stamp."

---

## 3. Auto bucket — instant, logged (60s)

Ops Tools → **Ops status summary** → Run.

⏳ *While it generates:*
> "This is reading a week of raw activity notes. Summarising internal notes for
> your own manager is about as low-risk as it gets — nothing leaves the company,
> nothing is binding — so it just runs. But note it still writes a permanent
> audit row. Every bucket logs. That's non-negotiable in our design."

When it returns, read one bullet aloud. Then:

> "No approval queue, no waiting. That's the whole point of having tiers — if
> everything needed sign-off, you've just invented a slower inbox."

---

## 4. Auto + RAG — grounded, and refuses to guess (75s)

Ops Tools → **Inventory Q&A** → ask: *"Which items are below their reorder point?"*

⏳ *While it generates:*
> "This one is answering from a stock list this company uploaded — not from
> general knowledge. Retrieval is per-company, so it's physically reading
> Company A's document and nothing else."

When it answers, then ask a second question it **cannot** answer:
*"What's the unit price of the 6204 bearing?"* (prices aren't in the doc)

> "Watch this — it says it doesn't have that. It would be easy to make an AI
> that always produces a confident number. For an ops tool that's worse than
> useless, because someone will order against it. Refusing is a feature."

---

## 5. Template bucket — the tier people forget exists (60s)

Ops Tools → **Vendor status update** → pick *Delay notification* → fill the fields → Send.

> "This one goes **outside** the company — to a supplier. So the AI does not get
> to choose the words. It picks which of three pre-approved templates applies,
> and fills in the blanks. That's it.
>
> This middle tier is the one most 'AI agent' demos skip. You either let the
> model write freely to outsiders, or you make a human approve every message.
> Neither is right for a delay notification you send forty times a month."

Point at the rendered message.

> "Fixed wording. A lawyer could sign this off once, and it stays signed off."

---

## 6. ⭐ Approval-required — the flagship moment (2.5 min)

**This is the demo. Slow down here.**

Approvals → the pending **Purchase Order** for the 6204 bearings.

> "Stock audit found 46 units against a reorder point of 120. The agent drafted
> the justification for reordering."

Read the agent's justification aloud. Then point at the two empty fields.

> "Now — look at what it did *not* do. There's no quantity, and no amount.
> Those fields are empty, and the agent is explicitly forbidden from suggesting
> figures, because the moment it puts a plausible number on the screen, a busy
> owner clicks approve without checking it.
>
> So the human types them in."

**Type 200 and 36400 by hand, deliberately, while talking.**

> "The AI did the writing. The human committed the money. That division is the
> entire thesis of this project."

Try clicking **Approve** before filling a field (or clear one first) to show it's disabled.

> "And it's enforced, not just asked for — the button stays dead until both are
> real numbers."

Approve. Then go to **History**.

> "And there's the permanent record: what the AI drafted, what the human
> actually authorised, and who authorised it. The draft is never overwritten —
> if this purchase is ever questioned, you can see exactly what the AI proposed
> versus what a person signed off."

---

## 7. Tenant isolation — proof, not assurance (60s)

Log out → log in as **Company B** → Overview, then History.

> "Different company, same deployment. Company A's purchase orders, inventory,
> and history are simply not here.
>
> That's not just a filtered query — it's enforced in Postgres itself with
> row-level security, underneath our application code. If a developer forgets a
> WHERE clause, the database still returns nothing. We wrote adversarial tests
> that try to read across tenants with the app-layer filter deliberately
> removed, and they come back empty."

---

## 8. Close (30s)

> "So: five ops tools, three safety tiers, every action logged permanently,
> and the binding ones gated behind a human who types the numbers themselves.
>
> The department is Ops because our mentor pushed us there — but the tier table
> is department-agnostic. Adding HR or procurement is adding rows to that table,
> not rebuilding the safety model. That's the part we think is worth funding."

---

## Fallback plan (Phase 4 exit criterion)

**If a live generation call fails or hangs mid-demo:**

1. Don't wait on it. Say: *"That's the local model on a laptop GPU — in
   production this is a served endpoint."* Then go to **History**.
2. The seeded history contains **real generated output from earlier runs** for
   every one of the five tools. Walk through those instead — the audit trail is
   the more important screen anyway.
3. The architecture argument does not depend on a live call succeeding. The
   bucket assignment, the empty manual fields, the disabled approve button and
   the RLS isolation are all demonstrable with zero model calls.

**If the backend is down:** the app shows "Can't reach the server" rather than a
stack trace. Restart uvicorn; the seeded data is in Postgres and survives.

**If asked "did you fine-tune this yourself?":** yes — QLoRA on Qwen2.5-3B,
`backend/training/`. Be straight about the limits: 600 synthetic examples, and
the behavioural eval (`eval_ops_quality.py`) is how we check it honours the
safety rules, not a capability benchmark.

**If asked about prompt injection:** `backend/eval_injection.py` — uploaded
documents are attacker-reachable, so retrieved text is fenced and treated as
data. Worth saying plainly that the architecture caps the blast radius: injected
text cannot change an action's bucket, because that's hard-coded, not inferred.

---

## Questions to have an answer ready for

| Likely question | Short answer |
|---|---|
| "Why not just use ChatGPT?" | Nothing stops the model sending a binding PO. The tiers are the product. |
| "What if the AI is wrong?" | On binding actions it doesn't matter — a human types the figures. On auto actions it's internal and reversible, and logged. |
| "Does data leave the company?" | Today the model runs locally via Ollama. Be honest that hosted APIs are a prototype-phase option; self-hosting is the Phase 5 plan. |
| "How is this defensible?" | The tier table + audit trail architecture, which is department-agnostic. Not the department choice. |
| "How many customers?" | None. It's a prototype built to a 2-year degree-project timeline; this is the architecture milestone. |
