from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from db.session import get_db
from routers.auth import get_tenant_ctx
from models.schemas import InventoryQuestion, InventoryUpload
from agent.crew import run_tool
from agent.rag import index_inventory_document, retrieve_inventory_chunks

router = APIRouter()


@router.post("/inventory-upload")
def upload_inventory(
    payload: InventoryUpload,
    db: Session = Depends(get_db),
    ctx=Depends(get_tenant_ctx),
):
    """Index (replace) this company's inventory document for `inventory_qa` retrieval."""
    n_chunks = index_inventory_document(str(ctx.company_id), payload.doc_text, payload.source)
    return {"indexed_chunks": n_chunks}


@router.post("/inventory-qa")
def answer_inventory_question(
    payload: InventoryQuestion,
    db: Session = Depends(get_db),
    ctx=Depends(get_tenant_ctx),
):
    """
    `inventory_qa` (auto bucket, RAG-grounded). Retrieves this company's own
    inventory passages, answers from them only, refuses to guess when nothing
    relevant is retrieved. Runs and logs immediately — no approval.
    """
    chunks = retrieve_inventory_chunks(str(ctx.company_id), payload.question)
    action = run_tool(
        "inventory_qa",
        {"question": payload.question, "context_chunks": chunks},
        ctx.company_id,
        db,
    )
    return {
        "id": str(action.id),
        "status": action.status,
        "tool_name": action.tool_name,
        "answer": action.draft_output.get("agent_output"),
        "retrieved_chunks": len(chunks),
        "grounded": bool(chunks),
    }
