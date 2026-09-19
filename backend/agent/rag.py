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


# Inventory documents are overwhelmingly line-oriented — one SKU per row. An
# earlier 700-char setting packed ~5 unrelated SKUs into a single embedding,
# which diluted it badly: a question about bearings had to match a chunk that
# was mostly bolts and washers, so the distance cutoff dropped it and the tool
# answered "no matching inventory record" for questions the document could
# plainly answer. Keeping chunks near one record each is what makes retrieval
# precise enough to be useful.
_MAX_CHUNK_CHARS = int(os.environ.get("RAG_MAX_CHUNK_CHARS", "220"))


def _chunk(text: str, max_chars: int = None) -> List[str]:
    """
    Split into line-oriented chunks of roughly one inventory record each.

    Long prose lines still become their own chunk rather than being split
    mid-sentence, so a free-text inventory note degrades gracefully.
    """
    max_chars = max_chars or _MAX_CHUNK_CHARS
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

# Below this total size, the whole inventory is handed to the model instead of
# being retrieved over. This is a deliberate fit to the target user: an SME
# with 10-100 staff keeps a stock list of dozens of rows, not millions, and it
# comfortably fits the context window.
#
# It also fixes a real failure. Semantic retrieval matches a question against
# individual records, so it handles "how many 6204 bearings?" well but not
# aggregate questions like "which items are below their reorder point?" — that
# question isn't *about* any one row, so it sits just past the cutoff and the
# tool wrongly answered "no matching inventory record". Widening the cutoff
# would have fixed it only by also admitting noise for questions the document
# genuinely can't answer, which would break the refusal behaviour. Passing the
# whole small document sidesteps the tradeoff entirely.
_FULL_DOC_MAX_CHARS = int(os.environ.get("RAG_FULL_DOC_MAX_CHARS", "2500"))


def retrieve_inventory_chunks(company_id: str, question: str, k: int = 4) -> List[str]:
    """
    Return the inventory passages the question should be answered from.

    Small documents are returned whole (see _FULL_DOC_MAX_CHARS) so aggregate
    questions work. Larger ones fall back to semantic retrieval, dropping
    matches beyond _MAX_DISTANCE so "no matching record" doesn't rest on the
    prompt alone. Empty list means nothing relevant was found.
    """
    col = _collection(company_id)
    if col.count() == 0:
        return []

    everything = col.get()
    all_docs = [d for d in (everything.get("documents") or []) if d]
    if all_docs and sum(len(d) for d in all_docs) <= _FULL_DOC_MAX_CHARS:
        # Preserve the document's original row order — inventory lists read as
        # a table, and shuffling rows makes the model's answer harder to check.
        metas = everything.get("metadatas") or [{}] * len(all_docs)
        ordered = sorted(
            zip(all_docs, metas),
            key=lambda pair: (pair[1] or {}).get("chunk", 0),
        )
        return [d for d, _ in ordered]

    res = col.query(
        query_texts=[question],
        n_results=min(k, col.count()),
        include=["documents", "distances"],
    )
    docs = (res.get("documents") or [[]])[0]
    dists = (res.get("distances") or [[]])[0]
    return [doc for doc, dist in zip(docs, dists) if dist <= _MAX_DISTANCE]
