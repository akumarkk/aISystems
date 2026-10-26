# vac_planner

A crewAI project using JSON-first configuration.

## Running

```bash
crewai run
```

## Project Structure

- `agents/` - Agent definitions (JSONC)
- `crew.jsonc` - Crew definition with tasks and configuration
- `tools/` - Custom tools (Python)
- `knowledge/` - Knowledge files for agents

> **Note:** `custom:<name>` tool references execute `tools/<name>.py` as local
> Python code when the crew loads. Only run crew projects from sources you
> trust.



##### docker
```

docker build -t vac-planner .

// For AWS AgentCore Runtime (needs an arm64 image)
docker buildx build --platform linux/arm64 -t vac-planner:arm64 --load .


docker run --rm -p 8080:8080 -e MISTRAL_API_KEY=$env:MISTRAL_API_KEY vac-planner


validation
```

###### Validation
```
$r = Invoke-RestMethod -Method Post -Uri http://localhost:8080/invocations `
  -ContentType "application/json" -TimeoutSec 1800 `
  -Body (Get-Content sample_request.json -Raw)
$r.result

```