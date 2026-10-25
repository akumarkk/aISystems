# CrewAI Setup on Windows (PowerShell) — Full Guide & Fixes

Single-agent CrewAI crew, Mistral LLM, Python 3.12 venv on Windows.
 distilled from a real install session — every error below actually happened.

## 1. Python version: use 3.12 (NOT 3.14)

CrewAI depends on `regex` / `tiktoken`, which have **no prebuilt wheels for
Python 3.14** — pip tries to build from source and fails.

```powershell
py --list                                # see installed versions
winget install Python.Python.3.12        # if only 3.14 present
# RESTART terminal after install, then:
py --list                                # confirm 3.12 appears
```

> `py -3.12 -m venv .venv` → "No suitable Python runtime found"
> means 3.12 isn't installed; `winget install Python.Python.3.12`.

## 2. Scaffold + venv

```powershell
cd <projects-dir>
crewai create crew demo_ai_opps --no-interaction   # skip interactive wizard
cd demo_ai_opps
py -3.12 -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip crewai crewai-tools
```

- `--no-interaction` beats the wizard: editing the generated YAML is faster
  than answering prompts.
- **Always `python -m pip`**, never bare `pip` — guarantees the venv's pip
  (bare `pip` warning about other projects' packages = global Python).
- Activation blocked? `Set-ExecutionPolicy -Scope Process RemoteSigned`
  or call venv Python directly: `.venv\Scripts\python.exe main.py`

### Check which venv is active

```powershell
(Get-Command python).Path    # must contain the folder you're working in
```

### Switching projects

```powershell
deactivate
cd ..\other_project
.venv\Scripts\Activate.ps1
```

Rule: the active venv must match the current folder.

## 3. Mistral LLM config

`.env`:

```text
MODEL=mistral/mistral-large-latest
MISTRAL_API_KEY=<key from console.mistral.ai/api-keys>
```

`crew.py` — the `llm=` on the **Agent** is what avoids OpenAI fallback:

```python
from crewai import LLM
...
llm=LLM(model="mistral/mistral-large-latest")
```

- The `mistral/` prefix routes via LiteLLM to Mistral's API. No OpenAI key needed.
- A Mistral key sent with `anthropic/...` or `openai/...` prefix → **401 invalid x-api-key**.

## 4. Disable memory (avoids OPENAI_API_KEY demand)

CrewAI memory defaults to OpenAI embeddings (`text-embedding-3-large`):

```python
Crew(..., memory=False, verbose=True)
```

## 5. THE critical fix: litellm/mcp version clash

**Symptom:** `Failed to get streaming response: cannot import name
'CacheableResult' from 'mcp.types'`

**Root cause:** **litellm 1.106.0** (published Oct 2026) imports
`CacheableResult` from `mcp.types` — a symbol that only exists in **mcp 2.x**.
But crewai (and most agent frameworks) pin **mcp < 2**. So latest litellm +
any mcp 1.x = broken. (See litellm issue #46045.)

**Fix — pin litellm below 1.106, keep mcp 1.30.x:**

```powershell
python -m pip install --upgrade --force-reinstall --no-deps "mcp==1.30.0"
python -m pip install "litellm>=1.90,<1.106"
python -c "from importlib.metadata import version; print(version('litellm'), version('mcp'))"
```

**Dead ends we tried (don't repeat):**
   Attempt | Result |
 |---|---|
 | `mcp==1.6.0` | Import still fails — CacheableResult doesn't exist there either; also conflicts with langflow-base (wrong env) |
 | `mcp==1.16.0` / `1.20.0` | Same failure — **no mcp 1.x has the symbol** |
 | upgrading crewai alone | Doesn't help — the import is in litellm's chain |

The error message pointing at `mcp` is misleading — **the broken package is
litellm, not mcp.**

## 6. Verifying before a run

```powershell
python -c "from crewai import LLM; print(LLM(model='mistral/mistral-large-latest').call('Say hi in 3 words'))"
```

Prints a reply → key + provider config are good.

## 7. Run

```powershell
python main.py      # or: crewai run
```

## 8. Git hygiene

`.gitignore` (note: `Add-Content <file> "<line>"` — file first, content quoted):

```powershell
Add-Content .gitignore ".venv/"
Add-Content .gitignore "__pycache__/"
Add-Content .gitignore "*.pyc"
Add-Content .gitignore ".env"
```

- `git rm -r --cached .venv` → `pathspec did not match` = never tracked, nothing to undo.
- Undo `git add`: `git reset` (all) or `git reset <file>`.
- Scaffold's auto-created `.git` is read-only: `Remove-Item .\demo_ai_opps\.git\ -Recurse -Force`
  (add `-Force` for the read-only files; else `cmd /c "rmdir /s /q .git"`).

## 9. Deleting a locked venv

`Remove-Item -Recurse -Force .venv` fails with `UnauthorizedAccessException`
when a Python process still uses it:

```powershell
deactivate
Get-Process python* | Format-Table Id, ProcessName, Path
Stop-Process -Id <id>                 # or close VS Code/Cursor window for that folder
Remove-Item -Recurse -Force .venv
```

## 10. Error cheat-sheet
 | Error | Cause | Fix |
 |---|---|---|
 | `No suitable Python runtime found` | no 3.12 | `winget install Python.Python.3.12`, restart terminal |
 | `Failed building wheel for regex/tiktoken` | Python 3.14 | recreate venv with 3.12 |
 | `Remove-Item: positional parameter` | cmd syntax in PowerShell | `Remove-Item -Recurse -Force <path>` |
 | pip warns about other projects' deps | global pip | use `python -m pip` inside active venv |
 | `OPENAI_API_KEY is required` | agent has no `llm=` | set `llm=LLM(model="mistral/...")` on the Agent |
 | 401 `invalid x-api-key` | wrong provider prefix | use `mistral/` prefix + `MISTRAL_API_KEY` |
 | `CHROMA_OPENAI_API_KEY ... not set` | memory enabled | `memory=False` |
 | `cannot import name 'CacheableResult'` | litellm 1.106 + mcp 1.x | `litellm<1.106`, mcp 1.30.x (section 5) |
 | `AttributeError: module 'mcp' has no attribute '__version__'` | normal | use `importlib.metadata.version('mcp')` |
 | Cannot delete .venv (access denied) | locked by python process | section 9 |

## 11. Optional: uv instead of pip

```powershell
uv venv --python 3.12                    # venv without needing py launcher
uv pip install crewai crewai-tools       # pip-style into active venv
# or project-managed:
uv init
uv add "crewai[litellm]"
uv run python main.py                    # no activation needed
```

`uv add` writes `pyproject.toml` + `uv.lock` (reproducible via `uv sync`);
`uv pip install` is a plain pip drop-in.