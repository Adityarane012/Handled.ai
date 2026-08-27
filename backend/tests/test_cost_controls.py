"""
Phase 3.2 — cost-control guardrails.

The real risk on a paid provider is a runaway agent loop. Confirm the CrewAI
iteration / rate caps are actually loaded from .env and applied to the agent,
and that the LLM failure path is bounded (returns, does not retry forever).
"""
import os

import pytest

import agent.crew as crew


def test_crew_caps_loaded_from_env():
    assert crew.CREW_MAX_ITER == int(os.getenv("CREW_MAX_ITER", "6"))
    assert crew.CREW_MAX_RPM == int(os.getenv("CREW_MAX_RPM", "10"))


def test_caps_are_sane_bounds():
    assert 1 <= crew.CREW_MAX_ITER <= 12
    assert 1 <= crew.CREW_MAX_RPM <= 60


def test_agent_object_carries_the_caps():
    agent = crew._ops_agent()
    assert agent.max_iter == crew.CREW_MAX_ITER
    assert agent.max_rpm == crew.CREW_MAX_RPM
    assert agent.allow_delegation is False  # no fan-out to other agents


@pytest.mark.real_llm
def test_generate_is_bounded_on_llm_failure(monkeypatch):
    """With no reachable model, _generate must return labelled text, not raise/hang."""
    monkeypatch.setattr(crew, "LLM_PROVIDER", "ollama")
    monkeypatch.setattr(crew, "LLM_MODEL", "does-not-exist-model")
    monkeypatch.setattr(crew, "OLLAMA_BASE_URL", "http://127.0.0.1:1")  # nothing listening
    out = crew._generate("say hi", "a greeting")
    assert isinstance(out, str) and out            # returned, didn't raise
    assert "fallback" in out.lower() or "unavailable" in out.lower()


def test_spend_cap_env_present():
    """Not enforceable in code (provider-side), but must be declared for the checklist."""
    assert os.getenv("LLM_MONTHLY_SPEND_CAP_USD") not in (None, "")
