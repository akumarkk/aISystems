"""HTTP entrypoint for running the vac_planner crew in a container.

Follows the Amazon Bedrock AgentCore Runtime contract (port 8080,
GET /ping, POST /invocations), which also works behind ECS, App Runner,
or any load balancer that can health-check /ping.

POST /invocations body:
  {"inputs": {"origin": "Seattle", "travel_dates": "June 10-17, 2027",
              "travelers": "2 adults", "budget": "$5,000",
              "interests": "food, hiking, history"}}
merged over crew.jsonc "inputs".
"""

import json
import os
import tomllib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from crewai.project.crew_loader import load_crew_and_kickoff

ROOT = Path(__file__).parent
CREW_PATH = ROOT / "crew.jsonc"

# Single source of truth: [project].version in pyproject.toml
VERSION = tomllib.loads((ROOT / "pyproject.toml").read_text())["project"]["version"]

# Placeholders used in crew.jsonc / agents/*.jsonc
REQUIRED_INPUTS = ("origin", "travel_dates", "travelers", "budget", "interests")


class Handler(BaseHTTPRequestHandler):
    def _send(self, status: int, body: dict) -> None:
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        if self.path == "/ping":
            self._send(200, {"status": "Healthy", "version": VERSION})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self) -> None:
        if self.path != "/invocations":
            self._send(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            request = json.loads(self.rfile.read(length) or b"{}")
            # AgentCore only proxies POST /invocations, so {"path": "/ping"} routes to do_GET
            if request.get("path") == "/ping":
                self.path = "/ping"
                self.do_GET()
                return
            inputs = request.get("inputs") or {}
            missing = [k for k in REQUIRED_INPUTS if not str(inputs.get(k, "")).strip()]
            if missing:
                self._send(400, {"error": "missing required inputs", "missing": missing})
                return
            result = load_crew_and_kickoff(CREW_PATH, inputs)
            self._send(200, {"result": result.raw})
        except Exception as exc:
            self._send(500, {"error": str(exc)})


def load_secrets() -> None:
    """On AWS, pull MISTRAL_API_KEY from Secrets Manager instead of a plain env var."""
    secret_id = os.environ.get("MISTRAL_SECRET_ID")
    if secret_id and not os.environ.get("MISTRAL_API_KEY"):
        import boto3

        client = boto3.client("secretsmanager")
        os.environ["MISTRAL_API_KEY"] = client.get_secret_value(SecretId=secret_id)["SecretString"]


if __name__ == "__main__":
    load_secrets()
    port = int(os.environ.get("PORT", "8080"))
    print(f"vac_planner {VERSION} listening on :{port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
