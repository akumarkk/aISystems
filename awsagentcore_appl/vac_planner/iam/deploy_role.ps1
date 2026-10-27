<#
.SYNOPSIS
    Creates or updates the IAM execution role and assigns policies for Bedrock AgentCore & Lambda.

.DESCRIPTION
    Applies:
    - Trust policy:       iam/trust-policy.json (for lambda.amazonaws.com and bedrock-agentcore.amazonaws.com)
    - Permissions policy: iam/permissions-policy.json (inline policy 'runtime-access')

.PARAMETER RoleName
    IAM role name (default: AgentCoreRuntime-vac-planner).

.PARAMETER PolicyName
    Inline policy name to put (default: runtime-access).

.EXAMPLE
    .\deploy_role.ps1

.EXAMPLE
    .\deploy_role.ps1 -RoleName "AgentCoreRuntime-vac-planner"
#>

[CmdletBinding()]
param(
    [string]$RoleName = "AgentCoreRuntime-vac-planner",
    [string]$PolicyName = "runtime-access"
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = $PSScriptRoot
if (-not $SCRIPT_DIR) { $SCRIPT_DIR = Get-Location }

$TRUST_POLICY_PATH = Join-Path $SCRIPT_DIR "trust-policy.json"
$PERM_POLICY_PATH  = Join-Path $SCRIPT_DIR "permissions-policy.json"

if (-not (Test-Path $TRUST_POLICY_PATH)) {
    Write-Error "Trust policy file not found: $TRUST_POLICY_PATH"
    exit 1
}
if (-not (Test-Path $PERM_POLICY_PATH)) {
    Write-Error "Permissions policy file not found: $PERM_POLICY_PATH"
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " IAM Role Management: $RoleName" -ForegroundColor Cyan
Write-Host " Trust Policy:       $TRUST_POLICY_PATH" -ForegroundColor Cyan
Write-Host " Permissions Policy: $PERM_POLICY_PATH" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check if role exists
Write-Host "`nChecking if role '$RoleName' exists..." -ForegroundColor Yellow
$origEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$roleArn = aws iam get-role --role-name $RoleName --query "Role.Arn" --output text 2>$null
$roleExitCode = $LASTEXITCODE
$ErrorActionPreference = $origEAP

if ($roleExitCode -ne 0 -or -not $roleArn -or $roleArn -like "*NoSuchEntity*") {
    Write-Host "Role '$RoleName' does not exist. Creating role..." -ForegroundColor Yellow
    aws iam create-role --role-name $RoleName `
        --assume-role-policy-document "file://$TRUST_POLICY_PATH" `
        --output json
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create IAM role $RoleName."
        exit 1
    }
    Write-Host "Role '$RoleName' successfully created." -ForegroundColor Green
} else {
    Write-Host "Role '$RoleName' exists ($roleArn). Updating trust policy..." -ForegroundColor Yellow
    aws iam update-assume-role-policy --role-name $RoleName `
        --policy-document "file://$TRUST_POLICY_PATH"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to update assume role trust policy for $RoleName."
        exit 1
    }
    Write-Host "Trust policy updated successfully." -ForegroundColor Green
}

# 2. Assign / Put permissions policy
Write-Host "`nAssigning permissions policy '$PolicyName' to role '$RoleName'..." -ForegroundColor Yellow
aws iam put-role-policy --role-name $RoleName `
    --policy-name $PolicyName `
    --policy-document "file://$PERM_POLICY_PATH"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to put policy '$PolicyName' on role $RoleName."
    exit 1
}
Write-Host "Permissions policy '$PolicyName' assigned successfully." -ForegroundColor Green

# 3. Clean up any obsolete temporary inline policies if they exist (e.g. LambdaAgentCoreInvokeAccess)
$existingPoliciesJson = aws iam list-role-policies --role-name $RoleName --query "PolicyNames" --output json 2>$null
if ($existingPoliciesJson) {
    $existingPolicies = $existingPoliciesJson | ConvertFrom-Json
    if ($existingPolicies -and ($existingPolicies -contains "LambdaAgentCoreInvokeAccess")) {
        Write-Host "`nRemoving obsolete inline policy 'LambdaAgentCoreInvokeAccess' (consolidated into '$PolicyName')..." -ForegroundColor Yellow
        aws iam delete-role-policy --role-name $RoleName --policy-name "LambdaAgentCoreInvokeAccess" 2>$null | Out-Null
        Write-Host "Cleaned up obsolete policy." -ForegroundColor Green
    }
}

# 4. Display confirmation
$finalArn = aws iam get-role --role-name $RoleName --query "Role.Arn" --output text
Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " IAM Role Ready: $finalArn" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
