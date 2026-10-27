# IAM Role & Policy Setup for Bedrock AgentCore & Lambda

All trust and permission policies are maintained declaratively in:
- [trust-policy.json](trust-policy.json): AssumeRole trust relationship for `lambda.amazonaws.com` and `bedrock-agentcore.amazonaws.com`.
- [permissions-policy.json](permissions-policy.json): Unified permissions for ECR image pull, AgentCore Runtime logging, Lambda execution logging, AgentCore Runtime invocation, X-Ray tracing, CloudWatch metrics, and Secrets Manager API key retrieval.

The role must be created and assigned **separately before deployment** (before running `deployment.ps1` or `Deployment/lambdaDeployment.ps1`).

---

## Option 1: Automated Setup via PowerShell

Run the setup script directly from the `iam` folder:

```powershell
cd iam
.\deploy_role.ps1
```

This script will:
1. Create the `AgentCoreRuntime-vac-planner` role if it does not exist (or update the trust policy if it does).
2. Attach/update the `runtime-access` inline policy with [permissions-policy.json](permissions-policy.json).
3. Clean up any obsolete inline policies (such as `LambdaAgentCoreInvokeAccess`).
4. Output the verified role ARN.

---

## Option 2: Manual Setup via AWS CLI

### 1. Create Role with Trust Policy
```powershell
aws iam create-role `
  --role-name AgentCoreRuntime-vac-planner `
  --assume-role-policy-document file://iam/trust-policy.json
```

### 2. Update Trust Policy (if role already exists)
```powershell
aws iam update-assume-role-policy `
  --role-name AgentCoreRuntime-vac-planner `
  --policy-document file://iam/trust-policy.json
```

### 3. Assign Permissions Policy
```powershell
aws iam put-role-policy `
  --role-name AgentCoreRuntime-vac-planner `
  --policy-name runtime-access `
  --policy-document file://iam/permissions-policy.json
```

### 4. Verify Role ARN & Policies
```powershell
# Get role ARN
aws iam get-role --role-name AgentCoreRuntime-vac-planner --query Role.Arn --output text

# List attached inline policies
aws iam list-role-policies --role-name AgentCoreRuntime-vac-planner --output json
```
