<#
.SYNOPSIS
    CI/CD runner: deploys the query-travel-plans Lambda with Terraform, validates it, and prints query results.

.DESCRIPTION
    Stage 1: Pre-flight checks and AWS authentication
    Stage 2: Terraform init and validate
    Stage 3: Terraform plan (saved plan artifact only when changes exist)
    Stage 4: Terraform apply (skipped when infrastructure is up to date)
    Stage 5: Post-deployment validation and smoke tests, including the query results
    Stage 6: Summary

.PARAMETER TerraformDir
    Terraform configuration directory (default: Deployment\Terraform\LambdaFunctions).

.PARAMETER TestCity
    City used for the query smoke tests (default: Paris).

.PARAMETER Interactive
    Prompts for confirmation before applying. Without it the runner applies automatically (CI mode).

.PARAMETER SkipValidation
    Skips Stage 5.

.EXAMPLE
    .\deploy_validate_query-travel-plan.ps1

.EXAMPLE
    .\deploy_validate_query-travel-plan.ps1 -TestCity "Honolulu" -Interactive
#>

[CmdletBinding()]
param(
    [string]$TerraformDir = "$PSScriptRoot\..\..\Terraform\LambdaFunctions",
    [string]$TestCity = "Paris",
    [switch]$Interactive,
    [switch]$SkipValidation
)

# Exit codes are checked explicitly; "Stop" would turn native-command stderr into terminating errors on PS 5.1.
$ErrorActionPreference = "Continue"
$PipelineStart = Get-Date
$script:PlanFile = $null

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

function Stop-Pipeline {
    param([string]$Message)
    Write-Fail $Message
    if ($script:PlanFile -and (Test-Path $script:PlanFile)) { Remove-Item $script:PlanFile -Force -ErrorAction SilentlyContinue }
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

function Write-QueryResults {
    param([string]$Source, $Result, [string]$City)
    Write-Host ""
    Write-Host "  ---- Query Results ($Source) ----" -ForegroundColor Magenta
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
    Write-Host "  ----------------------------------------" -ForegroundColor Magenta
    Write-Host ""
}

$ResolvedTfDir = [System.IO.Path]::GetFullPath($TerraformDir)
if (-not (Test-Path $ResolvedTfDir)) {
    Stop-Pipeline "Terraform directory not found: $ResolvedTfDir"
}

Write-Host "**********************************************************" -ForegroundColor DarkCyan
Write-Host "        LAMBDA CI/CD AUTOMATION PIPELINE RUNNER" -ForegroundColor DarkCyan
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

    $script:PlanFile = Join-Path $env:TEMP "tfplan_lambda_$PID.binary"
    Write-Info "Running 'terraform plan -detailed-exitcode'..."
    # Exit codes: 0 = no changes (no plan file is written), 1 = error, 2 = changes pending
    terraform plan -input=false -no-color -detailed-exitcode "-out=$($script:PlanFile)"
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
    $FunctionName = $tfOut.function_name.value
    $FunctionArn  = $tfOut.function_arn.value
    $FunctionUrl  = $tfOut.function_url.value
}
finally {
    if ($script:PlanFile -and (Test-Path $script:PlanFile)) { Remove-Item $script:PlanFile -Force -ErrorAction SilentlyContinue }
    Pop-Location
}

if (-not $FunctionName) { Stop-Pipeline "Terraform output 'function_name' is missing." }

Write-Host ""
Write-Host "Deployed Resource Summary:" -ForegroundColor Green
Write-Host "  - Function Name : $FunctionName" -ForegroundColor White
Write-Host "  - Function ARN  : $FunctionArn" -ForegroundColor White
Write-Host "  - Function URL  : $FunctionUrl" -ForegroundColor White

# ---------------------------------------------------------------------------
# STAGE 5: Validation & smoke tests
# ---------------------------------------------------------------------------
Write-Stage "5/5" "Post-Deployment Validation & Smoke Tests"

$DirectCount = $null
$UrlCount = $null

if ($SkipValidation) {
    Write-Info "Validation skipped (-SkipValidation)."
}
else {
    # The CLI may have no default region; the function ARN always carries one.
    if (-not $env:AWS_REGION -and -not $env:AWS_DEFAULT_REGION) {
        $cfgRegion = Invoke-Native "aws" @("configure", "get", "region")
        if (-not $cfgRegion.Stdout -and $FunctionArn -match '^arn:aws[^:]*:lambda:([^:]+):') {
            $env:AWS_DEFAULT_REGION = $Matches[1]
            Write-Info "No AWS region configured; using '$($Matches[1])' from the function ARN."
        }
    }

    # 5.1 Function state
    Write-Info "Checking Lambda function state..."
    $fn = Invoke-Native "aws" @("lambda", "get-function", "--function-name", $FunctionName, "--output", "json")
    if ($fn.ExitCode -ne 0 -or -not $fn.Stdout) {
        Stop-Pipeline "Could not retrieve Lambda function '$FunctionName'.`n$($fn.Stderr)"
    }
    $cfg = ($fn.Stdout | ConvertFrom-Json).Configuration
    if ($cfg.State -eq "Active" -and $cfg.LastUpdateStatus -eq "Successful") {
        Write-Pass "State: $($cfg.State) | LastUpdateStatus: $($cfg.LastUpdateStatus) | Runtime: $($cfg.Runtime)"
    }
    else {
        Stop-Pipeline "Unexpected Lambda state: State=$($cfg.State), LastUpdateStatus=$($cfg.LastUpdateStatus)"
    }

    # 5.2 Direct invoke
    Write-Info "Direct invoke with TravelCity='$TestCity'..."
    $payload = @{ TravelCity = $TestCity } | ConvertTo-Json -Compress
    $payloadB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $respFile = Join-Path $env:TEMP "smoke_invoke_$PID.json"
    try {
        $inv = Invoke-Native "aws" @("lambda", "invoke", "--function-name", $FunctionName, "--payload", $payloadB64, $respFile)
        if ($inv.ExitCode -ne 0 -or -not (Test-Path $respFile)) {
            Stop-Pipeline "Direct invocation failed.`n$($inv.Stderr)"
        }
        $invJson = Get-Content $respFile -Raw | ConvertFrom-Json
    }
    finally {
        Remove-Item $respFile -Force -ErrorAction SilentlyContinue
    }

    if ($invJson.statusCode -ne 200) {
        Write-Host ($invJson | ConvertTo-Json -Depth 6) -ForegroundColor Red
        Stop-Pipeline "Direct invoke returned status $($invJson.statusCode)."
    }
    $directBody = $invJson.body | ConvertFrom-Json
    $DirectCount = $directBody.count
    Write-Pass "Direct invoke returned HTTP 200 (found $DirectCount plan(s) for '$TestCity')."
    Write-QueryResults "Direct Invoke" $directBody $TestCity

    # 5.3 Function URL
    if ($FunctionUrl) {
        Write-Info "Function URL smoke test..."
        $endpoint = "$FunctionUrl`?travelCity=$([uri]::EscapeDataString($TestCity))"
        try {
            $urlBody = Invoke-RestMethod -Uri $endpoint -Method Get -TimeoutSec 15
        }
        catch {
            Stop-Pipeline "Function URL request failed: $_"
        }
        if ($urlBody.travelCity -ne $TestCity -or $urlBody.count -lt 0) {
            Stop-Pipeline "Function URL returned an unexpected payload."
        }
        $UrlCount = $urlBody.count
        Write-Pass "Function URL returned HTTP 200 (found $UrlCount plan(s) for '$TestCity')."
        Write-QueryResults "Function URL" $urlBody $TestCity

        # 5.4 Negative test
        Write-Info "Negative test (missing TravelCity)..."
        $status = $null
        try {
            $r = Invoke-WebRequest -Uri $FunctionUrl -Method Get -UseBasicParsing -TimeoutSec 15
            $status = [int]$r.StatusCode
        }
        catch {
            if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
            else { Stop-Pipeline "Negative test request failed: $_" }
        }
        if ($status -eq 400) { Write-Pass "Service correctly returned HTTP 400 Bad Request." }
        else { Stop-Pipeline "Negative test expected HTTP 400 but received: $status" }
    }
    else {
        Write-Info "No function URL output; skipping HTTPS and negative tests."
    }
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
Write-Host " Function Name  : $FunctionName" -ForegroundColor White
Write-Host " Endpoint URL   : $FunctionUrl" -ForegroundColor White
if (-not $SkipValidation) {
    Write-Host " Query ($TestCity)  : direct=$DirectCount plan(s), url=$UrlCount plan(s)" -ForegroundColor White
}
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""

exit 0
