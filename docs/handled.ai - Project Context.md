# handled.ai — Project Context

**One-liner:** A web/app product for small Indian companies without dedicated HR/admin staff. Companies sign up and turn on an AI assistant for a department (starting with HR). The AI handles easy, safe tasks on its own and asks a human manager to approve anything risky before it happens.

**Project type:** B.Tech engineering degree project (Design Experience, sem4–sem8). Solo/small team. Total timeline: 2 years (remaining 4 semesters). First milestone: a working (not complete) demo at the 3-month mark.

---

## 1. Core Idea
A company signs up, turns on the HR assistant, and the AI starts handling routine HR work. Low-risk internal tasks (e.g. summarizing a resume) happen automatically. Anything external-facing, financially binding, or hard to undo (e.g. sending an offer letter) is drafted by the AI but requires human approval first.

## 2. Target Customer
Small-to-mid-size Indian companies (roughly 10–100 employees) without dedicated departmental/HR/admin staff.

## 3. Who Can Do What (Roles)
- **Owner/Admin** — signs the company up, pays the bill, turns departments on, adds/removes staff, sets approval rules, can approve anything.
- **Department Head** — manages their department's AI, approves the risky actions in their department.
- **Staff** — uses the AI day-to-day, cannot approve their own department's risky actions.

## 4. Why Departments Are Fixed, Not Custom
A pre-built, fixed catalog of department types (HR, Ops, Support, Admin, BD/leads, etc.) — for each one, it's decided in advance which actions are safe to auto-run and which need approval. Companies turn these on; they cannot invent a new department or a new AI action themselves.

**Reason:** someone has to correctly judge how risky each action is, and that's not a judgment call to leave to the AI or to each company. Doing it once, centrally, keeps that judgment reliable. If a company needs something not offered yet, that becomes a "request a new module" process for later — not something the 3-month prototype needs to support.

## 5. Auto vs. Approval-Required — the Rule
Three buckets:
1. **Auto (AI just does it)** — internal, low-risk, easy to undo. Example: writing an internal summary.
2. **Auto, but restricted to a pre-approved template** — external-facing but low-stakes, with wording fixed/legally reviewed in advance rather than freshly AI-generated. Example: a candidate rejection email using one of a small set of vetted templates.
3. **Needs a human's OK first** — creates a binding/financial commitment, is hard to undo, or requires freely AI-generated external-facing wording. Example: an offer letter, or a rejection email with custom AI-composed language.

**Implementation rules:**
- The bucket for each action is hard-coded per action in the code — not decided by the AI in the moment. Safer, easier to audit.
- Every action is logged permanently, no exceptions, regardless of bucket — for tracking and proving what happened.
- For anything with important numbers (money, dates), the AI writes the wording but the approving human types the actual number in themselves (e.g. CTC, joining date) — not just clicking "approve" on a number the AI guessed. Forces a real check instead of rubber-stamping.
- Letting each company change these approval rules themselves is a "someday" feature — not part of the 3-month prototype.

## 6. Tech Stack

| Layer | Choice |
|---|---|
| AI model | **Prototype (now):** third-party API (e.g. Claude or GPT). **Real product (later, Phase 2):** own fine-tuned open-source model, self-hosted. |
| Fine-tuning method | LoRA/QLoRA via Unsloth (main tool), LLaMA-Factory (no-code backup) |
| Serving the model | Ollama (local/testing), vLLM (many concurrent users) |
| App | Flutter (Dart) — one codebase, real installable app for phone + desktop |
| Backend | FastAPI (Python) |
| Database | PostgreSQL |
| AI agent logic | CrewAI (main), LangGraph (backup if approval logic outgrows CrewAI) |

No ready-made Flutter+FastAPI SaaS starter kit exists (confirmed via research). Plan: combine a FastAPI backend starter (e.g. philipokiokio/FastAPI_SAAS_Template, for its auth/org/permissions model) with a separate Flutter starter, connected manually.

**Why Flutter over React/React Native:** one codebase gives a real installable app for phone + desktop. React/React Native would need Electron (or similar) bolted on for desktop, plus React Native separately for mobile — more moving parts for the same result. This project wants a real installable app, not a website.

## 7. System Architecture
Four separate layers:
1. **App (Flutter)** — just the screens. No decision-making here; every button press is a request to the backend.
2. **Backend (FastAPI)** — checks who's logged in, checks their role, ensures a company can only see its own data, passes requests to the AI layer.
3. **AI layer** — two parts, kept separate on purpose:
   - **Orchestration (CrewAI)** — decides what to do, drafts actions, puts risky ones in the approval queue.
   - **The language model** — just generates text, knows nothing about the database or rules. Separation means the model can be swapped later (API → own model) without rewriting the rest.
4. **Database (PostgreSQL)** — stores companies, departments, users, and every action the AI has taken or proposed. Core tables: `company`, `department`, `user`, `agent_action` (with `status`, `draft_output`, `action_type`, `requires_approval` fields; status spans drafted → auto-executed/pending → approved/rejected → executed).

**What happens when someone uses it:** Staff asks the AI to do something → backend checks they're allowed → AI layer pulls relevant company info (RAG) → AI drafts a response → system checks if that action type is auto/template/approval → auto actions run and get logged; risky ones wait in a queue for the Department Head to approve, edit, or reject.

**Signing up:** Owner registers the company → light identity check via Udyam MSME registration number → HR module on by default → they invite their team → default approval rules apply → done.

## 8. India-Specific Notes
- India's DPDP Act (2023) is the reason self-hosting the AI model matters for the **real product** — client data never has to leave the company's own servers. This claim only applies once on the self-hosted model (Phase 2); the prototype itself is not making this claim, since it uses a third-party API.
- Udyam (MSME) registration number is the planned sign-up identity check.
- Startup India / DPIIT recognition — only worth pursuing if this becomes a real company after graduation.

## 9. Competitive Landscape
- **Zencia AI** (Lucknow) — voice-first AI employee, phone-first rather than dashboard-first.
- **Zapcore** — another Indian "AI employees" company, limited public detail available.
- **An unnamed YC-backed company** — has a CRM, a daily "approve" click model, drafts email replies for review — very close to this project's approval-gate idea.
- **Rasa** — enterprise agent platform supporting self-hosted/on-prem deployment — confirms self-hosting AI models is workable at real scale.

**What makes handled.ai different:** covering multiple departments in one platform (most competitors do one thing only), India-SME/data-protection-law positioning, and a fixed, pre-vetted list of departments that keeps the safety story simple while scaling. The self-hosted/data-never-leaves-our-servers angle is a Phase 2 claim, not true of the prototype yet — don't market the prototype that way.

## 10. Project History (how we got here)
1. **TradeIQ** — an AI-powered financial literacy/trading education platform. Explored via deep market research, ultimately abandoned (personally uninteresting, market/regulation too crowded).
2. **Sambandh AI** — pivoted to an AI BD-assist agent for industrial/EPC SMEs with no BD function, using a relationship graph for warm intros instead of cold outreach. Three template docs (Ideation Doc, Persona Development, Stakeholder Analysis Matrix) were filled out for this phase.
3. **handled.ai** — generalized into a multi-department AI assistant/automation platform for any registered company, not EPC/BD-specific. "Sambandh AI" rejected as a name; **handled.ai** is the final chosen name. BD/lead-gen became just one *possible* future department module, not the whole product.

**Note:** Insteel Engineers (an EPC company, separate freelance/internship work) was only ever a placeholder "pilot partner" during the Sambandh AI phase and has been fully dropped — it is not part of this project in any form, and its data/logins must never be reused here.
