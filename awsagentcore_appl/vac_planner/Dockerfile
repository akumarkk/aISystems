# vac_planner crew container for AWS (Bedrock AgentCore Runtime, ECS/Fargate, App Runner).
# AgentCore Runtime requires linux/arm64:
#   docker buildx build --platform linux/arm64 -t vac-planner .
FROM python:3.13-slim

COPY --from=ghcr.io/astral-sh/uv:0.8.22 /uv /uvx /bin/

ENV PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PORT=8080 \
    PATH="/app/.venv/bin:$PATH" \
    OTEL_PYTHON_DISTRO=aws_distro \
    OTEL_PYTHON_CONFIGURATOR=aws_configurator \
    AGENT_OBSERVABILITY_ENABLED=true \
    OTEL_SERVICE_NAME=vac_planner \
    CREWAI_DISABLE_TELEMETRY=true \
    OTEL_EXPORTER_OTLP_LOGS_HEADERS="x-aws-log-group=/aws/bedrock-agentcore/runtimes/vac_planner,x-aws-log-stream=default"

WORKDIR /app

# Dependencies first so code edits don't invalidate this layer
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY crew.jsonc server.py ./
COPY agents/ agents/
COPY tools/ tools/
COPY knowledge/ knowledge/
COPY skills/ skills/

RUN useradd --create-home --uid 1000 app && chown -R app /app
USER app

EXPOSE 8080
CMD ["opentelemetry-instrument", "python", "server.py"]
