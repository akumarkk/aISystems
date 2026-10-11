$release = Invoke-RestMethod "https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/tags/Ghidra_12.1_build"
$asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
$url = $asset.browser_download_url
$zipPath = "$env:TEMP\ghidra.zip"

Invoke-WebRequest -Uri $url -OutFile $zipPath

# 2. Extract it
$installRoot = "C:\tools"
New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Expand-Archive -Path $zipPath -DestinationPath $installRoot -Force

# The zip usually contains a single top-level folder like ghidra_12.1_PUBLIC
$extractedFolder = Get-ChildItem $installRoot -Directory | Where-Object { $_.Name -like "ghidra_12.1*" } | Select-Object -First 1
$ghidraPath = $extractedFolder.FullName

# 3. Set GHIDRA_INSTALL_DIR permanently (User scope) and in current session
setx GHIDRA_INSTALL_DIR "$ghidraPath"
$env:GHIDRA_INSTALL_DIR = $ghidraPath

Write-Host "Ghidra installed at: $ghidraPath"