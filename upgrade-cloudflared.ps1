# Upgrade cloudflared in place on a Windows fleet box (run from an ADMIN PowerShell).
# Finds the running cloudflared.exe, downloads the release, verifies its SHA-256
# against the digest GitHub publishes for the asset, backs up the old exe,
# restarts the "Cloudflared Tunnel" scheduled task, and prints the new version.
param(
    [string]$Version = "2026.10.4",
    [string]$TaskName = "Cloudflared Tunnel"
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$proc = Get-CimInstance Win32_Process | Where-Object { $_.Name -match "cloudflared" } | Select-Object -First 1
if (-not $proc) { throw "no running cloudflared process found" }
$exe = $proc.ExecutablePath
"current exe: $exe"
"current version: " + (& $exe --version | Select-Object -First 1)

$assetName = "cloudflared-windows-amd64.exe"
$rel = Invoke-RestMethod "https://api.github.com/repos/cloudflare/cloudflared/releases/tags/$Version"
$asset = $rel.assets | Where-Object { $_.name -eq $assetName }
if (-not $asset) { throw "asset $assetName not found in release $Version" }
if (-not $asset.digest -or $asset.digest -notmatch "^sha256:") { throw "no sha256 digest published for asset" }
$want = $asset.digest.Substring(7).ToUpper()

$new = "$exe.new"
Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $new
$got = (Get-FileHash $new -Algorithm SHA256).Hash.ToUpper()
if ($got -ne $want) { Remove-Item $new; throw "SHA-256 mismatch: got $got want $want" }
"sha256 verified: $got"

$bak = "$exe.bak-" + (Get-Date -Format "yyyy-MM-dd")
Copy-Item $exe $bak
"backup: $bak"

Stop-ScheduledTask -TaskName $TaskName
Start-Sleep 3
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force
Move-Item $new $exe -Force
Start-ScheduledTask -TaskName $TaskName
Start-Sleep 8

"new version: " + (& $exe --version | Select-Object -First 1)
Get-CimInstance Win32_Process | Where-Object { $_.Name -match "cloudflared" } |
    Select-Object ProcessId, CommandLine | Format-List
