#https://6y93gsmga0.execute-api.us-east-1.amazonaws.com/prod/vacation_planner_v1
curl.exe -i --aws-sigv4 "aws:amz:us-east-1:lambda" --user "$env:AWS_ACCESS_KEY_ID`:$env:AWS_SECRET_ACCESS_KEY" https://2qjdfqpfzbt25f6texrsemwu2m0gigfa.lambda-url.us-east-1.on.aws/ping

curl.exe -i --aws-sigv4 "aws:amz:us-east-1:lambda" --user "$env:AWS_ACCESS_KEY_ID`:$env:AWS_SECRET_ACCESS_KEY" https://6y93gsmga0.execute-api.us-east-1.amazonaws.com/prod/vacation_planner_v1/ping
