import json
import os
import time
import requests
from typing import Type
from pydantic import BaseModel, Field
from crewai.tools import BaseTool

_tok = {"v": None, "exp": 0}

def _token() -> str:
    if _tok["v"] and time.time() < _tok["exp"] - 60:
        return _tok["v"]
    domain = os.environ["OIDC_AUTHORITY"]
    region = os.environ.get("AWS_REGION", "us-east-1")
    token_url = f"https://{domain}.auth.{region}.amazoncognito.com/oauth2/token"
    r = requests.post(
        token_url,
        data={"grant_type": "client_credentials",
              "client_id": os.environ["OIDC_CLIENTID_Local_Expert_City_Guide"],
              "client_secret": os.environ["OIDC_CLIENTSECRET_Local_Expert_City_Guide"]},
        timeout=15)
    r.raise_for_status()
    j = r.json()
    _tok.update(v=j["access_token"], exp=time.time() + j.get("expires_in", 3600))
    return _tok["v"]

class QueryTravelPlansInput(BaseModel):
    """Input schema for QueryTravelPlans tool."""
    TravelCity: str = Field(
        ...,
        description="Exact name of the destination city, e.g. 'Paris'."
    )

class QueryTravelPlans(BaseTool):
    name: str = "query_travel_plans"
    description: str = (
        "Look up saved travel plans for a destination city (exact name, e.g. 'Paris'). "
        "Use before creating a new itinerary to reuse existing plans."
    )
    args_schema: Type[BaseModel] = QueryTravelPlansInput

    def _run(self, TravelCity: str) -> str:
        body = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": {
                "name": "query-travel-plans___query_travel_plans",
                "arguments": {"TravelCity": TravelCity},
            },
        }
        r = requests.post(
            os.environ["GATEWAY_URL"],
            json=body,
            timeout=30,
            headers={
                "Authorization": f"Bearer {_token()}",
                "Accept": "application/json",
            },
        )
        r.raise_for_status()
        return json.dumps(r.json().get("result", r.json()))


#class QueryTravelPlansInput(BaseModel):
#    """Input schema for QueryTravelPlans tool."""
#    TravelCity: str = Field(
#        ...,
#        description="Exact name of the destination city, e.g. 'Paris'."
#   )
    
#@tool("query_travel_plans")
def query_travel_plans(TravelCity: str) -> str:
    """Look up saved travel plans for a destination city (exact name, e.g. 'Paris').
    Use before creating a new itinerary to reuse existing plans."""
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": "query-travel-plans___query_travel_plans",  # <target_name>___query_travel_plans
                       "arguments": {"TravelCity": TravelCity}}}
    r = requests.post(os.environ["GATEWAY_URL"], json=body, timeout=30,
                      headers={"Authorization": f"Bearer {_token()}",
                               "Accept": "application/json"})
    r.raise_for_status()
    return json.dumps(r.json().get("result", r.json()))
