# backup-comfyui-models-to-nas-smb.ps1
# One-time backup: C:\ComfyUI_Models (ib) -> FleetNAS \\192.168.178.123\misc\models_backup\ComfyUI_Models
# Priority 1 (no other existing copy of this dir).
#
# Uses SMB + robocopy instead of rsync/SSH: native Windows rsync+OpenSSH cannot
# talk to FleetNAS's UGOS rsync-backup wrapper at all (confirmed 2026-09-18 --
# "dup() in/out/err failed" / connection closed, 0 bytes transferred; same
# failure class documented in AmsterdamDesktop/push_media_to_fleetnas.sh on
# 2026-08-04, there worked around via WSL, which `ib` doesn't have installed).
# SMB is a different protocol and isn't affected by that wrapper.
#
# ONE-TIME manual setup before running this (do it once per session -- the
# credential isn't cached across reboots): map/authenticate the share:
#   net use \\192.168.178.123\misc /user:dhm *
# (the trailing * makes it prompt for the password instead of taking it on
# the command line). Destination folder \\192.168.178.123\misc\models_backup
# was already created via SSH (2026-09-18) -- confirm with:
#   dir \\192.168.178.123\misc\models_backup
#
# Usage:
#   .\backup-comfyui-models-to-nas-smb.ps1                # dry run, additive only (/L: lists only, copies nothing)
#   .\backup-comfyui-models-to-nas-smb.ps1 go              # real run, additive only (adds/updates, never deletes)
#   .\backup-comfyui-models-to-nas-smb.ps1 -Mirror         # dry run, MIRROR (also lists what it would DELETE on the NAS)
#   .\backup-comfyui-models-to-nas-smb.ps1 go -Mirror      # real run, MIRROR -- DELETES NAS-side files/folders
#                                                             not present under $Src. Always review the -Mirror
#                                                             dry run first; there is no undo.

param(
    [string]$Mode = "",
    [switch]$Mirror
)

$Src  = "C:\ComfyUI_Models"
$Dest = "\\192.168.178.123\misc\models_backup\ComfyUI_Models"
$LogDir = "$env:USERPROFILE\.cache\fleetnas-sync"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Ts = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "ib_comfyui_models_${Ts}.log"

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

# robocopy exit codes 0-7 are all "success" variants (bitmask of what happened);
# only 8+ indicates a real failure.
if ($LASTEXITCODE -ge 8) {
    Write-Error "robocopy reported failure, exit code $LASTEXITCODE. See $LogFile"
} else {
    Write-Output "robocopy exit code $LASTEXITCODE (0-7 = success/no-op variants). See $LogFile"
}
