##### deploy policy

```

aws iam create-policy --policy-name vac-planner-deploy --policy-document file://deploy_policy.json

aws iam attach-user-policy --user-name ai-engr --policy-arn arn:aws:iam::837873138218:policy/vac-planner-deploy

aws iam list-attached-user-policies --user-name ai-engr


// update
aws iam create-policy-version --policy-arn arn:aws:iam::837873138218:policy/vac-planner-deploy --policy-document file://deploy_policy.json --set-as-default
```