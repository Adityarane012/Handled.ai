handled.ai — Project Summary
One-liner: A web/app product for small Indian companies that don't have dedicated HR/admin staff. Companies sign up and turn on an "AI assistant" for a department (starting with HR). The AI does easy, safe tasks on its own and asks a human manager to approve anything risky before it happens.

Context: B.Tech degree project. Solo/small team. 2-year timeline. First goal: a working (not complete) demo at the 3-month mark.


1. Core Idea
A company signs up, turns on the HR assistant, and the AI starts handling routine HR work. Low-risk internal stuff (like summarizing a resume) happens automatically. Anything that goes outside the company, costs money, or can't be undone (like sending an offer letter) is drafted by the AI but must be approved by a human first.
2. What We Ruled Out
Building our own AI model from scratch — too expensive, too slow.
React / React Native for the app — settled, staying rejected. We want a real installable app, not a website. Flutter builds that natively for phone + desktop from one codebase. React/React Native would need an extra tool (Electron or similar) bolted on to get a desktop app at all, plus React Native separately for phone — more moving parts for the same result.
Mixing the marketing website with the actual product.
Letting companies invent their own custom departments (explained in Section 5 — keeping this fixed is a safety decision, not a limitation we forgot to lift).
Third-party AI APIs (OpenAI, Anthropic, etc.) in the final, real product — still ruled out, because real client data shouldn't leave our own servers.

Allowed for the 3-month prototype only: using a third-party AI API (see Section 3). No real company data is involved in the prototype, so the privacy concern doesn't apply yet. Running our own fine-tuned AI model stays the plan for the real product (Phase 2, starts after the prototype — Section 9). This is also what keeps the "your data never leaves your servers" pitch true once real customers are involved, and it's the part of this project that looks like real AI/ML engineering work for a grad school application — an API wrapper alone wouldn't.
3. Tech Stack
Layer
Choice
AI model
Prototype (now): third-party API (e.g. Claude or GPT). Real product (later): our own fine-tuned open-source model, run on our own servers.
Fine-tuning method
LoRA/QLoRA via Unsloth (main tool), LLaMA-Factory (simpler no-code backup)
Serving the model
Ollama (for testing on a laptop), vLLM (for handling many users at once)
App
Flutter (Dart) — confirmed. One codebase, real installable app for phone + desktop.
Backend
FastAPI (Python)
Database
PostgreSQL
AI agent logic
CrewAI (main), LangGraph (backup if the approval logic gets too complex for CrewAI)

No ready-made Flutter+FastAPI starter kit exists — plan is to combine a FastAPI backend starter with a separate Flutter starter and connect them ourselves.
4. Who Can Do What
Owner/Admin — signs the company up, pays the bill, turns departments on, adds/removes staff, sets approval rules, can approve anything.
Department Head — manages their department's AI, approves the risky actions in their department.
Staff — uses the AI day-to-day, can't approve their own department's risky actions.
5. Why Departments Are Fixed, Not Custom
We pre-build a set list of department types (HR, Ops, Support, Admin, BD/leads, etc.), and for each one we decide in advance which actions are safe to auto-run and which need approval. Companies just turn these on — they can't invent a new department or a new AI action themselves. Reason: someone has to correctly judge how risky each action is, and that's not a judgment call we want to leave to the AI or to each company. Doing it once, centrally, keeps that judgment reliable. If a company needs something we don't offer yet, that becomes a "request a new module" process for us to build later — not something for the 3-month prototype.
6. Auto vs. Approval-Required — the Rule
Auto (AI just does it): internal, low-risk, easy to undo. Example: writing an internal summary.
Auto, but restricted to a pre-approved template (no free-generation): external-facing but low-stakes, and the wording is fixed/legally reviewed in advance, not written fresh by the AI each time. Example: a candidate rejection email using one of a small set of vetted templates.
Needs a human's OK first: creates a binding/financial commitment, is hard to undo, or requires the AI to freely generate external-facing wording. Example: an offer letter, or a rejection email where the AI is composing custom language instead of filling a template.
This rule is hard-coded per action in the code (not decided by the AI in the moment) — safer and easier to check later.
Every action is logged permanently — auto, template-restricted, or approval-gated, no exceptions. This log is for tracking and proving what happened, and it's non-negotiable regardless of which bucket an action falls into.
For anything with important numbers (money, dates), split the writing from the numbers. The AI can write the wording, but the person approving it should type the actual number in themselves (e.g. CTC, joining date) — not just click "approve" on a number the AI guessed. If they only have to click a button, people stop actually checking. Typing it in forces a real check.
Letting each company change these approval rules themselves is a "someday" feature, not part of the 3-month prototype.
7. How the Pieces Fit Together
Four separate layers:

App (Flutter) — just the screens. No decision-making happens here; every button press is a request sent to the backend.
Backend (FastAPI) — checks who's logged in, checks their role, makes sure a company can only see its own data, and passes requests to the AI layer.
AI layer — two parts kept separate on purpose: (a) the "orchestration" logic (CrewAI) that decides what to do, drafts actions, and puts risky ones in the approval queue; (b) the actual language model, which just generates text and knows nothing about our database or rules. Keeping these separate means we can swap the AI model later (API → our own model) without rewriting the rest.
Database (PostgreSQL) — stores companies, departments, users, and every action the AI has taken or proposed.

What happens when someone uses it: Staff asks the AI to do something → backend checks they're allowed → AI layer pulls relevant company info → AI drafts a response → the system checks if that type of action is auto or needs approval → auto actions run and get logged; risky ones wait in a queue for the Department Head to approve, edit, or reject.

Signing up: Owner registers the company → light identity check (we're using their Udyam MSME registration number for this) → HR module is on by default → they invite their team → default approval rules apply → done.

Teaching our own model later (Phase 2): collect 200–500 examples of "situation → ideal AI response" pairs for HR → fine-tune a small open-source model on them using LoRA → check its answers against a held-out set of examples → repeat 2–3 times until it's good enough → put it into production serving.
8. India-Specific Notes
India's data protection law (DPDP Act, 2023) is the reason self-hosting our own AI model matters for the real product — client data never has to leave our servers. This only applies once we're on our own model (Section 2); the prototype itself isn't making this claim.
Udyam (MSME) registration number is our planned sign-up identity check.
Startup India / DPIIT recognition — only worth pursuing if this becomes a real company after graduation, not now.
9. 3-Month Prototype Plan
HR tools to build (auto vs. approval)
Modeled loosely on how ERPNext structures HR workflows (a request moves from draft → review → approved/executed) — we're mapping the same idea onto our own auto/approval system, not copying ERPNext's code:

AI does this automatically, no approval needed:

Screen/summarize resumes for an open role (similar to the ATS resume-parsing work already familiar from ERPNext)
Draft a job posting
Answer an employee's question about policy (e.g. "how many leave days do I have left")
Update leave balance after a request is approved
Draft an onboarding checklist for a new hire
Draft an internal performance-review summary (not sent to the employee — internal only)
Send a candidate rejection email — only if using a pre-approved, fixed template, not AI-generated wording

Needs a Department Head's approval first:

Sending an offer letter to a candidate — AI writes the letter itself, but the Department Head types in the actual CTC, joining date, and other key numbers before it can be sent (see Section 6)
Sending a rejection email with custom/AI-generated wording (as opposed to the templated version above)
Approving a leave request that breaks normal policy
Anything touching payroll numbers
Final exit/settlement paperwork

This is a starting list to build against, not the full HR department — pick 3-5 of these for the actual prototype, don't try to build all of them in 3 months.
Training data for the AI (Phase 2 problem, not urgent yet)
Since the prototype uses a third-party API, no training data is needed right now. When Phase 2 (our own model) starts, we won't have real company data, and that's fine — don't reuse your old ERPNext login/data from your internship company. Even a small pull could break your internship's confidentiality terms — not worth the risk for a college project. Instead: write a handful of made-up but realistic HR policies yourself, then use the AI API itself to generate example question→answer pairs based on those made-up policies. This is a standard, legitimate way to bootstrap training data and avoids touching anyone's real data.
Month 1 build plan
Week 1: FastAPI skeleton + database tables (company/department/user/action) + login system + per-company data isolation. Flutter skeleton wired to a basic "is the server up" check.
Week 2: Company sign-up flow working end-to-end, roles/permissions working, Udyam number field.
Week 3: HR module turn-on flow + dashboard.
Week 4: Wire up one AI agent, one real action (e.g. logging something automatically), through the whole stack, using the third-party API.

Switching to a third-party API for the prototype frees up the time we'd have spent building the fine-tuning pipeline. Suggested use of that time: harden the per-company data isolation and permission checks (this is the part most likely to have an embarrassing bug — one company seeing another's data), and build out more than one HR tool instead of just one.
Approx. costs (prototype + basic testing, 3 months)
AI API calls: using a cheap model for development (e.g. GPT-4o-mini at ~$0.15 per million input tokens / $0.60 per million output tokens, or Claude Haiku at ~$1/$5 per million) and a stronger model only for final demo runs, total usage for a few hundred/thousand test calls should land under $20–40 (~₹1,700–3,400) for the full 3 months. Real risk is a runaway loop calling the API repeatedly by accident — worth adding a simple call cap during development.
Hosting: free tiers (Render/Railway/Supabase, or your own laptop) are enough for development. If a public demo link is needed, a small VPS is ~$5–10/month (~₹400–800/month).
Flutter app: free to build and test (emulator or web build); skip app store fees ($99/yr Apple, $25 one-time Google) — not needed for a college demo.
Total estimate: roughly ₹2,000–6,000 (~$25–75) for the whole 3-month prototype phase — much cheaper than the earlier self-hosted GPU estimate, since that work is now deferred to Phase 2.
Phase 2 (later, self-hosted fine-tuning) GPU cost estimate stays at roughly ₹15,000–35,000, unchanged, for whenever that phase starts.
10. Other Companies Doing Similar Things
Zencia AI (Lucknow) — voice-first AI employee, phone-first rather than dashboard-first.
Zapcore — another Indian "AI employees" company, not much public detail available.
An unnamed YC-backed company — has a CRM, a daily "approve" click model, drafts email replies for review — very close to our approval-gate idea.
Rasa — an enterprise agent platform that also supports self-hosted/on-prem deployment — confirms self-hosting AI models is a workable pattern at real scale.

What makes us different: covering multiple departments in one platform (most competitors do one thing only), India-SME/data-protection-law positioning, and a fixed, pre-vetted list of departments that keeps the safety story simple as we grow. The self-hosted/data-never-leaves-our-servers angle is a Phase 2 claim, not true of the prototype yet — don't market the prototype that way.
11. Still Open / Next Session
Decide when to start Phase 2 (our own fine-tuned model) — confirmed as "after the 3-month prototype," not during it.
Pick which 3–5 HR tools from Section 9 actually get built first.
Set a simple API-call budget/limit for development so a bug can't run up an unexpected bill.
Decide on the database-level protection for per-company data isolation (recommended: Postgres Row-Level Security, not just filtering in application code — safer if a developer forgets a check somewhere).
Since the app is a real installable app, not a website: decide whether to get a code-signing certificate before demo day (avoids the "unknown publisher" warning on Windows) — not urgent, but plan for it.
Decide how the app gets updates after it's installed — for the prototype, manual redownload is fine; auto-update is a later, non-prototype feature.
12. Concepts Worth Learning Before/While Building This
Kept short — these are the ones that map directly onto what you're building, not a general AI reading list.

How large language models actually work (tokens, context window, what "generating text" means): The Illustrated Transformer by Jay Alammar; Andrej Karpathy's "Let's build GPT" video if you want to go deeper.
Prompt engineering (this is 90% of what Phase 1 depends on): Anthropic's prompt engineering guide.
What "AI agents" and "tools" mean in practice (directly relevant to the CrewAI layer): Anthropic's "Building Effective Agents" — practical, not hypey.
LoRA / fine-tuning, for when Phase 2 starts: Unsloth's own docs explain it simply; the original LoRA paper if you want the source.
RAG (retrieving company-specific info before the AI answers) — this is in your architecture already: any beginner "RAG from scratch" tutorial; Pinecone's learning center has a clear one.
Multi-tenant SaaS data isolation and Postgres Row-Level Security — directly relevant to Section 11, item 4: Postgres official docs on RLS.
FastAPI itself, if not already comfortable: FastAPI's official tutorial — genuinely one of the better framework docs out there.

