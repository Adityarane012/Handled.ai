"""
Risk classification table for handled.ai — Ops department.
Per arch.md §4: this is a HARD-CODED lookup table. The LLM never decides
at runtime whether its own action needs approval.

Adding a tool = adding a row here with an explicit human decision.
"""

TOOL_REGISTRY = {
    "ops_status_summary": {
        "action_type": "auto",
        "description": "Summarizes task/workflow status from raw activity logs",
    },
    "inventory_qa": {
        "action_type": "auto",
        "description": "Answers stock/inventory questions, RAG-grounded against the company's own inventory records",
    },
    "vendor_status_update": {
        "action_type": "template_restricted",
        "description": "Delay/status notification to a vendor using pre-approved templates",
        "templates": {
            "delay_notification_v1": {
                "subject": "Order Delay Notification",
                "body": "Dear {vendor_name}, we would like to inform you that order #{order_ref} "
                        "is currently delayed. Expected revised delivery: {revised_date}. "
                        "Please confirm receipt of this update. Regards, {company_name}.",
            },
            "delivery_confirmed_v1": {
                "subject": "Delivery Confirmation",
                "body": "Dear {vendor_name}, we confirm receipt of delivery for order #{order_ref} "
                        "on {delivery_date}. Thank you for your prompt service. Regards, {company_name}.",
            },
            "quality_issue_v1": {
                "subject": "Quality Issue Report",
                "body": "Dear {vendor_name}, we have identified a quality issue with order #{order_ref}. "
                        "Details: {issue_description}. Please advise on next steps. Regards, {company_name}.",
            },
        },
    },
    "purchase_order_approval": {
        "action_type": "approval_required",
        "description": "AI drafts a PO when a reorder trigger fires; Department Head must manually type quantity and amount",
        "manual_fields": ["quantity", "amount"],
    },
    "workflow_exception_approval": {
        "action_type": "approval_required",
        "description": "Agent evaluates a request against SOP limits, flags/drafts reasoning when it's an exception",
    },
}


def get_tool_config(tool_name: str) -> dict:
    """Look up a tool's risk classification and config. Raises KeyError if tool doesn't exist."""
    if tool_name not in TOOL_REGISTRY:
        raise KeyError(f"Unknown tool: {tool_name}. Valid tools: {list(TOOL_REGISTRY.keys())}")
    return TOOL_REGISTRY[tool_name]


def get_action_type(tool_name: str) -> str:
    """Convenience: get just the action_type for a tool."""
    return get_tool_config(tool_name)["action_type"]
