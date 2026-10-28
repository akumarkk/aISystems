"""Lambda function to query DynamoDB TravelPlans table by TravelCity.

Supports:
- Direct invocation: {"TravelCity": "Paris"}
- API Gateway / Function URL query string: ?travelCity=Paris or ?TravelCity=Paris
- API Gateway / Function URL POST body: {"TravelCity": "Paris"}
"""

import json
import logging
import os
from decimal import Decimal
from typing import Any, Dict, List, Optional

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

TABLE_NAME = os.environ.get("TABLE_NAME", "TravelPlans")
REGION = os.environ.get("AWS_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
table = dynamodb.Table(TABLE_NAME)


class DecimalEncoder(json.JSONEncoder):
    """Encodes Decimal objects to int or float for JSON serialization."""

    def default(self, obj: Any) -> Any:
        if isinstance(obj, Decimal):
            if obj % 1 == 0:
                return int(obj)
            return float(obj)
        return super().default(obj)


def extract_city(event: Dict[str, Any]) -> Optional[str]:
    """Extracts city from query parameters, JSON body, or root event dict."""
    # 1. API Gateway / Function URL query string parameters
    query_params = event.get("queryStringParameters") or {}
    city = query_params.get("TravelCity") or query_params.get("travelCity") or query_params.get("city")
    if city:
        return city.strip()

    # 2. HTTP POST body if present
    body = event.get("body")
    if body:
        if isinstance(body, str):
            try:
                body = json.loads(body)
            except json.JSONDecodeError:
                body = {}
        if isinstance(body, dict):
            city = body.get("TravelCity") or body.get("travelCity") or body.get("city")
            if city:
                return city.strip()

    # 3. Direct invocation payload
    city = event.get("TravelCity") or event.get("travelCity") or event.get("city")
    if city and isinstance(city, str):
        return city.strip()

    return None


def query_travel_plans(travel_city: str) -> List[Dict[str, Any]]:
    """Queries the TravelPlans table using the TravelCity partition key."""
    items: List[Dict[str, Any]] = []
    query_kwargs = {
        "KeyConditionExpression": Key("TravelCity").eq(travel_city),
    }

    while True:
        response = table.query(**query_kwargs)
        items.extend(response.get("Items", []))

        last_evaluated_key = response.get("LastEvaluatedKey")
        if not last_evaluated_key:
            break
        query_kwargs["ExclusiveStartKey"] = last_evaluated_key

    return items


def build_response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    """Builds an API Gateway / Function URL compatible response."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
        },
        "body": json.dumps(body, cls=DecimalEncoder),
    }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """AWS Lambda entry point."""
    logger.info("Received event: %s", json.dumps(event, default=str))

    city = extract_city(event)
    if not city:
        logger.warning("Missing TravelCity in request event")
        return build_response(
            status_code=400,
            body={
                "error": "Missing required parameter 'TravelCity'",
                "usage": {
                    "queryString": "?travelCity=<CityName>",
                    "jsonPayload": {"TravelCity": "<CityName>"},
                },
            },
        )

    try:
        items = query_travel_plans(city)
        return build_response(
            status_code=200,
            body={
                "travelCity": city,
                "count": len(items),
                "plans": items,
            },
        )
    except ClientError as e:
        logger.error("DynamoDB Query error: %s", e)
        return build_response(
            status_code=500,
            body={
                "error": "Failed to query DynamoDB table",
                "details": e.response.get("Error", {}).get("Message", str(e)),
            },
        )
