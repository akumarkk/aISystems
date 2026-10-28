$scopes = @("default-m2m-resource-server-vgesoa/read",
    "https://localexpertcityguide.vacationplanner.com/local_expert__city_guide",
    "https://localexpertcityguide.vacationplanner.com/local_expert_read",
    "https://localexpertcityguide.vacationplanner.com/local_expert_write"
)

curl.exe -X POST "https://$($env:OIDC_AUTHORITY).auth.us-east-1.amazoncognito.com/oauth2/token" `
  -H "Content-Type: application/x-www-form-urlencoded" `
  --data-urlencode "grant_type=client_credentials" `
  --data-urlencode "client_id=$env:OIDC_CLIENTID_Local_Expert_City_Guide" `
  --data-urlencode "client_secret=$env:OIDC_CLIENTSECRET_Local_Expert_City_Guide" `
  --data-urlencode "scope=$($scopes -join ' ')"

# curl -X POST https://$env:OIDC_AUTHORITY".auth.us-east-1.amazoncognito.com/oauth2/token `
#   -H "Content-Type: application/x-www-form-urlencoded" `
#   -d "grant_type=client_credentials&client_id=$env:OIDC_CLIENTID_Local_Expert_City_Guide&client_secret=$env:OIDC_CLIENTSECRET_Local_Expert_City_Guide$&scope=$($scopes -join ' ')"