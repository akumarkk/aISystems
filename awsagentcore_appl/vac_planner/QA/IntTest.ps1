# Integration test: call the deployed vac_planner runtime over its public HTTPS endpoint,
# the way a client app does: SigV4-signed POST /runtimes/{arn}/invocations.
# AgentCore health-checks the container's GET /ping internally but does not expose it,
# so the default check sends {"path": "/ping"}: server.py hands it to do_GET and returns
# the /ping response without kicking off the crew (no LLM cost).
#   .\IntTest.ps1        ping
#   .\IntTest.ps1 -Full  real crew run with sample inputs (takes minutes)
param([switch]$Full)

$region = "us-east-1"
$service = "bedrock-agentcore"
$runtimeArn = "arn:aws:bedrock-agentcore:us-east-1:837873138218:runtime/vac_planner-4M3CfW8SGa"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Temporary credentials from the active CLI session
$creds = aws configure export-credentials --format process | ConvertFrom-Json
if (-not $creds.AccessKeyId) { Write-Error "No AWS credentials; run 'aws login' first"; exit 1 }

if ($Full) {
    $body = @{ inputs = @{
        origin       = "Seattle"
        travel_dates = "June 10-17, 2027"
        travelers    = "2 adults"
        budget       = "`$5,000"
        interests    = "food, hiking, history"
    } } | ConvertTo-Json -Compress
} else {
    $body = '{"path":"/ping"}'
}

function Get-Sha256Hex([byte[]]$bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") })
}
function Get-HmacSha256([byte[]]$key, [string]$data) {
    $hmac = New-Object Security.Cryptography.HMACSHA256 (, $key)
    $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($data))
}

$hostName = "$service.$region.amazonaws.com"
$encodedArn = [Uri]::EscapeDataString($runtimeArn)
$path = "/runtimes/$encodedArn/invocations"
$query = "qualifier=DEFAULT"
$uri = "https://$hostName${path}?$query"

# SigV4: non-S3 services sign the path with each segment URI-encoded a second time
$canonicalUri = ($path -split "/" | ForEach-Object { [Uri]::EscapeDataString($_) }) -join "/"
$now = [DateTime]::UtcNow
$amzDate = $now.ToString("yyyyMMddTHHmmssZ")
$dateStamp = $now.ToString("yyyyMMdd")
$bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
$payloadHash = Get-Sha256Hex $bodyBytes

$headers = [ordered]@{
    "host"                 = $hostName
    "x-amz-content-sha256" = $payloadHash
    "x-amz-date"           = $amzDate
}
if ($creds.SessionToken) { $headers["x-amz-security-token"] = $creds.SessionToken }

$canonicalHeaders = ($headers.Keys | ForEach-Object { "${_}:$($headers[$_])`n" }) -join ""
$signedHeaders = $headers.Keys -join ";"
$canonicalRequest = "POST`n$canonicalUri`n$query`n$canonicalHeaders`n$signedHeaders`n$payloadHash"

$scope = "$dateStamp/$region/$service/aws4_request"
$stringToSign = "AWS4-HMAC-SHA256`n$amzDate`n$scope`n" + (Get-Sha256Hex ([Text.Encoding]::UTF8.GetBytes($canonicalRequest)))

$kDate = Get-HmacSha256 ([Text.Encoding]::UTF8.GetBytes("AWS4" + $creds.SecretAccessKey)) $dateStamp
$kRegion = Get-HmacSha256 $kDate $region
$kService = Get-HmacSha256 $kRegion $service
$kSigning = Get-HmacSha256 $kService "aws4_request"
$signature = -join ((Get-HmacSha256 $kSigning $stringToSign) | ForEach-Object { $_.ToString("x2") })

$curlArgs = @(
    "-s", "-X", "POST", $uri,
    "-H", "Authorization: AWS4-HMAC-SHA256 Credential=$($creds.AccessKeyId)/$scope, SignedHeaders=$signedHeaders, Signature=$signature",
    "-H", "x-amz-content-sha256: $payloadHash",
    "-H", "x-amz-date: $amzDate",
    "-H", "Content-Type: application/json"
)
if ($creds.SessionToken) { $curlArgs += @("-H", "x-amz-security-token: $($creds.SessionToken)") }

# curl.exe, not Invoke-WebRequest: .NET Framework decodes %2F in the path to "/",
# which breaks the encoded ARN and makes AgentCore answer 405
$bodyFile = Join-Path $env:TEMP "vac_planner_body.json"
$outFile = Join-Path $env:TEMP "vac_planner_out.json"
[IO.File]::WriteAllBytes($bodyFile, $bodyBytes)
$curlArgs += @("--data-binary", "@$bodyFile", "-o", $outFile, "-w", "%{http_code}", "--max-time", "900")

Write-Output "POST $uri"
$status = [int](& curl.exe @curlArgs)
$content = if (Test-Path $outFile) { Get-Content $outFile -Raw } else { "" }
Write-Output "HTTP $status"
Write-Output $content

# AgentCore relays a container error status as 424; 403 (auth) or 5xx come from AgentCore
$pass = $status -eq 200 -and ($Full -or $content -match '"Healthy"')
if ($pass) {
    Write-Output "PASS"
    exit 0
}
Write-Output "FAIL: unexpected response"
exit 1
