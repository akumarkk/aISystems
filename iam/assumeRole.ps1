$p = aws iam get-role --role-name bedrock-loggroup-v1 --query Role.AssumeRolePolicyDocument | ConvertFrom-Json
$p.Statement += [pscustomobject]@{
  Sid="AllowAiEngrAssume"; Effect="Allow"
  Principal=[pscustomobject]@{AWS="arn:aws:iam::837873138218:user/ai-engr"}
  Action="sts:AssumeRole"
}
$p | ConvertTo-Json -Depth 10 | Set-Content trust.json -Encoding ascii
Get-Content trust.json

aws iam update-assume-role-policy --role-name bedrock-loggroup-v1 --policy-document file://trust.json