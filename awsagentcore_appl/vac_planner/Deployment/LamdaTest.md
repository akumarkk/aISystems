##### test lambda

```
aws configure export-credentials --format env-no-export | ForEach-Object { $k, $v = $_ -split '=', 2; Set-Item "env:$k" $v }

curl.exe -i --aws-sigv4 "aws:amz:us-east-1:lambda" --user "$env:AWS_ACCESS_KEY_ID`:$env:AWS_SECRET_ACCESS_KEY" https://2qjdfqpfzbt25f6texrsemwu2m0gigfa.lambda-url.us-east-1.on.aws/ping

```