# CrewAI Single-Agent Sample (Mistral)

A minimal CrewAI application with one agent, using Mistral as the LLM provider.

## Requirements

- **Python 3.10–3.13** (3.12 recommended — Python 3.14 fails because
  `regex`/`tiktoken` have no prebuilt wheels for it yet)
- A Mistral API key ([console.mistral.ai](https://console.mistral.ai/))

## Setup

```powershell
# 1. (One-time) Install Python 3.12 if you only have 3.14:
winget install Python.Python.3.12
# Restart your terminal afterwards

# 2. Create a virtual environment
py -3.12 -m venv .venv

# 3. Activate it (PowerShell)
.venv\Scripts\Activate.ps1
# cmd: .venv\Scripts\activate.bat

# 4. Upgrade pip and install dependencies
python -m pip install --upgrade pip
python -m pip install crewai
python -m pip install -q "crewai[litellm]==1.1.0"

# 5. Set your Mistral API key
$env\:MISTRAL_API_KEY = "your-key-here"   # current session only


python -c "from crewai import LLM; print(LLM(model='mistral/mistral-large-latest').call('Say hi in 3 words'))"

# 6. Run
python app.py
```

## Notes

- **Always use `python -m pip`** instead of bare `pip` in a venv on Windows —
  it guarantees the venv's pip is used.
- If activation is blocked: `Set-ExecutionPolicy -Scope Process RemoteSigned`
  or call the venv Python directly: `.venv\Scripts\python.exe app.py`
- To recreate the venv from scratch: `Remove-Item -Recurse -Force .venv`
- The `mistral/` prefix in the model string routes calls to the Mistral API
  via LiteLLM; no OpenAI key is needed.

## Troubleshooting
   Error | Fix |
 |---|---|
 | `ModuleNotFoundError: No module named 'crewai'` | Venv not activated, or install went to the global Python |
 | `Failed building wheel for regex / tiktoken` | You're on Python 3.14 — use 3.12/3.13 |
 | `No suitable Python runtime found` | Run `winget install Python.Python.3.12`, restart terminal, check `py --list` |
 | `Remove-Item: positional parameter` | You're in PowerShell, not cmd — use `Remove-Item -Recurse -Force .venv` |