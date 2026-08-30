"""
Minimal RAG store for the `inventory_qa` tool.

Prototype scope: one inventory document per company, chunked and embedded into a
persistent local Chroma collection. No Postgres schema change — embeddings live
in backend/.chroma/ (gitignored). Retrieval is per-company, so tenant isolation
holds here too (collection name is namespaced by company_id).

Embeddings use Chroma's built-in DefaultEmbeddingFunction (all-MiniLM ONNX,
~80 MB, downloaded once, then fully offline) — no API key, aligned with the
no-cost local phase.
"""
import os
import re
from typing import List

import chromadb
from chromadb.utils import embedding_functions

_CHROMA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), ".chroma")
_client = chromadb.PersistentClient(path=_CHROMA_DIR)
_embed_fn = embedding_functions.DefaultEmbeddingFunction()


def _collection(company_id: str):
    # ':' is not allowed in Chroma names; company_id is a UUID so it's safe.
    return _client.get_or_create_collection(
        name=f"inventory_{company_id}".replace("-", ""),
        embedding_function=_embed_fn,
    )


def _chunk(text: str, max_chars: int = 700) -> List[str]:
    """
    Split on blank lines / list rows first, then pack into ~max_chars chunks.
    Inventory docs are usually line-oriented (one item per line / short rows),
    so this keeps whole records together.
    """
    lines = [ln.strip() for ln in re.split(r"\n", text) if ln.strip()]
    chunks, buf = [], ""
    for ln in lines:
        if len(buf) + len(ln) + 1 > max_chars and buf:
            chunks.append(buf.strip())
            buf = ""
        buf += ln + "\n"
    if buf.strip():
        chunks.append(buf.strip())
    return chunks or [text.strip()]


def index_inventory_document(company_id: str, doc_text: str, source: str = "upload") -> int:
    """Replace this company's inventory index with the given document. Returns chunk count."""
    col = _collection(company_id)
    # Wipe prior contents (prototype = single current document per company).
    existing = col.get()
    if existing["ids"]:
        col.delete(ids=existing["ids"])

    chunks = _chunk(doc_text)
    col.add(
        ids=[f"{source}-{i}" for i in range(len(chunks))],
        documents=chunks,
        metadatas=[{"source": source, "chunk": i} for i in range(len(chunks))],
    )
    return len(chunks)


# hnsw defaults to l2 distance on normalized MiniLM embeddings, so lower is
# closer; a match past MAX_DISTANCE is treated as noise, not a real hit.
_MAX_DISTANCE = float(os.environ.get("RAG_MAX_DISTANCE", "1.1"))


def retrieve_inventory_chunks(company_id: str, question: str, k: int = 4) -> List[str]:
    """
    Return up to k inventory passages relevant to the question. Empty if nothing
    is indexed, or if the nearest matches are too far to be a real answer (rather
    than relying solely on the prompt to say "no matching record").
    """
    col = _collection(company_id)
    if col.count() == 0:
        return []
    res = col.query(
        query_texts=[question],
        n_results=min(k, col.count()),
        include=["documents", "distances"],
    )
    docs = (res.get("documents") or [[]])[0]
    dists = (res.get("distances") or [[]])[0]
    return [doc for doc, dist in zip(docs, dists) if dist <= _MAX_DISTANCE]
