"""
Retrieval quality for `inventory_qa`.

These exist because of a real bug: chunking packed ~5 unrelated SKUs into one
700-char embedding, which diluted it enough that the distance cutoff dropped
everything, and the tool answered "no matching inventory record found" to
questions the uploaded document plainly answered. It was only visible by
inspecting seeded demo data — every unit test still passed.
"""
import uuid

import pytest

from agent import rag

INVENTORY = """\
SKU FAST-M8-50 | Hex Bolt M8x50 Grade 8.8 | on_hand 1840 | reorder_point 500 | vendor Shree Fasteners
SKU FAST-M10-60 | Hex Bolt M10x60 Grade 8.8 | on_hand 240 | reorder_point 400 | vendor Shree Fasteners
SKU WASH-M8 | Spring Washer M8 | on_hand 12500 | reorder_point 3000 | vendor Shree Fasteners
SKU BRG-6204 | Deep Groove Ball Bearing 6204-2RS | on_hand 46 | reorder_point 120 | vendor Nandi Bearings
SKU BELT-B55 | V-Belt B55 | on_hand 22 | reorder_point 60 | vendor Pune Rubber Works
"""


@pytest.fixture
def company():
    """A throwaway per-company collection, removed afterwards."""
    cid = uuid.uuid4().hex
    yield cid
    try:
        rag._client.delete_collection(name=f"inventory_{cid}".replace("-", ""))
    except Exception:
        pass


def test_line_oriented_doc_is_not_packed_into_mega_chunks():
    """
    The property that matters is dilution, not chunk count: the original bug
    put ~5 unrelated SKUs into one embedding, so a bearing question had to
    match a chunk that was mostly bolts and washers.
    """
    chunks = rag._chunk(INVENTORY)
    worst = max(c.count("SKU ") for c in chunks)
    assert worst <= 2, f"a chunk holds {worst} SKUs — embeddings will be diluted"


def test_specific_lookup_retrieves_the_right_record(company):
    rag.index_inventory_document(company, INVENTORY, "test")
    got = rag.retrieve_inventory_chunks(company, "How many 6204 bearings do we have?")
    assert any("BRG-6204" in c for c in got)


def test_retrieval_stays_narrow(company):
    """
    Context is kept small deliberately. Handing this model the whole stock list
    measurably cost recall on named-part lookups (17/17 correct with 3 rows in
    context, 8/11 with 9-10), so retrieval must narrow rather than dump.
    """
    rag.index_inventory_document(company, INVENTORY, "test")
    got = rag.retrieve_inventory_chunks(company, "How many 6204 bearings do we have?")
    assert 0 < len(got) <= 4, f"expected a narrowed result set, got {len(got)}"


def test_large_document_also_narrows(company):
    big = "".join(
        f"SKU ITEM-{i:04d} | Component number {i} | on_hand {i} | reorder_point 50 | vendor V{i % 7}\n"
        for i in range(300)
    )
    rag.index_inventory_document(company, big, "test")
    got = rag.retrieve_inventory_chunks(company, "How many of component number 42 do we have?")
    assert 0 < len(got) <= 4, f"expected a narrowed result set, got {len(got)}"


def test_nothing_indexed_returns_nothing(company):
    assert rag.retrieve_inventory_chunks(company, "anything at all?") == []
