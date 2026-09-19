"""
Seed realistic demo data for the incubator walkthrough (Implementation_Plan.md §4.1).

Creates two companies so tenant isolation can be shown live, uploads a real
inventory document for the RAG tool, and leaves a deliberate mix of finished
history and *pending* approvals so the demo's flagship moment — typing the
quantity/amount in by hand and approving — is still available to perform live.

Everything goes through the real HTTP API rather than direct DB writes, so the
seeded rows contain genuine model output. That doubles as the Phase 4 fallback
plan: if a live generation call fails mid-demo, the seeded history already
holds real generated text to show instead.

Usage (backend running on :8000, Ollama up):
    ..\\venv\\Scripts\\python seed_demo.py
    ..\\venv\\Scripts\\python seed_demo.py --base-url http://127.0.0.1:8000

Re-runnable: each run creates freshly-suffixed companies, so it never collides
with a previous seed. Prints the login credentials at the end.
"""
import argparse
import sys
import time

import requests

PASSWORD = "DemoPass!2026"

# A real-looking fastener/bearing distributor's stock list — the kind of thing
# an SME actually keeps in a spreadsheet. Deliberately includes items below
# their reorder point so the PO scenario has a genuine trigger.
INVENTORY_DOC = """\
SKU FAST-M8-50 | Hex Bolt M8x50 Grade 8.8 | on_hand 1840 | reorder_point 500 | vendor Shree Fasteners | unit_cost 4.20
SKU FAST-M10-60 | Hex Bolt M10x60 Grade 8.8 | on_hand 240 | reorder_point 400 | vendor Shree Fasteners | unit_cost 7.10
SKU WASH-M8 | Spring Washer M8 | on_hand 12500 | reorder_point 3000 | vendor Shree Fasteners | unit_cost 0.80
SKU BRG-6204 | Deep Groove Ball Bearing 6204-2RS | on_hand 46 | reorder_point 120 | vendor Nandi Bearings | unit_cost 182.00
SKU BRG-6205 | Deep Groove Ball Bearing 6205-2RS | on_hand 310 | reorder_point 150 | vendor Nandi Bearings | unit_cost 214.00
SKU SEAL-TC25 | Oil Seal TC 25x42x7 | on_hand 88 | reorder_point 200 | vendor Nandi Bearings | unit_cost 63.50
SKU BELT-A42 | V-Belt A42 | on_hand 130 | reorder_point 75 | vendor Pune Rubber Works | unit_cost 310.00
SKU BELT-B55 | V-Belt B55 | on_hand 22 | reorder_point 60 | vendor Pune Rubber Works | unit_cost 455.00
SKU LUB-EP2 | Grease EP2 Lithium 500g | on_hand 205 | reorder_point 100 | vendor Pune Rubber Works | unit_cost 240.00
SKU CHN-08B | Roller Chain 08B-1 (per metre) | on_hand 64 | reorder_point 150 | vendor Shree Fasteners | unit_cost 395.00
"""

ACTIVITY_LOG = """\
Mon: 4 purchase orders raised (PO-2291 to PO-2294). PO-2291 approved same day.
Mon: Nandi Bearings confirmed dispatch for order PO-2287, 6 cartons, LR no. 44821.
Tue: Shree Fasteners flagged a 5-day delay on PO-2288 (M10 bolts) citing raw material shortage.
Tue: Stock audit found BRG-6204 at 46 units, well below the 120 reorder point.
Wed: Customer Deshmukh Engineering requested expedited dispatch on order SO-1142.
Wed: 2 inward GRNs booked, 1 rejected for short quantity (BELT-B55, 8 units short).
Thu: PO-2292 and PO-2293 still awaiting approval from the ops head.
Thu: Pune Rubber Works quoted revised pricing on V-belts, effective next month.
"""


class Api:
    def __init__(self, base_url):
        self.base = base_url.rstrip("/")
        self.token = None

    def _headers(self):
        h = {"Content-Type": "application/json"}
        if self.token:
            h["Authorization"] = f"Bearer {self.token}"
        return h

    def post(self, path, payload):
        r = requests.post(f"{self.base}{path}", json=payload, headers=self._headers(), timeout=180)
        if r.status_code >= 300:
            raise RuntimeError(f"POST {path} -> {r.status_code}: {r.text[:300]}")
        return r.json()

    def get(self, path):
        r = requests.get(f"{self.base}{path}", headers=self._headers(), timeout=60)
        if r.status_code >= 300:
            raise RuntimeError(f"GET {path} -> {r.status_code}: {r.text[:300]}")
        return r.json()

    def signup_and_login(self, company, owner, email):
        self.post("/company/signup", {
            "name": company, "industry": "Industrial components distribution",
            "size": 35, "owner_name": owner, "owner_email": email, "password": PASSWORD,
        })
        self.token = self.post("/auth/login", {"email": email, "password": PASSWORD})["access_token"]


def step(msg):
    print(f"  -> {msg}", flush=True)


def seed_company_a(api):
    """The company the demo is actually driven from — rich, realistic history."""
    step("uploading inventory document for RAG")
    n = api.post("/ops/inventory-upload", {"doc_text": INVENTORY_DOC, "source": "stock_list_sep2026"})
    print(f"     indexed {n['indexed_chunks']} chunks")

    step("auto: ops_status_summary on a week of real activity")
    api.post("/ops/status-summary", {"activity_log": ACTIVITY_LOG})

    # Single-item lookups are what this tool does reliably; cross-record
    # comparisons ("which items are below reorder point") are declined by
    # design — see the prompt in agent/crew.py and suite E of
    # eval_ops_quality.py for why.
    step("auto: inventory_qa (grounded, specific stock figure)")
    api.post("/ops/inventory-qa", {"question": "How many 6204 bearings do we have on hand?"})

    step("auto: inventory_qa (grounded, vendor lookup)")
    api.post("/ops/inventory-qa", {"question": "Who supplies the V-Belt B55, and what is its stock?"})

    step("auto: inventory_qa (not in the records -> should refuse)")
    api.post("/ops/inventory-qa", {"question": "What is the lead time from Nandi Bearings?"})

    step("template: vendor_status_update - delay notification (already sent)")
    api.post("/ops/vendor-status", {
        "vendor_name": "Shree Fasteners", "template_key": "delay_notification_v1",
        "details": {"vendor_name": "Shree Fasteners", "company_name": "Sharma Industrial Supplies",
                    "order_ref": "PO-2288", "revised_date": "2026-09-26"},
    })

    step("template: vendor_status_update - quality issue (already sent)")
    api.post("/ops/vendor-status", {
        "vendor_name": "Pune Rubber Works", "template_key": "quality_issue_v1",
        "details": {"vendor_name": "Pune Rubber Works", "company_name": "Sharma Industrial Supplies",
                    "order_ref": "PO-2285", "issue_description": "8 units of BELT-B55 short-supplied against the GRN"},
    })

    # --- resolved approvals, so History shows real approve/reject outcomes ---
    step("approval: purchase_order - APPROVED with hand-typed numbers (history)")
    po_done = api.post("/ops/purchase-order", {
        "item_name": "Oil Seal TC 25x42x7 (SEAL-TC25)", "current_stock": 88,
        "reorder_reason": "Below reorder point of 200 after Q2 consumption",
        "preferred_vendor": "Nandi Bearings",
    })
    api.post("/ops/approve", {
        "action_id": po_done["id"], "decision": "approved",
        "manual_fields": {"quantity": 250, "amount": 15875.00},
    })

    step("approval: workflow_exception - REJECTED (history)")
    exc_done = api.post("/ops/workflow-exception", {
        "request_description": "Release SO-1142 to dispatch before payment clearance",
        "sop_reference": "SOP-FIN-04: no dispatch before advance realisation",
        "justification": "Long-standing customer, verbally promised delivery this week",
    })
    api.post("/ops/approve", {"action_id": exc_done["id"], "decision": "rejected"})

    # --- left PENDING on purpose: these are the live demo moments ---
    step("approval: purchase_order - LEFT PENDING (flagship live demo moment)")
    api.post("/ops/purchase-order", {
        "item_name": "Deep Groove Ball Bearing 6204-2RS (BRG-6204)", "current_stock": 46,
        "reorder_reason": "Stock audit found 46 units against a reorder point of 120",
        "preferred_vendor": "Nandi Bearings",
    })

    step("approval: workflow_exception - LEFT PENDING (optional demo step)")
    api.post("/ops/workflow-exception", {
        "request_description": "Air-freight BELT-B55 shortfall from Chennai supplier instead of road",
        "sop_reference": "SOP-LOG-02: road freight is the default for domestic replenishment",
        "justification": "Line stoppage risk at Deshmukh Engineering if belts miss Friday",
    })


def seed_company_b(api):
    """Second tenant — just enough data to prove isolation live."""
    step("uploading a DIFFERENT inventory document")
    api.post("/ops/inventory-upload", {
        "doc_text": (
            "SKU ACC-BRK-01 | Brake Pad Set (Hatchback) | on_hand 320 | reorder_point 100 | vendor Vidarbha Auto\n"
            "SKU ACC-CLT-02 | Clutch Plate 190mm | on_hand 75 | reorder_point 90 | vendor Vidarbha Auto\n"
            "SKU ACC-FLT-03 | Oil Filter (Diesel) | on_hand 1240 | reorder_point 400 | vendor Nagpur Filters\n"
        ),
        "source": "stock_list_sep2026",
    })
    step("auto: one status summary")
    api.post("/ops/status-summary", {
        "activity_log": "Mon: 2 POs raised. Tue: clutch plates dipped below reorder point.",
    })
    step("approval: one pending purchase_order")
    api.post("/ops/purchase-order", {
        "item_name": "Clutch Plate 190mm (ACC-CLT-02)", "current_stock": 75,
        "reorder_reason": "Below reorder point of 90", "preferred_vendor": "Vidarbha Auto",
    })


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://127.0.0.1:8000")
    args = ap.parse_args()

    try:
        requests.get(f"{args.base_url}/health", timeout=5)
    except Exception:
        sys.exit(f"Backend not reachable at {args.base_url} — start uvicorn first.")

    stamp = int(time.time())
    a_email = f"ops@sharma-industrial-{stamp}.in"
    b_email = f"ops@krishna-auto-{stamp}.in"
    started = time.time()

    print("\nSeeding Company A - Sharma Industrial Supplies")
    api_a = Api(args.base_url)
    api_a.signup_and_login("Sharma Industrial Supplies", "Rohit Sharma", a_email)
    seed_company_a(api_a)

    print("\nSeeding Company B - Krishna Auto Components")
    api_b = Api(args.base_url)
    api_b.signup_and_login("Krishna Auto Components", "Priya Krishnan", b_email)
    seed_company_b(api_b)

    hist_a = api_a.get("/ops/history")
    pend_a = api_a.get("/ops/approvals")
    hist_b = api_b.get("/ops/history")

    print(f"""
Done in {time.time() - started:.0f}s.

  Company A - Sharma Industrial Supplies
    login     {a_email}  /  {PASSWORD}
    history   {len(hist_a)} actions
    pending   {len(pend_a)} awaiting approval  <- the live demo moments

  Company B - Krishna Auto Components
    login     {b_email}  /  {PASSWORD}
    history   {len(hist_b)} actions

Log in as Company A for the walkthrough; log in as Company B to show isolation.
""")


if __name__ == "__main__":
    main()
