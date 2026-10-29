cd "c:\Users\Anil Krishna\anikris\aism\awsagentcore_appl\Deployment\Terraform\AgentCoreGateway"
$url = terraform output -raw gateway_url
Write-Host "Gateway URL: $url"

cd "c:\Users\Anil Krishna\anikris\aism\awsagentcore_appl\Deployment\Terraform\AppClients"
$sec = terraform output -json client_secrets | ConvertFrom-Json
Write-Host "Client secrets loaded: $sec"
$env:OIDC_CLIENTID_Local_Expert_City_Guide     = "43uv1tea5kf45713brp310nabk"
$env:OIDC_CLIENTSECRET_Local_Expert_City_Guide = $sec.local_expert__city_guide



$tok = (Invoke-RestMethod -Method Post "https://$env:OIDC_AUTHORITY.auth.us-east-1.amazoncognito.com/oauth2/token" `
  -ContentType "application/x-www-form-urlencoded" `
  -Body "grant_type=client_credentials&client_id=$env:OIDC_CLIENTID_Local_Expert_City_Guide&client_secret=$env:OIDC_CLIENTSECRET_Local_Expert_City_Guide").access_token

$h = @{ Authorization = "Bearer $tok"; Accept = "application/json" }

Invoke-RestMethod -Method Post $url -Headers $h -ContentType "application/json" -Body '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | ConvertTo-Json -Depth 10

Invoke-RestMethod -Method Post $url -Headers $h -ContentType "application/json" -Body '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"query-travel-plans___query_travel_plans","arguments":{"TravelCity":"Paris"}}}' | ConvertTo-Json -Depth 10

try { Invoke-RestMethod -Method Post $url -Headers $h -ContentType "application/json" -Body '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' }
catch { (New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() }