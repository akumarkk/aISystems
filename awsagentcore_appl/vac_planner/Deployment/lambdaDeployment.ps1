<#
.SYNOPSIS
    Deploys an AWS Lambda function that invokes the Bedrock AgentCore Runtime (vac_planner).

.DESCRIPTION
    This script automates:
    1. Verification of AWS credentials and CLI prerequisites.
    2. Verification of the pre-configured IAM execution role (created/managed via iam/).
    3. Packaging lambda_function.py with the latest boto3/botocore dependencies (supporting bedrock-agentcore).
    4. Creating or updating the Lambda function (900s timeout for CrewAI multi-agent execution).
    5. (Optional) Configuring an HTTPS Lambda Function URL.
    6. Testing the deployment with a health check ping or full vacation planning run.

.PARAMETER Region
    AWS Region for the deployment (default: us-east-1).

.PARAMETER FunctionName
    Name of the Lambda function (default: vac-planner-agentcore-invoker).

.PARAMETER RuntimeArn
    The ARN of the Bedrock AgentCore Runtime to invoke.

.PARAMETER Qualifier
    AgentCore endpoint qualifier (default: DEFAULT).

.PARAMETER RoleName
    IAM role name for the Lambda function (default: AgentCoreRuntime-vac-planner).

.PARAMETER Timeout
    Function timeout in seconds (default: 900 / 15 minutes to allow CrewAI runs).

.PARAMETER MemorySize
    Function memory in MB (default: 512).

.PARAMETER PythonRuntime
    Python runtime for Lambda (default: python3.12).

.PARAMETER BundleDependencies
    Bundles the latest boto3/botocore into the zip to ensure bedrock-agentcore client support (default: $true).

.PARAMETER CreateFunctionUrl
    Configures a public HTTPS Function URL for direct HTTP invocation (default: $false).

.PARAMETER TestPing
    Runs an immediate health-check ping test against the deployed Lambda (default: $true).

.PARAMETER TestFull
    Runs a full vacation planning trip request test against the deployed Lambda (takes 1-3 minutes).

.EXAMPLE
    .\lambdaDeployment.ps1

.EXAMPLE
    .\lambdaDeployment.ps1 -CreateFunctionUrl -TestPing
#>

[CmdletBinding()]
param(
    [string]$Region = "us-east-1",
    [string]$FunctionName = "vac-planner-agentcore-invoker",
    [string]$RuntimeArn = "arn:aws:bedrock-agentcore:us-east-1:837873138218:runtime/vac_planner-4M3CfW8SGa",
    [string]$Qualifier = "DEFAULT",
    [string]$RoleName = "AgentCoreRuntime-vac-planner",
    [int]$Timeout = 900,
    [int]$MemorySize = 512,
    [string]$PythonRuntime = "python3.12",
    [bool]$BundleDependencies = $true,
    [switch]$CreateFunctionUrl,
    [bool]$TestPing = $true,
    [switch]$TestFull
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Bedrock AgentCore Lambda Deployment: $FunctionName" -ForegroundColor Cyan
Write-Host " Target Runtime ARN: $RuntimeArn" -ForegroundColor Cyan
Write-Host " Region: $Region" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Check AWS Credentials & Prerequisites
# -----------------------------------------------------------------------------
Write-Host "`n[1/6] Verifying AWS CLI and active credentials..." -ForegroundColor Yellow
$callerIdentity = aws sts get-caller-identity --output json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $callerIdentity) {
    Write-Error @"
AWS authentication failed or session has expired.
Please run 'aws login' or configure your credentials ('aws configure'), then rerun this script.
"@
    exit 1
}

$identityObj = $callerIdentity | ConvertFrom-Json
$ACCOUNT = $identityObj.Account
Write-Host "Authenticated as Account: $ACCOUNT (ARN: $($identityObj.Arn))" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 2. Setup Working Directories
# -----------------------------------------------------------------------------
$SCRIPT_DIR = $PSScriptRoot
if (-not $SCRIPT_DIR) { $SCRIPT_DIR = Get-Location }
$LAMBDA_CODE_FILE = Join-Path $SCRIPT_DIR "lambda_function.py"

if (-not (Test-Path $LAMBDA_CODE_FILE)) {
    Write-Error "Could not find $LAMBDA_CODE_FILE. Ensure lambda_function.py is in the Deployment folder."
    exit 1
}

$TMP_DIR = Join-Path $env:TEMP "vac_planner_lambda_deploy"
$BUILD_DIR = Join-Path $TMP_DIR "pkg"
$ZIP_PATH = Join-Path $TMP_DIR "lambda_package.zip"

if (Test-Path $TMP_DIR) {
    Remove-Item -Path $TMP_DIR -Recurse -Force | Out-Null
}
New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8JsonFile([string]$path, [object]$data) {
    $json = if ($data -is [string]) { $data } else { $data | ConvertTo-Json -Depth 10 -Compress }
    [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
    return $path
}

# -----------------------------------------------------------------------------
# 3. Verify IAM Execution Role
# -----------------------------------------------------------------------------
Write-Host "`n[2/6] Verifying IAM Execution Role: $RoleName..." -ForegroundColor Yellow

$roleArn = $null
$origEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$roleCheck = aws iam get-role --role-name $RoleName --query "Role.Arn" --output text 2>&1
$roleExitCode = $LASTEXITCODE
$ErrorActionPreference = $origEAP

if ($roleExitCode -ne 0 -or -not $roleCheck -or $roleCheck -like "*NoSuchEntity*") {
    Write-Error @"
IAM execution role '$RoleName' was not found.
Please ensure the role and its policies are created before running deployment:
  - Trust policy:       iam/trust-policy.json
  - Permissions policy: iam/permissions-policy.json
See iam/deploy_role.md or run iam/deploy_role.ps1 to create/update the role.
"@
    exit 1
}

$roleArn = $roleCheck.Trim()
Write-Host "Using verified IAM role: $roleArn" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 4. Package Lambda Code & Dependencies
# -----------------------------------------------------------------------------
Write-Host "`n[3/6] Packaging Lambda function code..." -ForegroundColor Yellow

# Copy handler code
Copy-Item -Path $LAMBDA_CODE_FILE -Destination (Join-Path $BUILD_DIR "lambda_function.py") -Force

if ($BundleDependencies) {
    Write-Host "Bundling latest boto3 & botocore to guarantee 'bedrock-agentcore' service model support..."
    & python -m pip install boto3 botocore --target $BUILD_DIR --upgrade --no-user --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "pip install encountered a warning or error. Proceeding with packaging..."
    } else {
        Write-Host "Dependencies successfully installed into build directory." -ForegroundColor Green
    }
}

# Use python's standard zipfile for fast and reliable cross-platform packaging
$zipScript = @"
import sys, os, zipfile
build_dir = sys.argv[1]
zip_path = sys.argv[2]
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(build_dir):
        for f in files:
            full_path = os.path.join(root, f)
            arc_name = os.path.relpath(full_path, build_dir)
            z.write(full_path, arc_name)
print(f'Archive created: {os.path.getsize(zip_path)} bytes')
"@

$zipScriptPath = Join-Path $TMP_DIR "create_zip.py"
[System.IO.File]::WriteAllText($zipScriptPath, $zipScript, [System.Text.Encoding]::UTF8)

& python $zipScriptPath $BUILD_DIR $ZIP_PATH
if (-not (Test-Path $ZIP_PATH)) {
    Write-Error "Failed to generate $ZIP_PATH"
    exit 1
}
$zipSizeMb = [Math]::Round((Get-Item $ZIP_PATH).Length / 1MB, 2)
Write-Host "Deployment zip ready: $ZIP_PATH ($zipSizeMb MB)" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 5. Create or Update Lambda Function
# -----------------------------------------------------------------------------
Write-Host "`n[4/6] Deploying Lambda function: $FunctionName..." -ForegroundColor Yellow

$envVars = "Variables={AGENT_RUNTIME_ARN=$RuntimeArn,QUALIFIER=$Qualifier,TARGET_REGION=$Region}"

# In PowerShell with $ErrorActionPreference = "Stop", native CLI output on stderr (e.g. ResourceNotFoundException)
# throws a NativeCommandError. Temporarily use Continue and capture output.
$origEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$funcCheckRaw = aws lambda get-function --function-name $FunctionName --region $Region 2>&1
$funcExitCode = $LASTEXITCODE
$ErrorActionPreference = $origEAP

if ($funcExitCode -eq 0) {
    Write-Host "Updating code for existing Lambda function..."
    aws lambda update-function-code `
        --function-name $FunctionName `
        --zip-file "fileb://$ZIP_PATH" `
        --region $Region | Out-Null

    Write-Host "Waiting for function code update..."
    aws lambda wait function-updated --function-name $FunctionName --region $Region

    Write-Host "Updating function configuration (Timeout=$Timeout, Memory=$MemorySize)..."
    aws lambda update-function-configuration `
        --function-name $FunctionName `
        --role $roleArn `
        --timeout $Timeout `
        --memory-size $MemorySize `
        --environment $envVars `
        --region $Region | Out-Null
} else {
    Write-Host "Function does not exist yet. Creating new Lambda function $FunctionName..."
    aws lambda create-function `
        --function-name $FunctionName `
        --runtime $PythonRuntime `
        --role $roleArn `
        --handler "lambda_function.lambda_handler" `
        --zip-file "fileb://$ZIP_PATH" `
        --timeout $Timeout `
        --memory-size $MemorySize `
        --environment $envVars `
        --region $Region
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create Lambda function $FunctionName."
        exit 1
    }

    Write-Host "Waiting for function to become active..."
    # Older CLI versions use function-active, newer use function-active-v2
    $origEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    aws lambda wait function-active-v2 --function-name $FunctionName --region $Region 2>$null
    if ($LASTEXITCODE -ne 0) {
        aws lambda wait function-active --function-name $FunctionName --region $Region 2>$null
    }
    $ErrorActionPreference = $origEAP
}

Write-Host "Lambda function $FunctionName deployed successfully!" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 6. Optional: Lambda Function URL
# -----------------------------------------------------------------------------
if ($CreateFunctionUrl) {
    Write-Host "`n[5/6] Configuring Lambda Function URL..." -ForegroundColor Yellow
    $origEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $urlConfig = aws lambda get-function-url-config --function-name $FunctionName --region $Region 2>&1
    $urlExitCode = $LASTEXITCODE
    $ErrorActionPreference = $origEAP

    if ($urlExitCode -ne 0) {
        $corsConfig = @{
            AllowOrigins = @("*")
            AllowMethods = @("POST", "GET")
            AllowHeaders = @("content-type")
        }
        $corsFile = Join-Path $TMP_DIR "cors-config.json"
        Write-Utf8JsonFile $corsFile $corsConfig | Out-Null

        $origEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $createUrlOut = aws lambda create-function-url-config `
            --function-name $FunctionName `
            --auth-type NONE `
            --cors "file://$corsFile" `
            --region $Region 2>&1
        $createUrlExit = $LASTEXITCODE
        $ErrorActionPreference = $origEAP

        if ($createUrlExit -ne 0) {
            Write-Warning "Failed to create Function URL: $createUrlOut"
        } else {
            $urlConfig = $createUrlOut
            # Grant public invoke permission
            $origEAP = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            aws lambda add-permission `
                --function-name $FunctionName `
                --statement-id "FunctionURLAllowPublicAccess" `
                --action "lambda:InvokeFunctionUrl" `
                --principal "*" `
                --function-url-auth-type NONE `
                --region $Region 2>&1 | Out-Null
            $ErrorActionPreference = $origEAP
        }
    }
    if ($urlConfig -and $urlConfig -notlike "*ERROR*") {
        try {
            $funcUrl = ($urlConfig | ConvertFrom-Json).FunctionUrl
            Write-Host "Function URL created: $funcUrl" -ForegroundColor Cyan
        } catch {
            Write-Warning "Could not parse Function URL output: $urlConfig"
        }
    }
} else {
    Write-Host "`n[5/6] Skipping Function URL (pass -CreateFunctionUrl to enable)." -ForegroundColor DarkGray
}

# -----------------------------------------------------------------------------
# 7. Smoke Testing
# -----------------------------------------------------------------------------
Write-Host "`n[6/6] Smoke Testing..." -ForegroundColor Yellow

if ($TestPing) {
    Write-Host "Running health check ping test..." -ForegroundColor Yellow
    $pingEventFile = Join-Path $TMP_DIR "ping_request.json"
    Write-Utf8JsonFile $pingEventFile '{"path":"/ping"}' | Out-Null
    $pingResponseFile = Join-Path $TMP_DIR "ping_response.json"

    aws lambda invoke `
        --function-name $FunctionName `
        --cli-binary-format raw-in-base64-out `
        --payload "fileb://$pingEventFile" `
        --region $Region `
        $pingResponseFile | Out-Null

    if (Test-Path $pingResponseFile) {
        $pingOut = Get-Content $pingResponseFile -Raw
        Write-Host "Ping response received:" -ForegroundColor Green
        Write-Host $pingOut
    }
}

if ($TestFull) {
    Write-Host "`nRunning full vacation planner crew invocation test (this may take 1-3 minutes)..." -ForegroundColor Yellow
    $vacEventFile = Join-Path $SCRIPT_DIR "test-event-vacation.json"
    $fullResponseFile = Join-Path $TMP_DIR "full_response.json"

    if (Test-Path $vacEventFile) {
        aws lambda invoke `
            --function-name $FunctionName `
            --cli-binary-format raw-in-base64-out `
            --payload "fileb://$vacEventFile" `
            --cli-read-timeout 950 `
            --region $Region `
            $fullResponseFile

        if (Test-Path $fullResponseFile) {
            $fullOut = Get-Content $fullResponseFile -Raw
            Write-Host "Vacation Planner response received:" -ForegroundColor Green
            Write-Host $fullOut
        }
    } else {
        Write-Warning "Could not find $vacEventFile"
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " Deployment Complete!" -ForegroundColor Cyan
Write-Host " Function: $FunctionName" -ForegroundColor Cyan
Write-Host " Target Runtime ARN: $RuntimeArn" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
