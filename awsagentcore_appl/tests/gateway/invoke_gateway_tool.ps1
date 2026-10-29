<#
.SYNOPSIS
  Invokes a single tool on the AgentCore Gateway (MCP tools/call) using a Cognito client-credentials token.

.EXAMPLE
  .\invoke_gateway_tool.ps1 -TravelCity Paris
  .\invoke_gateway_tool.ps1 -ToolName "query-travel-plans___query_travel_plans" -Arguments @{ TravelCity = "Rome" }
#>
[CmdletBinding()]
param(
  [string]$ToolName = "query-travel-plans___query_travel_plans",
  [hashtable]$Arguments,
  [string]$TravelCity = "Paris",
  [string]$GatewayUrl,
  [string]$ClientId = $env:OIDC_CLIENTID_Local_Expert_City_Guide,
  [string]$ClientSecret = $env:OIDC_CLIENTSECRET_Local_Expert_City_Guide,
  [string]$OidcAuthority = $env:OIDC_AUTHORITY,
  [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$tf = Join-Path $root "Deployment\Terraform"

if (-not $Arguments) { $Arguments = @{ TravelCity = $TravelCity } }

if (-not $GatewayUrl) {
  Push-Location (Join-Path $tf "AgentCoreGateway")
  try { $GatewayUrl = terraform output -raw gateway_url } finally { Pop-Location }
}

if (-not $ClientSecret) {
  Push-Location (Join-Path $tf "AppClients")
  try { $ClientSecret = (terraform output -json client_secrets | ConvertFrom-Json).local_expert__city_guide }
  finally { Pop-Location }
}

foreach ($p in @{ GatewayUrl = $GatewayUrl; ClientId = $ClientId; ClientSecret = $ClientSecret; OidcAuthority = $OidcAuthority }.GetEnumerator()) {
  if (-not $p.Value) { throw "Missing required value: $($p.Key)" }
}

$tokenUrl = "https://$OidcAuthority.auth.$Region.amazoncognito.com/oauth2/token"
$token = (Invoke-RestMethod -Method Post $tokenUrl -ContentType "application/x-www-form-urlencoded" `
    -Body "grant_type=client_credentials&client_id=$ClientId&client_secret=$ClientSecret").access_token

$headers = @{ Authorization = "Bearer $token"; Accept = "application/json" }
$body = @{
  jsonrpc = "2.0"
  id      = 1
  method  = "tools/call"
  params  = @{ name = $ToolName; arguments = $Arguments }
} | ConvertTo-Json -Depth 10

Write-Host "Gateway : $GatewayUrl"
Write-Host "Tool    : $ToolName"
Write-Host "Args    : $($Arguments | ConvertTo-Json -Compress)"

try {
  $resp = Invoke-RestMethod -Method Post $GatewayUrl -Headers $headers -ContentType "application/json" -Body $body
  $resp | ConvertTo-Json -Depth 10
}
catch {
  Write-Error "tools/call failed: $($_.Exception.Message)"
  if ($_.Exception.Response) {
    (New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd()
  }
  exit 1
}
