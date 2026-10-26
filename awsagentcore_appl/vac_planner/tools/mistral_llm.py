"""Mistral LLM routed through CrewAI's native OpenAI-compatible client.

The "mistral/..." string goes through LiteLLM, which forwards CrewAI's internal
`cache_breakpoint` message flag to Mistral's API and gets rejected with
"extra_forbidden". The native client strips that flag before sending.
"""

import os

from crewai import LLM

mistral_large = LLM(
    model="mistral-large-latest",
    provider="openai",
    base_url="https://api.mistral.ai/v1",
    api_key=os.environ.get("MISTRAL_API_KEY"),
    timeout=180,
    max_retries=5,
)
