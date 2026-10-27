# AWS Lambda Deployment for Bedrock AgentCore Runtime (vac_planner)

This directory contains the AWS Lambda function and deployment automation to invoke the **vac_planner** agent running on **Amazon Bedrock AgentCore Runtime**.

---

## Architecture Overview

```
[Client / API Gateway / Function URL]
                 │
                 ▼
     [AWS Lambda Function]
  (vac-planner-agentcore-invoker)
                 │
                 ▼ boto3: invoke_agent_runtime
[Bedrock AgentCore Runtime Data Plane]
(arn:aws:bedrock-agentcore:us-east-1:...:runtime/vac_planner-4M3CfW8SGa)
                 │
                 ▼ (Port 8080 / MicroVM)
      [vac_planner Container]
      (CrewAI Multi-Agent Execution)
```

---

## Files

- [lambda_function.py](lambda_function.py): The Python Lambda handler. Handles session IDs (>= 33 chars), payload formatting, invocation via `bedrock-agentcore`, and response stream parsing.
- [lambdaDeployment.ps1](lambdaDeployment.ps1): Automated PowerShell deployment script (IAM role setup, dependency bundling, function create/update, Function URL, and smoke testing).
- [test-event-ping.json](test-event-ping.json): Fast health check event (`{"path": "/ping"}`) that checks container status without incurring LLM charges.
- [test-event-vacation.json](test-event-vacation.json): Full vacation planning request with sample inputs.

---

## Prerequisites

1. **AWS CLI v2** installed and configured:
   ```powershell
   aws login
   # or
   aws configure
   ```
2. **Python 3.10+** and `pip` available in PATH.
3. Target **AgentCore Runtime ARN**:
   `arn:aws:bedrock-agentcore:us-east-1:837873138218:runtime/vac_planner-4M3CfW8SGa`

---

## Deployment Instructions

### 1. Standard Deployment with Ping Test
Uses existing role `AgentCoreRuntime-vac-planner` by default:
```powershell
cd Deployment
.\lambdaDeployment.ps1
```

### 2. Deploy with Public HTTPS Function URL
```powershell
.\lambdaDeployment.ps1 -CreateFunctionUrl
```

### 3. Deploy and Run Full Multi-Agent Vacation Plan Test
```powershell
.\lambdaDeployment.ps1 -TestFull
```

### 4. Custom Parameters
```powershell
.\lambdaDeployment.ps1 `
    -FunctionName "my-vac-planner-invoker" `
    -Region "us-east-1" `
    -Timeout 900 `
    -MemorySize 512 `
    -CreateFunctionUrl
```

---

## Invoking the Lambda Function

### Via AWS CLI

**Health check ping:**
```powershell
aws lambda invoke `
    --function-name vac-planner-agentcore-invoker `
    --cli-binary-format raw-in-base64-out `
    --payload '{"path": "/ping"}' `
    response.json
Get-Content response.json
```

**Full vacation planning query:**
```powershell
aws lambda invoke `
    --function-name vac-planner-agentcore-invoker `
    --cli-binary-format raw-in-base64-out `
    --payload fileb://test-event-vacation.json `
    --cli-read-timeout 950 `
    response.json
Get-Content response.json
```

### Via Python (boto3)

```python
import boto3
import json

lambda_client = boto3.client('lambda', region_name='us-east-1')

payload = {
    "inputs": {
        "origin": "Seattle",
        "travel_dates": "June 10-17, 2027",
        "travelers": "2 adults",
        "budget": "$5,000",
        "interests": "food, hiking, history"
    }
}

response = lambda_client.invoke(
    FunctionName='vac-planner-agentcore-invoker',
    InvocationType='RequestResponse',
    Payload=json.dumps(payload)
)

result = json.loads(response['Payload'].read())
print(json.dumps(result, indent=2))
```

### Via Function URL (curl)

If `-CreateFunctionUrl` was used:
```bash
# Health check
curl -X POST https://<function-url-id>.lambda-url.us-east-1.on.aws/ \
  -H "Content-Type: application/json" \
  -d '{"path": "/ping"}'

# Full planning
curl -X POST https://<function-url-id>.lambda-url.us-east-1.on.aws/ \
  -H "Content-Type: application/json" \
  --max-time 900 \
  -d @test-event-vacation.json
```

---

## Key Configuration Details

- **Timeout:** Set to **900 seconds (15 minutes)**. A multi-agent CrewAI flow executing research, itinerary planning, and cost calculation typically takes 1 to 3 minutes to complete.
- **Session IDs:** AgentCore requires `runtimeSessionId` to be **33+ characters**. The Lambda function automatically generates a valid UUID-based session ID if none is supplied. Every unique session ID spins up a dedicated MicroVM.
- **Dependency Bundling:** By default, `lambdaDeployment.ps1` bundles up-to-date `boto3` and `botocore` packages into the zip archive to guarantee that the `bedrock-agentcore` service model is present in the Lambda execution environment.
