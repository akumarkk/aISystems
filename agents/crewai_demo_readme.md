# Venv Setup for CrewAI Projects (Windows/PowerShell)

## Why Python 3.12 (not 3.14)

CrewAI depends on `regex` and `tiktoken`, which have **no prebuilt wheels for
Python 3.14** — pip tries to compile from source and fails. Use 3.11–3.13.

Check what's installed: `py --list`

If you only have 3.14, install 3.12, then **restart the terminal**:

```powershell
winget install Python.Python.3.12
```

## Create project + venv

```powershell
crewai create crew demo_ai_opps --no-interaction   # skip interactive wizard
cd demo_ai_opps
py -3.12 -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip crewai crewai-tools
```

**Always use `python -m pip`** (not bare `pip`) — guarantees the venv's pip.
If activation is blocked: `Set-ExecutionPolicy -Scope Process RemoteSigned`

## Configure Mistral LLM

`.env`:

```text
MODEL=mistral/mistral-large-latest
MISTRAL_API_KEY=<key from console.mistral.ai/api-keys>
```

`crew.py`:

```python
llm=LLM(model="mistral/mistral-large-latest")
```

The `mistral/` prefix routes via LiteLLM to Mistral's API — no OpenAI/Anthropic
keys needed. A Mistral key used with `anthropic/...` or `openai/...` gives 401.

## Disable memory (avoids OpenAI embedder requirement)

```python
@crew
def crew(self) -> Crew:
    return Crew(..., memory=False, verbose=True)
```

Default memory uses OpenAI embeddings → demands `OPENAI_API_KEY`.

## Run

```powershell
python main.py
```

## Troubleshooting
   Symptom | Fix |
 |---|---|
 | `No suitable Python runtime found` | 3.12 not installed → `winget install Python.Python.3.12`, restart terminal |
 | `Failed building wheel for regex/tiktoken` | You're on Python 3.14 → recreate venv with 3.12 |
 | pip warns about `langflow-base` etc. in your venv | pip is hitting global Python → use `python -m pip` |
 | `cannot import name 'CacheableResult' from 'mcp.types'` | crewai/mcp version clash → `python -m pip install --upgrade crewai` |
 | `OPENAI_API_KEY is required` / 401 `invalid x-api-key` | LLM not set to Mistral → fix `MODEL` in `.env` + `llm=` in `crew.py` |

## Deleting a locked venv

`Remove-Item -Recurse -Force .venv` fails when a Python process still uses it:

```powershell
deactivate
Get-Process python* | Format-Table Id, ProcessName, Path   # find the culprit
Stop-Process -Id <id>
Remove-Item -Recurse -Force .venv
```

Also close VS Code/Cursor windows for that folder (their Python extension
locks venv files).

## Git

`.gitignore`:

```text
.venv/
__pycache__/
*.pyc
.env
```

If `.venv` was committed: `git rm -r --cached .venv`
(Error `pathspec did not match` = it was never tracked; nothing to undo.)
Scaffold's `.git` can be deleted (files are read-only): add `-Force`, else
`cmd /c "rmdir /s /q .git"`.

## Switching between projects

```powershell
deactivate                          # leave current venv
cd ..\other_project
.venv\Scripts\Activate.ps1
```

Verify which venv is live: `(Get-Command python).Path`