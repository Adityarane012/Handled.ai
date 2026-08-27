import os
from crewai import Agent, Task, Crew, Process
from pydantic import BaseModel
from typing import Dict, Any, Optional

# Load env vars safely
CREW_MAX_ITER = int(os.getenv("CREW_MAX_ITER", 6))
CREW_MAX_RPM = int(os.getenv("CREW_MAX_RPM", 10))
LLM_PROVIDER = os.getenv("LLM_PROVIDER", "anthropic").lower()

def _get_llm():
    """Configure the LLM based on environment variables."""
    # CrewAI uses litellm under the hood
    if LLM_PROVIDER == "anthropic":
        return f"anthropic/{os.getenv('LLM_MODEL', 'claude-3-haiku-20240307')}"
    elif LLM_PROVIDER == "openai":
        return os.getenv('LLM_MODEL', 'gpt-3.5-turbo')
    elif LLM_PROVIDER == "gemini":
        return f"gemini/{os.getenv('LLM_MODEL', 'gemini-1.5-pro')}"

    return os.getenv('LLM_MODEL', 'gpt-3.5-turbo')

class AgentResponse(BaseModel):
    justification: str
    suggested_vendor: Optional[str] = None
    item_details: Optional[str] = None

def get_ops_agent():
    return Agent(
        role="Operations Assistant",
        goal="Analyze operations data, handle routine tasks accurately, and flag anything risky for human approval.",
        backstory="An expert operations agent designed to assist small companies with logistics, inventory, and vendor management.",
        verbose=True,
        allow_delegation=False,
        max_iter=CREW_MAX_ITER,
        max_rpm=CREW_MAX_RPM,
        llm=_get_llm()
    )

def draft_purchase_order_justification(item_name: str, current_stock: int, reorder_reason: str = None, preferred_vendor: str = None) -> Dict[str, Any]:
    """
    Run the CrewAI orchestration specifically for drafting a PO justification.
    Crucially, this NEVER predicts the quantity or amount (safety rule).
    """
    agent = get_ops_agent()

    task_description = f"""
    A reorder trigger has fired for the following inventory item:
    - Item Name: {item_name}
    - Current Stock: {current_stock}
    - Reorder Reason (if any provided): {reorder_reason or 'Stock is running low.'}
    - Preferred Vendor (if any provided): {preferred_vendor or 'Not specified. Recommend one if possible.'}

    Your task is to draft a professional justification for creating a Purchase Order for this item.
    DO NOT guess or suggest the quantity to order or the total amount. Those are strictly left for human entry.
    Only draft the reasoning for why the order is necessary, based on the provided context.

    Return a clear, concise justification paragraph.
    """

    po_task = Task(
        description=task_description,
        expected_output="A short, professional justification explaining why the purchase order is necessary. Do not include quantity or price.",
        agent=agent,
    )

    crew = Crew(
        agents=[agent],
        tasks=[po_task],
        process=Process.sequential,
        verbose=True
    )

    # In a real environment, this might throw if API key is invalid.
    try:
        result = crew.kickoff()
        # CrewAI returns a string (the final output of the task)
        return {
            "item_name": item_name,
            "current_stock": current_stock,
            "preferred_vendor": preferred_vendor,
            "reorder_reason": reorder_reason,
            "agent_justification": str(result)
        }
    except Exception as e:
        # If LLM fails (e.g. no API key), we return a fallback draft so the app doesn't crash during dev/demo
        return {
            "item_name": item_name,
            "current_stock": current_stock,
            "preferred_vendor": preferred_vendor,
            "reorder_reason": reorder_reason,
            "agent_justification": f"LLM Generation Failed (Check API Key). Fallback justification: Reorder required for {item_name} due to low stock ({current_stock}). Error: {str(e)}"
        }
