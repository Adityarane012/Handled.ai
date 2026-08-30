"""
Synthesizes fine-tuning data for the 4 free-generation Ops tools, mirroring the
exact prompt/context schema in agent/crew.py so the resulting JSONL trains the
model on the same system+user shape production will actually send it.

vendor_status_update is excluded on purpose: it's template_restricted, the LLM
never writes free wording for it, so there is nothing to fine-tune there.

Each set includes a --refusal-ratio of ungrounded/edge scenarios (no matching
inventory record, no preferred vendor, etc.) so the model doesn't regress the
"never fabricate numbers/facts" guarantee the current prompting relies on.

Usage (run from backend/):
    ..\\venv\\Scripts\\python training\\synthesize_data.py --tool ops_status_summary --n 5   # smoke test
    ..\\venv\\Scripts\\python training\\synthesize_data.py --all --n 150                      # full run

Backend defaults to local Ollama (--backend ollama, no cost, uses the project's
existing LLM_MODEL/OLLAMA_BASE_URL from backend/.env or their .env.example
defaults). Pass --backend anthropic for higher-quality labels if quality from
the local model isn't good enough (needs ANTHROPIC_API_KEY in backend/.env).

Writes training/data/<tool>.jsonl (one JSON object per line:
{"messages": [system, user, assistant]}).
"""

import argparse
import json
import random
from pathlib import Path

from dotenv import load_dotenv
import os
import requests

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

DATA_DIR = Path(__file__).resolve().parent / "data"
GEN_MODEL_ANTHROPIC = os.environ.get("SYNTH_MODEL", "claude-haiku-4-5-20251001")
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.environ.get("LLM_MODEL", "llama3.2")

ITEMS = ["A4 copier paper", "USB-C cables", "safety gloves", "packing tape",
         "printer toner cartridges", "steel bolts M8", "cardboard boxes (medium)",
         "hand sanitizer bottles", "LED tube lights", "nitrile gloves (box)"]
VENDORS = ["Sharma Traders", "Metro Supplies Co.", "Anand Hardware", "Kumar & Sons",
           "Prime Packaging Ltd.", None, None]  # None -> "no vendor on file" case
STATUSES = ["done", "blocked", "in progress", "overdue"]
TASKS = ["restock warehouse B", "vendor payment reconciliation", "monthly stock audit",
         "dispatch order #{n}", "quality check batch {n}", "onboard new supplier",
         "update inventory sheet", "resolve delivery delay for order #{n}"]
SOP_TOPICS = ["expense approval limit", "vendor payment terms", "overtime authorization",
              "discount approval threshold", "return/refund window", "credit period extension"]


def _rand_activity_log():
    n = random.randint(3, 6)
    tasks = random.sample(TASKS, k=min(n, len(TASKS)))
    lines = []
    for task in tasks:
        task = task.format(n=random.randint(100, 999))
        status = random.choice(STATUSES)
        lines.append(f"- {task}: {status}")
    return "\n".join(lines)


def scenarios_status_summary(n):
    for _ in range(n):
        yield {"activity_log": _rand_activity_log()}


def scenarios_inventory_qa(n, refusal_ratio):
    for _ in range(n):
        item = random.choice(ITEMS)
        if random.random() < refusal_ratio:
            yield {"question": f"How many {item} do we have left?", "context_chunks": []}
        else:
            qty = random.randint(5, 500)
            loc = random.choice(["Warehouse A, Rack 3", "Warehouse B, Bin 12", "Main store"])
            yield {
                "question": f"How many {item} do we have left?",
                "context_chunks": [f"SKU record: {item} — quantity {qty} units, location {loc}, "
                                    f"last updated recently."],
            }


def scenarios_workflow_exception(n):
    for _ in range(n):
        topic = random.choice(SOP_TOPICS)
        yield {
            "request_description": f"Staff member is requesting an exception to the {topic} policy.",
            "sop_reference": f"SOP: {topic} is capped/defined by company policy; exceptions need Dept Head sign-off.",
            "justification": random.choice([
                "Urgent client deadline this week.",
                "One-time situation, unlikely to repeat.",
                "Vendor requires it to proceed with the order.",
                "New employee, policy wasn't communicated in time.",
            ]),
        }


def scenarios_purchase_order(n, refusal_ratio):
    for _ in range(n):
        item = random.choice(ITEMS)
        vendor = None if random.random() < refusal_ratio else random.choice(VENDORS)
        yield {
            "item_name": item,
            "current_stock": random.choice(["3 units", "0 units", "12 units", "very low"]),
            "reorder_reason": random.choice([
                "Stock fell below reorder threshold.", "Upcoming order spike expected.",
                "Recent usage rate increased.", None,
            ]),
            "preferred_vendor": vendor,
        }


# Mirrors the exact (description, expected_output) pairs from agent/crew.py so
# training data matches the real system+user prompt shape byte-for-byte in intent.
def prompt_status_summary(ctx):
    activity = ctx.get("activity_log") or "No activity records were provided."
    return (
        "Summarise the current state of operations for a manager who has 30 seconds. "
        "Base the summary ONLY on the activity records below — do not invent tasks, "
        f"numbers, or vendors.\n\nActivity records:\n{activity}",
        "A tight 3-6 bullet status summary: what's on track, what's blocked, what "
        "needs attention. No preamble.",
    )


def prompt_inventory_qa(ctx):
    question = ctx.get("question", "")
    passages = ctx.get("context_chunks") or []
    joined = "\n---\n".join(passages) if passages else ""
    if not joined:
        return (
            f"The user asked: {question!r}\n\nNo matching inventory records were retrieved "
            "for this question. Reply that there is no matching inventory record on file — "
            "do NOT guess.",
            "One or two sentences stating no matching inventory record was found.",
        )
    return (
        "Answer the inventory question using ONLY the retrieved inventory records below. "
        "If the records don't contain the answer, say so plainly — never fabricate stock "
        f"levels, SKUs, locations, or prices.\n\nQuestion: {question}\n\n"
        f"Retrieved inventory records:\n{joined}",
        "A direct answer grounded in the records, quoting the relevant figures. If "
        "unanswerable from the records, say 'no matching inventory record found'.",
    )


def prompt_workflow_exception(ctx):
    return (
        "A staff member has requested something that may break standard operating "
        "procedure. Evaluate it against the SOP reference and write reasoning for the "
        "Department Head who must approve or reject it. Do not approve it yourself. "
        f"Do not invent policy details that were not provided.\n\nRequest: "
        f"{ctx.get('request_description', '')}\nSOP reference: "
        f"{ctx.get('sop_reference') or 'Not provided.'}\nStaff justification: "
        f"{ctx.get('justification', '')}",
        "A short brief for the approver: (1) which SOP rule is at stake, (2) how far "
        "the request departs from it, (3) the trade-off, (4) a clear recommendation "
        "the human can accept or overrule.",
    )


def prompt_purchase_order(ctx):
    return (
        "A reorder trigger has fired. Draft ONLY the justification paragraph for a "
        "purchase order. Do NOT state, guess, or imply a quantity to order or a total "
        "amount — those are entered by the human approver. If no vendor was given, "
        f"note that a vendor still needs to be chosen; do not invent one.\n\nItem: "
        f"{ctx.get('item_name', '')}\nCurrent stock: {ctx.get('current_stock', '')}\n"
        f"Reorder reason: {ctx.get('reorder_reason') or 'Stock is running low.'}\n"
        f"Preferred vendor: {ctx.get('preferred_vendor') or 'None on file.'}",
        "A short, professional justification for why this purchase order is needed. "
        "No quantities, no prices.",
    )


TOOLS = {
    "ops_status_summary": (scenarios_status_summary, prompt_status_summary, False),
    "inventory_qa": (scenarios_inventory_qa, prompt_inventory_qa, True),
    "workflow_exception_approval": (scenarios_workflow_exception, prompt_workflow_exception, False),
    "purchase_order_approval": (scenarios_purchase_order, prompt_purchase_order, True),
}


def _call_anthropic(client, system, user):
    resp = client.messages.create(
        model=GEN_MODEL_ANTHROPIC,
        max_tokens=400,
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    return resp.content[0].text.strip()


def _call_ollama(system, user):
    resp = requests.post(
        f"{OLLAMA_BASE_URL}/api/chat",
        json={
            "model": OLLAMA_MODEL,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "stream": False,
            "options": {"temperature": 0.7},
        },
        timeout=120,
    )
    resp.raise_for_status()
    return resp.json()["message"]["content"].strip()


def generate_examples(tool_name, n, refusal_ratio, backend, client=None):
    scenario_fn, prompt_fn, wants_refusal = TOOLS[tool_name]
    scenarios = list(scenario_fn(n, refusal_ratio) if wants_refusal else scenario_fn(n))
    out = []
    for ctx in scenarios:
        description, expected_output = prompt_fn(ctx)
        system = f"Expected output shape: {expected_output}"
        completion = (
            _call_anthropic(client, system, description)
            if backend == "anthropic"
            else _call_ollama(system, description)
        )
        out.append({"messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": description},
            {"role": "assistant", "content": completion},
        ]})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tool", choices=list(TOOLS), help="single tool to generate for")
    ap.add_argument("--all", action="store_true", help="generate for all 4 tools")
    ap.add_argument("--n", type=int, default=5, help="examples per tool")
    ap.add_argument("--refusal-ratio", type=float, default=0.3,
                     help="fraction of ungrounded/edge-case scenarios for tools that support it")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--backend", choices=["ollama", "anthropic"], default="ollama")
    args = ap.parse_args()

    if not args.tool and not args.all:
        ap.error("pass --tool <name> or --all")

    client = None
    if args.backend == "anthropic":
        from anthropic import Anthropic
        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if not api_key:
            raise SystemExit("ANTHROPIC_API_KEY not set in backend/.env — copy .env.example and fill it in.")
        client = Anthropic(api_key=api_key)
    else:
        try:
            requests.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=5).raise_for_status()
        except Exception as e:
            raise SystemExit(f"Can't reach Ollama at {OLLAMA_BASE_URL} — is it running? ({e})")

    random.seed(args.seed)
    DATA_DIR.mkdir(exist_ok=True)

    targets = list(TOOLS) if args.all else [args.tool]
    for tool_name in targets:
        model_label = GEN_MODEL_ANTHROPIC if args.backend == "anthropic" else OLLAMA_MODEL
        print(f"[{tool_name}] generating {args.n} examples via {args.backend}:{model_label}...")
        examples = generate_examples(tool_name, args.n, args.refusal_ratio, args.backend, client)
        out_path = DATA_DIR / f"{tool_name}.jsonl"
        with out_path.open("w", encoding="utf-8") as f:
            for ex in examples:
                f.write(json.dumps(ex, ensure_ascii=False) + "\n")
        print(f"[{tool_name}] wrote {len(examples)} examples -> {out_path}")


if __name__ == "__main__":
    main()
