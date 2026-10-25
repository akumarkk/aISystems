"""Workaround for crewai 1.15.30: the LiteLLM fallback path forwards the
internal ``cache_breakpoint`` message flag to the provider. Native providers
strip it, but strict APIs reached through LiteLLM (e.g. Mistral) reject it
with ``extra_forbidden``. Remove this once CrewAI strips it upstream.
"""

from typing import Any

from crewai.llm import LLM
from crewai.llms.cache import CACHE_BREAKPOINT_KEY

_original_format = LLM._format_messages_for_provider


def _format_without_cache_breakpoint(self: LLM, messages: Any) -> Any:
    # Copy so the executor's buffer keeps its markers for later iterations.
    if messages:
        messages = [
            {k: v for k, v in m.items() if k != CACHE_BREAKPOINT_KEY}
            if isinstance(m, dict)
            else m
            for m in messages
        ]
    return _original_format(self, messages)


LLM._format_messages_for_provider = _format_without_cache_breakpoint


def strip_cache_breakpoint(inputs: dict[str, Any]) -> dict[str, Any]:
    """before_kickoff hook; importing this module applies the patch."""
    return inputs
