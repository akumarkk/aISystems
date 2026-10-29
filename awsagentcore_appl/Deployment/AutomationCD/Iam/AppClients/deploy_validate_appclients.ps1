<#
.SYNOPSIS
    CI/CD runner: deploys one Cognito app client per agent (custom <agent>_read / <agent>_write scopes) and validates them end to end.

.DESCRIPTION
    Stage 1: Pre-flight checks and AWS authentication
    Stage 2: Terraform init and validate
    Stage 3: Terraform plan (saved plan artifact only when changes exist)
    Stage 4: Terraform apply (skipped when infrastructure is up to date)
    Stage 5: Token tests per agent: the client-credentials token carries exactly the agent's own scopes,
             and a request for another agent's scope is rejected
    Secrets are never printed unless -ShowSecrets is passed.

.PARAMETER TerraformDir
    Terraform configuration directory (default: Deployment\Terraform\AppClients).

.PARAMETER UserPoolId
    Cognito user pool ID (default: us-east-1_igFfZFLDL).

.PARAMETER ResourceServerIdentifier
    Cognito resource server identifier that prefixes the custom scopes (default: the Terraform default, vacation-planner).

.PARAMETER Agents
    Agent names to create clients for. Defaults to the Terraform default (the agents of vac_planner\crew.jsonc).

.PARAMETER TokenDomain
    Cognito domain prefix (or full custom domain) for /oauth2/token. Default: the domain configured on the user pool, else env OIDC_AUTHORITY.

.PARAMETER ShowSecrets
    Prints the client secrets in the summary. Off by default.

.PARAMETER Interactive
    Prompts for confirmation before applying.

.PARAMETER SkipValidation
    Skips Stage 5.

.EXAMPLE
    .\deploy_validate_appclients.ps1

.EXAMPLE
    .\deploy_validate_appclients.ps1 -Interactive
#>

[CmdletBinding()]
param(
    [string]$TerraformDir = "$PSScriptRoot\..\..\..\Terraform\AppClients",
    [string]$UserPoolId = "us-east-1_igFfZFLDL",
    [string]$ResourceServerIdentifier,
    [string[]]$Agents,
    [string]$TokenDomain = $env:OIDC_AUTHORITY,
    [switch]$ShowSecrets,
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
            # PS 7 exposes the error body via ErrorDetails; PS 5.1 only via the response stream.
            $text = ""
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $text = $_.ErrorDetails.Message }
            else {
                try {
                    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
                    $text = $reader.ReadToEnd()
                } catch { }
            }
            return [pscustomobject]@{ Status = [int]$resp.StatusCode; Content = $text }
        }
        return [pscustomobject]@{ Status = 0; Content = $_.Exception.Message }
    }
}

# Client-credentials token request; returns HTTP status plus parsed JSON body.
function Get-ClientToken {
    param([string]$TokenUrl, [string]$ClientId, [string]$ClientSecret, [string]$Scope)
    $form = "grant_type=client_credentials&client_id=$([uri]::EscapeDataString($ClientId))&client_secret=$([uri]::EscapeDataString($ClientSecret))&scope=$([uri]::EscapeDataString($Scope))"
    $res = Invoke-Http -Uri $TokenUrl -Headers @{} -Body $form -ContentType "application/x-www-form-urlencoded"
    $json = $null
    try { $json = $res.Content | ConvertFrom-Json } catch { }
    [pscustomobject]@{ Status = $res.Status; Json = $json; Raw = $res.Content }
}

function ConvertFrom-JwtPayload {
    param([string]$Jwt)
    $part = $Jwt.Split(".")[1].Replace("-", "+").Replace("_", "/")
    switch ($part.Length % 4) { 2 { $part += "==" } 3 { $part += "=" } }
    [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part)) | ConvertFrom-Json
}

$ResolvedTfDir = [System.IO.Path]::GetFullPath($TerraformDir)
if (-not (Test-Path $ResolvedTfDir)) {
    Stop-Pipeline "Terraform directory not found: $ResolvedTfDir"
}

Write-Host "**********************************************************" -ForegroundColor DarkCyan
Write-Host "        APP CLIENTS CI/CD AUTOMATION PIPELINE RUNNER" -ForegroundColor DarkCyan
Write-Host " Start     : $PipelineStart" -ForegroundColor DarkCyan
Write-Host " Config    : $ResolvedTfDir" -ForegroundColor DarkCyan
Write-Host " User pool : $UserPoolId" -ForegroundColor DarkCyan
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

$PoolRegion = $UserPoolId.Split("_")[0]
Write-Info "Checking that user pool $UserPoolId exists..."
$pool = Invoke-Native "aws" @("cognito-idp", "describe-user-pool", "--user-pool-id", $UserPoolId, "--region", $PoolRegion, "--output", "json")
if ($pool.ExitCode -ne 0) { Stop-Pipeline "User pool not found or not accessible.`n$($pool.Stderr)" }
$poolInfo = ($pool.Stdout | ConvertFrom-Json).UserPool
Write-Pass "User pool: $($poolInfo.Name)"

# Terraform input variables are passed through a temporary .tfvars.json file (avoids Windows quoting problems).
$tfVars = @{ user_pool_id = $UserPoolId; aws_region = $PoolRegion }
if ($ResourceServerIdentifier) { $tfVars["resource_server_identifier"] = $ResourceServerIdentifier }
if ($Agents) { $tfVars["agents"] = @($Agents) }

$script:VarFile = Join-Path $env:TEMP "tfvars_appclients_$PID.tfvars.json"
($tfVars | ConvertTo-Json -Depth 5) | Set-Content -Path $script:VarFile -Encoding ASCII
$varArgs = @("-var-file=$($script:VarFile)")

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

    $script:PlanFile = Join-Path $env:TEMP "tfplan_appclients_$PID.binary"
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
        Write-Info "Applying saved plan..."
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
    $ClientIds     = $tfOut.client_ids.value
    $ClientSecrets = $tfOut.client_secrets.value
    $AgentScopes   = $tfOut.scopes.value
}
finally {
    Remove-TempFiles
    Pop-Location
}

if (-not $ClientIds) { Stop-Pipeline "Terraform output 'client_ids' is missing." }
$AgentNames = @($ClientIds.PSObject.Properties.Name)

Write-Host ""
Write-Host "Deployed Resource Summary:" -ForegroundColor Green
foreach ($agent in $AgentNames) {
    Write-Host "  - $agent" -ForegroundColor White
    Write-Host "      client_id : $($ClientIds.$agent)" -ForegroundColor Gray
    Write-Host "      scopes    : $(@($AgentScopes.$agent) -join ' ')" -ForegroundColor Gray
    if ($ShowSecrets) { Write-Host "      secret    : $($ClientSecrets.$agent)" -ForegroundColor Gray }
}
if (-not $ShowSecrets) {
    Write-Info "Secrets are hidden. Read them with 'terraform output -json client_secrets' in $ResolvedTfDir"
}

# ---------------------------------------------------------------------------
# STAGE 5: Token tests per agent
# ---------------------------------------------------------------------------
Write-Stage "5/5" "Post-Deployment Validation & Token Tests"

if ($SkipValidation) {
    Write-Info "Validation skipped (-SkipValidation)."
}
else {
    if (-not $TokenDomain) {
        if ($poolInfo.CustomDomain) { $TokenDomain = $poolInfo.CustomDomain }
        elseif ($poolInfo.Domain) { $TokenDomain = $poolInfo.Domain }
    }
    if (-not $TokenDomain) {
        Stop-Pipeline "The user pool has no domain, which /oauth2/token requires. Create one in Cognito (App integration > Domain) or pass -TokenDomain."
    }
    if ($TokenDomain -match "\.") { $tokenUrl = "https://$TokenDomain/oauth2/token" }
    else { $tokenUrl = "https://$TokenDomain.auth.$PoolRegion.amazoncognito.com/oauth2/token" }
    Write-Info "Token endpoint: $tokenUrl"

    $failures = 0
    for ($i = 0; $i -lt $AgentNames.Count; $i++) {
        $agent = $AgentNames[$i]
        $own = @($AgentScopes.$agent)
        Write-Host ""
        Write-Info "Agent '$agent'"

        # 5.1 Token with the agent's own scopes (retried: new clients can take a moment to propagate)
        $tok = $null
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $tok = Get-ClientToken -TokenUrl $tokenUrl -ClientId $ClientIds.$agent -ClientSecret $ClientSecrets.$agent -Scope ($own -join " ")
            if ($tok.Status -eq 200 -and $tok.Json.access_token) { break }
            if ($attempt -lt 3) { Write-Info "Token request not ready (HTTP $($tok.Status)); retrying in 5s..."; Start-Sleep -Seconds 5 }
        }
        if ($tok.Status -ne 200 -or -not $tok.Json.access_token) {
            Write-Fail "Token request failed (HTTP $($tok.Status)): $($tok.Raw)"
            $failures++
            continue
        }

        # 5.2 Token claims: right client and exactly the agent's scopes
        $claims = ConvertFrom-JwtPayload $tok.Json.access_token
        $granted = @(([string]$claims.scope).Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries))
        $missing = @($own | Where-Object { $granted -notcontains $_ })
        $extra = @($granted | Where-Object { $own -notcontains $_ })
        if ($claims.client_id -eq $ClientIds.$agent -and $missing.Count -eq 0 -and $extra.Count -eq 0) {
            Write-Pass "Token for client $($claims.client_id) carries: $($granted -join ' ')"
        }
        else {
            Write-Fail "Unexpected token claims. client_id=$($claims.client_id) scope='$($claims.scope)' missing=[$($missing -join ' ')] extra=[$($extra -join ' ')]"
            $failures++
        }

        # 5.3 Negative test: another agent's scope must be refused
        if ($AgentNames.Count -gt 1) {
            $other = $AgentNames[($i + 1) % $AgentNames.Count]
            $foreign = @($AgentScopes.$other)[0]
            $bad = Get-ClientToken -TokenUrl $tokenUrl -ClientId $ClientIds.$agent -ClientSecret $ClientSecrets.$agent -Scope $foreign
            Write-Host "  [DEBUG] Negative test response: HTTP $($bad.Status) $($bad.Raw)" -ForegroundColor DarkGray
            # Cognito answers invalid_grant when the scope exists but is not allowed for the client, invalid_scope when it is unknown.
            if ($bad.Status -eq 400 -and $bad.Json.error -in "invalid_scope", "invalid_grant") {
                Write-Pass "Request for '$foreign' (agent '$other') rejected with $($bad.Json.error)."
            }
            else {
                Write-Fail "Expected HTTP 400 (invalid_grant/invalid_scope) for '$foreign' but received HTTP $($bad.Status): $($bad.Raw)"
                $failures++
            }
        }
    }

    if ($failures -gt 0) { Stop-Pipeline "$failures validation check(s) failed." }
}

$elapsed = [int]((Get-Date) - $PipelineStart).TotalSeconds
Write-Host ""
Write-Host "**********************************************************" -ForegroundColor Green
Write-Host " PIPELINE COMPLETED SUCCESSFULLY in ${elapsed}s" -ForegroundColor Green
Write-Host "**********************************************************" -ForegroundColor Green
exit 0
