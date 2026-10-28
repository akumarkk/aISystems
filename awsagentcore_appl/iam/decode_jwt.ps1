function Decode-Jwt {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$Token
    )

    process {
        # Extract payload (middle part of Header.Payload.Signature)
        $payload = $Token.Split('.')[1]

        # Fix Base64 padding if needed
        while ($payload.Length % 4) { $payload += '=' }

        # Convert Base64 URL to string and parse JSON
        [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload)) | ConvertFrom-Json
    }
}