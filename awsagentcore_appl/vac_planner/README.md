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

## Observability & OpenTelemetry (ADOT)

This project integrates the **AWS Distro for OpenTelemetry (ADOT)** (`aws-opentelemetry-distro`) for end-to-end distributed tracing, agent observability, and CloudWatch metrics.

### Key Features
- **Auto-Instrumentation for CrewAI**: Uses ADOT's built-in `aws_crewai` instrumentor to trace multi-agent workflows, tasks, LLM calls, tool executions, and token metrics adhering to OpenTelemetry GenAI semantic conventions.
- **AWS X-Ray Distributed Tracing**: Auto-configured with X-Ray trace IDs, SigV4 authentication, and context propagation (`baggage,xray,tracecontext`).
- **CloudWatch Logs & Metrics**: Trace-correlated logging (`OTEL_PYTHON_LOG_CORRELATION=true`) routed to AgentCore runtime log groups, with CloudWatch metrics emission.

### Environment Configuration

| Variable | Recommended Value | Description |
|---|---|---|
| `OTEL_PYTHON_DISTRO` | `aws_distro` | Activates AWS OpenTelemetry distro |
| `OTEL_PYTHON_CONFIGURATOR` | `aws_configurator` | Configures AWS OTLP exporters, X-Ray ID generator, and SigV4 |
| `AGENT_OBSERVABILITY_ENABLED` | `true` | Enables native Agentic AI monitoring (including `aws_crewai`) |
| `OTEL_SERVICE_NAME` | `vac_planner` | Logical service name for traces and metrics |
| `CREWAI_DISABLE_TELEMETRY` | `true` | Prevents telemetry leakage and avoids duplicate tracing |
| `OTEL_EXPORTER_OTLP_LOGS_HEADERS` | `x-aws-log-group=...,x-aws-log-stream=...` | CloudWatch log group and stream headers for OTLP logs |

### Running with OpenTelemetry Instrumentation

```bash
# Via opentelemetry-instrument CLI wrapper:
opentelemetry-instrument python server.py

# Or in Docker (pre-configured in Dockerfile):
docker run --rm -p 8080:8080 \
  -e AGENT_OBSERVABILITY_ENABLED=true \
  -e MISTRAL_API_KEY=$env:MISTRAL_API_KEY \
  vac-planner
```