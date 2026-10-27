"""AWS Lambda handler for invoking Amazon Bedrock AgentCore Runtime (vac_planner).

This function bridges client callers (API Gateway, Lambda Function URL, or direct invocation)
to the Bedrock AgentCore Runtime microVMs running vac_planner.

Service: bedrock-agentcore
Method: invoke_agent_runtime
"""

import json
import logging
import os
import time
import uuid
from typing import Any, Dict

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

# Configuration from environment variables
DEFAULT_RUNTIME_ARN = "arn:aws:bedrock-agentcore:us-east-1:837873138218:runtime/vac_planner-4M3CfW8SGa"
AGENT_RUNTIME_ARN = os.environ.get("AGENT_RUNTIME_ARN", DEFAULT_RUNTIME_ARN)
TARGET_REGION = os.environ.get("TARGET_REGION") or os.environ.get("AWS_REGION") or "us-east-1"
QUALIFIER = os.environ.get("QUALIFIER", "DEFAULT")

# Reusable boto3 client
_client = None


def get_agentcore_client():
    global _client
    if _client is None:
        _client = boto3.client("bedrock-agentcore", region_name=TARGET_REGION)
    return _client


def generate_session_id(provided_id: str | None = None) -> str:
    """AgentCore requires runtimeSessionId to be >= 33 characters.

    Every new SessionId creates a new MicroVM in the AgentCore runtime.
    """
    if provided_id and len(str(provided_id).strip()) >= 33:
        return str(provided_id).strip()

    # Generate a unique 33+ char session ID (e.g. vac-session-<uuid4>) -> 48 chars
    return f"vac-session-{uuid.uuid4()}"


def extract_request_data(event: Dict[str, Any]) -> Dict[str, Any]:
    """Normalizes event payload from direct invoke, API Gateway, or Function URL."""
    # API Gateway / Function URL body parsing
    if "body" in event and event["body"] is not None:
        body = event["body"]
        if isinstance(body, str):
            try:
                return json.loads(body)
            except json.JSONDecodeError:
                return {"prompt": body}
        elif isinstance(body, dict):
            return body

    return event


def build_agentcore_payload(request_data: Dict[str, Any]) -> str:
    """Prepares the payload JSON string for the vac_planner runtime container.

    vac_planner runtime accepts:
      1) {"path": "/ping"} -> health check
      2) {"inputs": {"origin": ..., "travel_dates": ..., "travelers": ..., "budget": ..., "interests": ...}}
      3) {"prompt": "..."} -> user prompt
    """
    # 1. Health ping check
    if "path" in request_data:
        return json.dumps({"path": request_data["path"]})

    # 2. Explicit inputs dictionary
    if "inputs" in request_data and isinstance(request_data["inputs"], dict):
        return json.dumps({"inputs": request_data["inputs"]})

    # 3. Top-level vac_planner inputs
    vac_keys = ("origin", "travel_dates", "travelers", "budget", "interests")
    if any(k in request_data for k in vac_keys):
        inputs = {k: request_data.get(k, "") for k in vac_keys}
        return json.dumps({"inputs": inputs})

    # 4. Prompt provided
    if "prompt" in request_data:
        return json.dumps({"prompt": request_data["prompt"]})

    # 5. Fallback: pass request_data directly
    return json.dumps(request_data)


def format_response(status_code: int, body_data: Any) -> Dict[str, Any]:
    """Returns standardized response structure compatible with API Gateway / Function URL."""
    body_str = json.dumps(body_data) if not isinstance(body_data, str) else body_data
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Amz-Date, X-Api-Key",
        },
        "body": body_str,
    }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Main Lambda entrypoint."""
    logger.info("Received event: %s", json.dumps(event, default=str))

    # Lambda's own health check for HTTP GET /ping via Function URL / API Gateway (no runtime call).
    # To health-check the runtime itself, send {"path": "/ping"} as the payload instead.
    http_method = event.get("httpMethod") or event.get("requestContext", {}).get("http", {}).get("method")
    raw_path = event.get("rawPath") or event.get("path")
    if http_method == "GET" and raw_path == "/ping":
        return format_response(
            200,
            {
                "status": "Healthy",
                "service": "vac-planner-agentcore-invoker",
                "agentRuntimeArn": AGENT_RUNTIME_ARN,
                "qualifier": QUALIFIER,
                "region": TARGET_REGION,
            },
        )

    request_data = extract_request_data(event)

    # Session ID handling (must be 33+ characters)
    session_id = generate_session_id(
        request_data.get("runtimeSessionId") or request_data.get("sessionId")
    )

    # Target Runtime ARN & Qualifier
    runtime_arn = request_data.get("agentRuntimeArn") or AGENT_RUNTIME_ARN
    qualifier = request_data.get("qualifier") or QUALIFIER

    # Build payload string
    payload_str = build_agentcore_payload(request_data)
    logger.info(
        "Invoking AgentCore Runtime ARN: %s with Session ID: %s, Qualifier: %s",
        runtime_arn,
        session_id,
        qualifier,
    )

    try:
        client = get_agentcore_client()

        invoke_params = {
            "agentRuntimeArn": runtime_arn,
            "runtimeSessionId": session_id,
            "payload": payload_str,
        }
        if qualifier:
            invoke_params["qualifier"] = qualifier

        start_time = time.time()
        response = client.invoke_agent_runtime(**invoke_params)
        duration = time.time() - start_time
        logger.info("AgentCore invocation completed in %.2f seconds", duration)

        # Read StreamingBody response
        raw_body = response.get("response").read()
        try:
            response_data = json.loads(raw_body.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            response_data = {"rawResponse": raw_body.decode("utf-8", errors="replace")}

        result = {
            "runtimeSessionId": session_id,
            "agentRuntimeArn": runtime_arn,
            "durationSeconds": round(duration, 2),
            "response": response_data,
        }
        return format_response(200, result)

    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "ClientError")
        error_msg = e.response.get("Error", {}).get("Message", str(e))
        logger.error("ClientError invoking AgentCore: %s - %s", error_code, error_msg, exc_info=True)
        return format_response(
            502,
            {
                "error": "AgentCoreInvocationFailed",
                "code": error_code,
                "message": error_msg,
                "runtimeSessionId": session_id,
            },
        )
    except Exception as e:
        logger.error("Unexpected error in lambda_handler: %s", str(e), exc_info=True)
        return format_response(
            500,
            {
                "error": "InternalServerError",
                "message": str(e),
                "runtimeSessionId": session_id,
            },
        )
