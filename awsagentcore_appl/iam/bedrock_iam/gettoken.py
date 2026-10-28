import boto3

sts_client = boto3.client('sts')

response = sts_client.assume_role(
    RoleArn='arn:aws:iam::837873138218:role/service-role/bedrock-loggroup-v1',
    RoleSessionName='NativeAgentSession'
)

credentials = response['Credentials']
access_key = credentials['AccessKeyId']
secret_key = credentials['SecretAccessKey']
session_token = credentials['SessionToken']

print("Access Key:", access_key)
print("Secret Key:", secret_key)
print("Session Token:", session_token)