###### Deploy role

```

aws iam create-role --role-name AgentCoreRuntime-vac-planner `
  --assume-role-policy-document file://iam/trust-policy.json

aws iam put-role-policy --role-name AgentCoreRuntime-vac-planner `
  --policy-name runtime-access --policy-document file://iam/permissions-policy.json

# confirm the role exists and get its ARN
aws iam get-role --role-name AgentCoreRuntime-vac-planner --query Role.Arn --output text


# update role
aws iam update-assume-role-policy --role-name AgentCoreRuntime-vac-planner --policy-document file://iam/trust-policy.json; if ($?) { aws iam get-role --role-name AgentCoreRuntime-vac-planner --query "Role.AssumeRolePolicyDocument" --output json }

```