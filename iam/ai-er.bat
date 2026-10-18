aws iam create-user --user-name ai-engr

# 2. Attach AI Policies (Bedrock & SageMaker)
aws iam attach-user-policy --user-name ai-engr --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess
aws iam attach-user-policy --user-name ai-engr --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess

# 3. Attach App Deployment Policies (Lambda, ECS, S3, API Gateway, CloudFormation)
aws iam attach-user-policy --user-name ai-engr --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
aws iam attach-user-policy --user-name ai-engr --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess
aws iam attach-user-policy --user-name ai-engr --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-user-policy --user-name ai-engr --policy-arn arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator
aws iam attach-user-policy --user-name ai-engr --policy-arn arn:aws:iam::aws:policy/AWSCloudFormationFullAccess

# 4. Generate Access Keys (Save the output JSON securely!)
aws iam create-access-key --user-name ai-engr

aws sts get-caller-identity --profile ai-deployer