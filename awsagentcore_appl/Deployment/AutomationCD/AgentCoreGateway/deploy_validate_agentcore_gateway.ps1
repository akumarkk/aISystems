<#
.SYNOPSIS
    CI/CD runner: deploys the AgentCore Gateway (MCP, JWT auth) with the query_travel_plans Lambda tool and validates it end to end.

.DESCRIPTION
    Stage 1: Pre-flight checks and AWS authentication
    Stage 2: Terraform init and validate
    Stage 3: Terraform plan (saved plan artifact only when changes exist)
    Stage 4: Terraform apply (skipped when infrastructure is up to date)
    Stage 5: MCP smoke tests through the gateway: token, tools/list, tools/call (query results are printed)
    Stage 6: Summary

    The gateway authorizes callers with a Cognito JWT. The runner fetches a client-credentials token for the smoke tests.

.PARAMETER TerraformDir
    Terraform configuration directory (default: Deployment\Terraform\AgentCoreGateway).

.PARAMETER UserPoolId
    Cognito user pool ID (for example us-east-1_AbCdEf123). Used to build the OIDC discovery URL.
    Alternatives: -JwtDiscoveryUrl, or the TF_VAR_jwt_discovery_url environment variable.

.PARAMETER JwtDiscoveryUrl
    Full OIDC discovery URL; overrides -UserPoolId.

.PARAMETER AllowedClients
    Cognito app client IDs allowed to call the gateway. Defaults to the OIDC_CLIENTID_Local_Expert_City_Guide environment variable.

.PARAMETER ClientId
    App client ID used to fetch the smoke-test token (default: env OIDC_CLIENTID_Local_Expert_City_Guide).

.PARAMETER ClientSecret
    App client secret for the token request (default: env OIDC_CLIENTSECRET_Local_Expert_City_Guide).

.PARAMETER TokenDomain
    Cognito hosted-UI domain prefix for /oauth2/token (default: env OIDC_AUTHORITY).

.PARAMETER Scope
    Optional space-separated scopes for the token request. When omitted, Cognito grants all scopes allowed for the client.

.PARAMETER TestCity
    City used for the tools/call smoke test (default: Paris).

.PARAMETER Interactive
    Prompts for confirmation before applying.

.PARAMETER SkipValidation
    Skips Stage 5.

.EXAMPLE
    .\deploy_validate_agentcore_gateway.ps1 -UserPoolId us-east-1_AbCdEf123

.EXAMPLE
    .\deploy_validate_agentcore_gateway.ps1 -UserPoolId us-east-1_AbCdEf123 -TestCity Honolulu -Interactive
#>

[CmdletBinding()]
param(
    [string]$TerraformDir = "$PSScriptRoot\..\..\Terraform\AgentCoreGateway",
    [string]$UserPoolId,
    [string]$JwtDiscoveryUrl,
    [string[]]$AllowedClients,
    [string]$ClientId = $env:OIDC_CLIENTID_Local_Expert_City_Guide,
    [string]$ClientSecret = $env:OIDC_CLIENTSECRET_Local_Expert_City_Guide,
    [string]$TokenDomain = $env:OIDC_AUTHORITY,
    [string]$Scope,
    [string]$TestCity = "Paris",
    [switch]$Interactive,
    [switch]$SkipValidation
)

# Exit codes are checked explicitly; "Stop" would turn native-command stderr into terminating errors on PS 5.1.
$ErrorActionPreference = "Continue"
$PipelineStart = Get-Date
$script:PlanFile = $null
$script:VarFile = $null

function Write-Stage {
    param([string]$Num, [string]$Title)
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " [STAGE $Num] $Title" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
}
function Write-Pass { param([string]$m) Write-Host "  [PASS] $m" -ForegroundColor Green }
function Write-Fail { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Write-Info { param([string]$m) Write-Host "  [INFO] $m" -ForegroundColor Yellow }

function Remove-TempFiles {
    foreach ($f in $script:PlanFile, $script:VarFile) {
        if ($f -and (Test-Path $f)) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}

function Stop-Pipeline {
    param([string]$Message)
    Write-Fail $Message
    Remove-TempFiles
    exit 1
}

# Runs a native command, returning exit code, stdout and stderr separately.
function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments)
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $out = & $Exe @Arguments 2>$errFile
        $code = $LASTEXITCODE
        $err = (Get-Content $errFile -Raw -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            ExitCode = $code
            Stdout   = (@($out) -join "`n")
            Stderr   = $(if ($err) { $err.Trim() } else { "" })
        }
    }
    finally {
        Remove-Item $errFile -Force -ErrorAction SilentlyContinue
    }
}

# POSTs a body and returns status plus content, without throwing on HTTP errors (PS 5.1 compatible).
function Invoke-Http {
    param([string]$Uri, [hashtable]$Headers, [string]$Body, [string]$ContentType)
    try {
        $r = Invoke-WebRequest -Uri $Uri -Method Post -Headers $Headers -Body $Body -ContentType $ContentType -UseBasicParsing -TimeoutSec 60
        return [pscustomobject]@{ Status = [int]$r.StatusCode; Content = [string]$r.Content }
    }
    catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $text = ""
            try {
                $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $text = $reader.ReadToEnd()
            } catch { }
            return [pscustomobject]@{ Status = [int]$resp.StatusCode; Content = $text }
        }
        return [pscustomobject]@{ Status = 0; Content = $_.Exception.Message }
    }
}

function Invoke-Mcp {
    param([string]$Url, [string]$Token, [string]$Method, $Params, [int]$Id = 1)
    $req = @{ jsonrpc = "2.0"; id = $Id; method = $Method }
    if ($null -ne $Params) { $req.params = $Params }
    $res = Invoke-Http -Uri $Url -Headers @{ Authorization = "Bearer $Token"; Accept = "application/json" } `
        -Body ($req | ConvertTo-Json -Depth 20 -Compress) -ContentType "application/json"
    $parsed = $null
    if ($res.Content) { try { $parsed = $res.Content | ConvertFrom-Json } catch { } }
    [pscustomobject]@{ Status = $res.Status; Raw = $res.Content; Json = $parsed }
}

function Write-QueryResults {
    param($Result, [string]$City)
    Write-Host ""
    Write-Host "  ---- Query Results (AgentCore Gateway) ----" -ForegroundColor Magenta
    Write-Host "  TravelCity : $($Result.travelCity)" -ForegroundColor White
    Write-Host "  Plan count : $($Result.count)" -ForegroundColor White
    $i = 0
    foreach ($plan in @($Result.plans)) {
        $i++
        Write-Host "  Plan #$i" -ForegroundColor White
        foreach ($prop in $plan.PSObject.Properties) {
            $val = $prop.Value
            if ($val -is [System.Management.Automation.PSCustomObject] -or ($val -is [System.Collections.IEnumerable] -and $val -isnot [string])) {
                $val = $val | ConvertTo-Json -Depth 10 -Compress
            }
            Write-Host ("    {0,-22}: {1}" -f $prop.Name, $val) -ForegroundColor Gray
        }
    }
    if ($i -eq 0) { Write-Host "  (no plans found for '$City')" -ForegroundColor DarkYellow }
    Write-Host "  -------------------------------------------" -ForegroundColor Magenta
    Write-Host ""
}

$ResolvedTfDir = [System.IO.Path]::GetFullPath($TerraformDir)
if (-not (Test-Path $ResolvedTfDir)) {
    Stop-Pipeline "Terraform directory not found: $ResolvedTfDir"
}

Write-Host "**********************************************************" -ForegroundColor DarkCyan
Write-Host "      AGENTCORE GATEWAY CI/CD AUTOMATION PIPELINE RUNNER" -ForegroundColor DarkCyan
Write-Host " Start  : $PipelineStart" -ForegroundColor DarkCyan
Write-Host " Config : $ResolvedTfDir" -ForegroundColor DarkCyan
Write-Host "**********************************************************" -ForegroundColor DarkCyan

# ---------------------------------------------------------------------------
# STAGE 1: Pre-flight
# ---------------------------------------------------------------------------
Write-Stage "1/5" "Pre-flight & Authentication Verification"

foreach ($tool in "terraform", "aws") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Stop-Pipeline "$tool CLI is not installed or not in PATH."
    }
}
Write-Pass "Found Terraform: $((terraform version | Select-Object -First 1))"
Write-Pass "Found AWS CLI."

Write-Info "Validating AWS STS caller identity..."
$sts = Invoke-Native "aws" @("sts", "get-caller-identity", "--output", "json")
if ($sts.ExitCode -ne 0 -or -not $sts.Stdout) {
    Stop-Pipeline "AWS authentication failed. Ensure credentials or an 'aws login' session is active.`n$($sts.Stderr)"
}
$caller = $sts.Stdout | ConvertFrom-Json
Write-Pass "Authenticated as Account: $($caller.Account) ($($caller.Arn))"

# Terraform input variables are passed through a temporary .tfvars.json file (avoids Windows quoting problems).
$tfVars = @{}
if (-not $JwtDiscoveryUrl -and $UserPoolId) {
    $poolRegion = $UserPoolId.Split("_")[0]
    $JwtDiscoveryUrl = "https://cognito-idp.$poolRegion.amazonaws.com/$UserPoolId/.well-known/openid-configuration"
}
if ($JwtDiscoveryUrl) { $tfVars["jwt_discovery_url"] = $JwtDiscoveryUrl }
elseif (-not $env:TF_VAR_jwt_discovery_url -and -not (Test-Path (Join-Path $ResolvedTfDir "terraform.tfvars"))) {
    Stop-Pipeline "No JWT issuer configured. Pass -UserPoolId or -JwtDiscoveryUrl (or set TF_VAR_jwt_discovery_url)."
}

if (-not $AllowedClients -and $ClientId) { $AllowedClients = @($ClientId) }
if ($AllowedClients) { $tfVars["jwt_allowed_clients"] = @($AllowedClients) }

$script:VarFile = Join-Path $env:TEMP "tfvars_gateway_$PID.tfvars.json"
if ($tfVars.Count -gt 0) {
    ($tfVars | ConvertTo-Json -Depth 5) | Set-Content -Path $script:VarFile -Encoding ASCII
}
$varArgs = @()
if (Test-Path $script:VarFile) { $varArgs = @("-var-file=$($script:VarFile)") }

# ---------------------------------------------------------------------------
# STAGE 2: Init & validate
# ---------------------------------------------------------------------------
Write-Stage "2/5" "Terraform Initialization & Validation"

Push-Location $ResolvedTfDir
try {
    Write-Info "Running 'terraform init -input=false'..."
    $init = Invoke-Native "terraform" @("init", "-input=false", "-no-color")
    if ($init.ExitCode -ne 0) { Stop-Pipeline "terraform init failed.`n$($init.Stdout)`n$($init.Stderr)" }
    Write-Pass "Terraform initialized."

    Write-Info "Running 'terraform validate'..."
    $val = Invoke-Native "terraform" @("validate", "-json")
    $valJson = $val.Stdout | ConvertFrom-Json
    if ($val.ExitCode -ne 0 -or -not $valJson.valid) {
        Stop-Pipeline "Terraform configuration is invalid ($($valJson.error_count) error(s)).`n$($val.Stdout)"
    }
    Write-Pass "Configuration is valid."

    # -----------------------------------------------------------------------
    # STAGE 3: Plan
    # -----------------------------------------------------------------------
    Write-Stage "3/5" "Generating Execution Plan"

    $script:PlanFile = Join-Path $env:TEMP "tfplan_gateway_$PID.binary"
    Write-Info "Running 'terraform plan -detailed-exitcode'..."
    # Exit codes: 0 = no changes (no plan file is written), 1 = error, 2 = changes pending
    terraform plan -input=false -no-color -detailed-exitcode @varArgs "-out=$($script:PlanFile)"
    $planExit = $LASTEXITCODE
    if ($planExit -eq 1) { Stop-Pipeline "terraform plan failed." }

    $hasChanges = ($planExit -eq 2) -and (Test-Path $script:PlanFile)
    if ($hasChanges) { Write-Pass "Plan saved ($($script:PlanFile))." }
    else { Write-Pass "No infrastructure changes detected." }

    # -----------------------------------------------------------------------
    # STAGE 4: Apply
    # -----------------------------------------------------------------------
    Write-Stage "4/5" "Applying Infrastructure Changes"

    if ($hasChanges) {
        if ($Interactive) {
            $answer = Read-Host "  Apply the saved plan? (yes/no)"
            if ($answer -ne "yes") { Stop-Pipeline "Apply cancelled by user." }
        }
        Write-Info "Applying saved plan (gateway creation can take a few minutes)..."
        terraform apply -input=false -no-color "$($script:PlanFile)"
        if ($LASTEXITCODE -ne 0) { Stop-Pipeline "terraform apply failed." }
        Write-Pass "Terraform apply completed."
    }
    else {
        Write-Info "Skipping apply: infrastructure already matches configuration."
    }

    $outRaw = Invoke-Native "terraform" @("output", "-json")
    if ($outRaw.ExitCode -ne 0 -or -not $outRaw.Stdout) { Stop-Pipeline "Could not read Terraform outputs.`n$($outRaw.Stderr)" }
    $tfOut = $outRaw.Stdout | ConvertFrom-Json
    $GatewayId  = $tfOut.gateway_id.value
    $GatewayArn = $tfOut.gateway_arn.value
    $GatewayUrl = $tfOut.gateway_url.value
    $ToolName   = $tfOut.tool_name.value
}
finally {
    Remove-TempFiles
    Pop-Location
}

if (-not $GatewayUrl) { Stop-Pipeline "Terraform output 'gateway_url' is missing." }

Write-Host ""
Write-Host "Deployed Resource Summary:" -ForegroundColor Green
Write-Host "  - Gateway ID   : $GatewayId" -ForegroundColor White
Write-Host "  - Gateway ARN  : $GatewayArn" -ForegroundColor White
Write-Host "  - MCP URL      : $GatewayUrl" -ForegroundColor White
Write-Host "  - Tool name    : $ToolName" -ForegroundColor White

# ---------------------------------------------------------------------------
# STAGE 5: MCP smoke tests through the gateway
# ---------------------------------------------------------------------------
Write-Stage "5/5" "Post-Deployment Validation & MCP Smoke Tests"

$QueryCount = $null

if ($SkipValidation) {
    Write-Info "Validation skipped (-SkipValidation)."
}
else {
    # 5.1 Access token (Cognito client credentials)
    if (-not $ClientId -or -not $ClientSecret -or -not $TokenDomain) {
        Stop-Pipeline "Token settings missing. Set -ClientId, -ClientSecret and -TokenDomain (or the OIDC_CLIENTID_Local_Expert_City_Guide, OIDC_CLIENTSECRET_Local_Expert_City_Guide and OIDC_AUTHORITY environment variables)."
    }
    $tokenRegion = "us-east-1"
    if ($UserPoolId) { $tokenRegion = $UserPoolId.Split("_")[0] }
    $tokenUrl = "https://$TokenDomain.auth.$tokenRegion.amazoncognito.com/oauth2/token"

    Write-Info "Requesting access token from $tokenUrl ..."
    $form = "grant_type=client_credentials&client_id=$([uri]::EscapeDataString($ClientId))&client_secret=$([uri]::EscapeDataString($ClientSecret))"
    if ($Scope) { $form += "&scope=$([uri]::EscapeDataString($Scope))" }
    $tok = Invoke-Http -Uri $tokenUrl -Headers @{} -Body $form -ContentType "application/x-www-form-urlencoded"
    $tokJson = $null
    try { $tokJson = $tok.Content | ConvertFrom-Json } catch { }
    if ($tok.Status -ne 200 -or -not $tokJson.access_token) {
        Stop-Pipeline "Token request failed (HTTP $($tok.Status)): $($tok.Content)"
    }
    $AccessToken = $tokJson.access_token
    Write-Pass "Access token acquired (expires in $($tokJson.expires_in)s)."

    # 5.2 Unauthenticated request must be rejected
    Write-Info "Negative test: request without a token..."
    $anon = Invoke-Http -Uri $GatewayUrl -Headers @{} -Body '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' -ContentType "application/json"
    if ($anon.Status -in 401, 403) { Write-Pass "Gateway rejected the unauthenticated request (HTTP $($anon.Status))." }
    else { Stop-Pipeline "Expected HTTP 401/403 without a token but received: $($anon.Status)" }

    # 5.3 tools/list (retried: IAM and target propagation can lag right after creation)
    Write-Info "MCP tools/list..."
    $tools = $null
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $list = Invoke-Mcp -Url $GatewayUrl -Token $AccessToken -Method "tools/list" -Params $null -Id 1
        if ($list.Status -eq 200 -and $list.Json.result.tools) {
            $tools = @($list.Json.result.tools)
            if ($tools.name -contains $ToolName) { break }
        }
        Write-Info "Tool not visible yet (attempt $attempt/6, HTTP $($list.Status)); retrying in 10s..."
        Start-Sleep -Seconds 10
    }
    if (-not $tools -or -not ($tools.name -contains $ToolName)) {
        Stop-Pipeline "Tool '$ToolName' not found via tools/list.`n$($list.Raw)"
    }
    Write-Pass "tools/list returned $($tools.Count) tool(s): $(($tools.name) -join ', ')"

    # 5.4 tools/call
    Write-Info "MCP tools/call $ToolName with TravelCity='$TestCity'..."
    $call = Invoke-Mcp -Url $GatewayUrl -Token $AccessToken -Method "tools/call" -Id 2 `
        -Params @{ name = $ToolName; arguments = @{ TravelCity = $TestCity } }
    if ($call.Status -ne 200 -or $call.Json.error -or $call.Json.result.isError) {
        Stop-Pipeline "tools/call failed (HTTP $($call.Status)).`n$($call.Raw)"
    }

    # The Lambda's {statusCode, body} response arrives as JSON text in result.content[0].text
    $payload = $null
    try {
        if ($call.Json.result.structuredContent) { $payload = $call.Json.result.structuredContent }
        else { $payload = $call.Json.result.content[0].text | ConvertFrom-Json }
    }
    catch { Stop-Pipeline "Could not parse tools/call result.`n$($call.Raw)" }

    if ($payload.statusCode -ne 200) { Stop-Pipeline "Lambda returned status $($payload.statusCode).`n$($call.Raw)" }
    $queryResult = $payload.body | ConvertFrom-Json
    if ($queryResult.travelCity -ne $TestCity) { Stop-Pipeline "Unexpected travelCity in response: $($queryResult.travelCity)" }
    $QueryCount = $queryResult.count
    Write-Pass "tools/call succeeded (found $QueryCount plan(s) for '$TestCity')."
    Write-QueryResults $queryResult $TestCity

    # 5.5 Negative tool call: missing required argument
    Write-Info "Negative test: tools/call without TravelCity..."
    $bad = Invoke-Mcp -Url $GatewayUrl -Token $AccessToken -Method "tools/call" -Id 3 `
        -Params @{ name = $ToolName; arguments = @{} }
    $rejected = ($bad.Json.error) -or ($bad.Json.result.isError) -or ($bad.Status -ge 400)
    if (-not $rejected) {
        try {
            $badPayload = $bad.Json.result.content[0].text | ConvertFrom-Json
            $rejected = ($badPayload.statusCode -eq 400)
        } catch { }
    }
    if ($rejected) { Write-Pass "Missing TravelCity was rejected as expected." }
    else { Stop-Pipeline "Missing TravelCity was not rejected.`n$($bad.Raw)" }
}

# ---------------------------------------------------------------------------
# STAGE 6: Summary
# ---------------------------------------------------------------------------
$duration = (Get-Date) - $PipelineStart
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "                PIPELINE EXECUTION SUMMARY" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Status         : SUCCESS (ALL STAGES PASSED)" -ForegroundColor Green
Write-Host " Duration       : $($duration.TotalSeconds.ToString('F1')) seconds" -ForegroundColor White
Write-Host " Gateway ID     : $GatewayId" -ForegroundColor White
Write-Host " MCP URL        : $GatewayUrl" -ForegroundColor White
Write-Host " Tool           : $ToolName" -ForegroundColor White
if (-not $SkipValidation) {
    Write-Host " Query ($TestCity)  : $QueryCount plan(s)" -ForegroundColor White
}
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""

exit 0
