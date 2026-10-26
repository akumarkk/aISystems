# --- set these ---
$REGION  = "us-east-1"
$REPO    = "vac-planner"
$TAG = "v0.2.0-port8080"
$ACCOUNT = aws sts get-caller-identity --query Account --output text
$REGISTRY = "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
$IMAGE    = "$REGISTRY/${REPO}:$TAG"

# 1. Create the repo (only the first time; errors harmlessly if it exists)
# aws ecr create-repository --repository-name $REPO --region $REGION `
#   --image-scanning-configuration scanOnPush=true

# # 2. Log Docker in to ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY

# # 3. Build for linux/arm64 and push in one step
docker buildx build --platform linux/arm64 -t $IMAGE --push .

# 4. Check that image arrived
aws ecr describe-images --repository-name $REPO --region $REGION `
  --query "imageDetails[].{tags:imageTags,pushed:imagePushedAt,size:imageSizeInBytes}" --output table

# ===================== Bedrock AgentCore Runtime =====================
$RUNTIME_NAME = "vac_planner"            # letters, digits, underscores only
$ROLE_NAME    = "AgentCoreRuntime-vac-planner"
$SECRET_NAME  = "vac-planner/mistral-api-key"
$TMP          = Join-Path $env:TEMP "vac_planner_agentcore"
New-Item -ItemType Directory -Force $TMP | Out-Null

# PowerShell 5.1 mangles inline JSON passed to native exes, so every JSON arg goes via file:// (UTF-8, no BOM)
function Write-Json($name, $obj) {
  $path = Join-Path $TMP $name
  [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 10 -Compress))
  "file://$path"
}

# 5. Mistral key in Secrets Manager (first time only: set $env:MISTRAL_API_KEY before running)
aws secretsmanager describe-secret --secret-id $SECRET_NAME --region $REGION 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  aws secretsmanager create-secret --name $SECRET_NAME --region $REGION --secret-string $env:MISTRAL_API_KEY
}
$SECRET_ARN = aws secretsmanager describe-secret --secret-id $SECRET_NAME --region $REGION --query ARN --output text

# 6. Execution role the runtime assumes (pull image, write logs/traces, read the secret)
$ROLE_ARN = "arn:aws:iam::837873138218:role/AgentCoreRuntime-vac-planner"

# 7. Create the runtime, or roll out the new image if it already exists
$artifact = Write-Json "artifact.json" @{ containerConfiguration = @{ containerUri = $IMAGE } }
$network  = Write-Json "network.json"  @{ networkMode = "PUBLIC" }   # dev only; use VPC mode for production
$protocol = Write-Json "protocol.json" @{ serverProtocol = "HTTP" }
$envvars  = Write-Json "env.json"      @{ MISTRAL_SECRET_ID = $SECRET_NAME }

$RUNTIME_ID = aws bedrock-agentcore-control list-agent-runtimes --region $REGION `
  --query "agentRuntimes[?agentRuntimeName=='$RUNTIME_NAME'].agentRuntimeId | [0]" --output text
if ($RUNTIME_ID -eq "None" -or -not $RUNTIME_ID) {
  $RUNTIME_ID = aws bedrock-agentcore-control create-agent-runtime --region $REGION `
    --agent-runtime-name $RUNTIME_NAME --role-arn $ROLE_ARN `
    --agent-runtime-artifact $artifact --network-configuration $network `
    --protocol-configuration $protocol --environment-variables $envvars `
    --query agentRuntimeId --output text
} else {
  aws bedrock-agentcore-control update-agent-runtime --region $REGION --agent-runtime-id $RUNTIME_ID `
    --role-arn $ROLE_ARN --agent-runtime-artifact $artifact --network-configuration $network `
    --protocol-configuration $protocol --environment-variables $envvars | Out-Null
}

# 8. Wait until READY (the DEFAULT endpoint follows the latest version)
do {
  Start-Sleep -Seconds 10
  $status = aws bedrock-agentcore-control get-agent-runtime --region $REGION --agent-runtime-id $RUNTIME_ID `
    --query status --output text
  Write-Host "runtime $RUNTIME_ID : $status"
} while ($status -in @("CREATING", "UPDATING"))
$RUNTIME_ARN = aws bedrock-agentcore-control get-agent-runtime --region $REGION --agent-runtime-id $RUNTIME_ID `
  --query agentRuntimeArn --output text
aws bedrock-agentcore-control list-agent-runtime-endpoints --region $REGION --agent-runtime-id $RUNTIME_ID --output table

# 9. Smoke test. A full crew run takes minutes, so turn off the CLI's 60s read timeout.
$payload = Join-Path $TMP "payload.json"
[IO.File]::WriteAllText($payload, (@{ inputs = @{
  origin = "Seattle"; travel_dates = "June 10-17, 2027"; travelers = "2 adults"
  budget = "`$5,000"; interests = "food, hiking, history" } } | ConvertTo-Json -Compress))
$SESSION = [guid]::NewGuid().ToString() + "-vac"   # runtime session ids must be >= 33 chars
aws bedrock-agentcore invoke-agent-runtime --region $REGION --cli-read-timeout 0 `
  --agent-runtime-arn $RUNTIME_ARN --runtime-session-id $SESSION `
  --content-type application/json --payload "fileb://$payload" (Join-Path $TMP "response.json")
Get-Content (Join-Path $TMP "response.json")