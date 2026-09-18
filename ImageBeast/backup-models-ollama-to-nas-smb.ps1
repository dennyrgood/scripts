# backup-models-ollama-to-nas-smb.ps1
# One-time backup: OneDrive Models_ollama (ib) -> FleetNAS \\192.168.178.123\misc\models_backup\Models_ollama
# Priority 3.
#
# See backup-comfyui-models-to-nas-smb.ps1 for why SMB/robocopy is used instead
# of rsync/SSH, and for the one-time `net use` setup step.
#
# Pre-check already done: verified 2026-09-18 that all 163 files in this OneDrive
# folder are fully hydrated locally (no OFFLINE / cloud-placeholder attributes),
# so this is a real local copy, not stub files. Re-check if OneDrive has evicted
# files to free space since then:
#   Get-ChildItem -Recurse -File <path> | Where-Object { $_.Attributes -band 0x1000 -or $_.Attributes -band 0x400000 }
#
# Usage:
#   .\backup-models-ollama-to-nas-smb.ps1                # dry run, additive only (/L: lists only, copies nothing)
#   .\backup-models-ollama-to-nas-smb.ps1 go              # real run, additive only (adds/updates, never deletes)
#   .\backup-models-ollama-to-nas-smb.ps1 -Mirror         # dry run, MIRROR (also lists what it would DELETE on the NAS)
#   .\backup-models-ollama-to-nas-smb.ps1 go -Mirror      # real run, MIRROR -- DELETES NAS-side files/folders
#                                                            not present under $Src. Always review the -Mirror
#                                                            dry run first; there is no undo.

param(
    [string]$Mode = "",
    [switch]$Mirror
)

$Src  = "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_ollama"
$Dest = "\\192.168.178.123\misc\models_backup\Models_ollama"
$LogDir = "$env:USERPROFILE\.cache\fleetnas-sync"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Ts = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "ib_models_ollama_${Ts}.log"

if (-not (Test-Path $Src)) {
    Write-Error "Source path not found: $Src -- aborting. (Especially important in -Mirror mode, which deletes NAS-side files not present under a missing/renamed source.)"
    exit 1
}

$CommonArgs = @("/Z", "/MT:8", "/R:3", "/W:5", "/NP", "/LOG+:$LogFile", "/TEE")
$CommonArgs += if ($Mirror) { "/MIR" } else { "/E" }

if ($Mode -eq "go") {
    if ($Mirror) {
        Write-Warning "MIRROR MODE: this will DELETE files/folders under $Dest that no longer exist under $Src."
    }
    Write-Output ">>> REAL RUN$(if ($Mirror) { ' (MIRROR -- deletes extras)' }): $Src -> $Dest"
    Write-Output "Log: $LogFile"
    robocopy $Src $Dest @CommonArgs
} else {
    Write-Output ">>> DRY RUN$(if ($Mirror) { ' (MIRROR -- would also list deletions)' }) (pass 'go' as arg to actually copy): $Src -> $Dest"
    robocopy $Src $Dest @CommonArgs /L
}

if ($LASTEXITCODE -ge 8) {
    Write-Error "robocopy reported failure, exit code $LASTEXITCODE. See $LogFile"
} else {
    Write-Output "robocopy exit code $LASTEXITCODE (0-7 = success/no-op variants). See $LogFile"
}
