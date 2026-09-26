<#
.SYNOPSIS
  Update ComfyUI core and custom nodes in a portable / Easy-Install tree while keeping the
  input, output, models and user\default\workflows links intact. Dry run by default.

.DESCRIPTION
  With -Apply it does, in order:
    1. Record the current junction/symlink for input, output, models, user\default\workflows.
    2. Run the official update\update.py (stashes local changes, creates a backup_branch_*,
       checks out master, pulls, and pip-installs core requirements.txt).
    3. Report stale "~*" pip leftovers under site-packages (deletes them only with
       -CleanPipLeftovers).
    4. Update custom nodes with ComfyUI-Manager's cm-cli.py (skip with -SkipNodeUpdate).
    5. Restore any recorded link that git replaced with a plain folder. The plain folder is
       renamed to <name>.orphaned-<timestamp>, never deleted. Runs even if step 2 or 4 failed.
    6. Smoke test: import comfy.utils with the embedded python, so a startup crash (e.g. a
       broken triton install) shows up here and not on first launch.

  No package is pinned here; core requirements.txt decides what gets installed.

  ComfyUI must be closed before -Apply.

  Rolling back: git checkout <hash> in ComfyUI\ reverts core code only. If the startup log
  said the asset database was migrated, also copy user\comfyui.db.bkp back over
  user\comfyui.db. pip and custom-node changes are not rolled back by git.

.PARAMETER ComfyRoot
  Install root (folder containing ComfyUI\, python_embeded\ and update\), e.g.
  C:\ComfyUI_easy\ComfyUI-Easy-Install, C:\ComfyUI-Easy-Install, C:\ComfyUI_windows_portable

.PARAMETER SwitchToMaster
  Needed with -Apply when the repo is in detached HEAD (pinned to a tag); update.py will
  move it onto master, which is a bigger change than an ordinary pull.

.PARAMETER SkipNodeUpdate
  Skip the ComfyUI-Manager "update all" step.

.PARAMETER CleanPipLeftovers
  Delete the "~*" folders under site-packages. Off by default; they are only reported.

.PARAMETER Apply
  Actually perform the update. Without this, only reports what it would do.

.EXAMPLE
  .\update-comfyui.ps1 -ComfyRoot 'C:\ComfyUI-Easy-Install'
.EXAMPLE
  .\update-comfyui.ps1 -ComfyRoot 'C:\ComfyUI-Easy-Install' -Apply
.EXAMPLE
  .\update-comfyui.ps1 -ComfyRoot 'C:\ComfyUI_easy\ComfyUI-Easy-Install' -SwitchToMaster -Apply
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ComfyRoot,

    [switch]$SwitchToMaster,
    [switch]$SkipNodeUpdate,
    [switch]$CleanPipLeftovers,
    [switch]$Apply
)

# Continue, not Stop: with Stop, PowerShell 5.1 turns any stderr line from git/pip into a
# terminating error. Native exit codes are checked explicitly instead.
$ErrorActionPreference = 'Continue'

$comfyDir  = Join-Path $ComfyRoot 'ComfyUI'
$pythonExe = Join-Path $ComfyRoot 'python_embeded\python.exe'
$updateDir = Join-Path $ComfyRoot 'update'
$updatePy  = Join-Path $updateDir 'update.py'
$sitePkgs  = Join-Path $ComfyRoot 'python_embeded\Lib\site-packages'
$cmCli     = Join-Path $comfyDir 'custom_nodes\ComfyUI-Manager\cm-cli.py'
$linkRels  = @('input', 'output', 'models', 'user\default\workflows')

#region links
# git checkout/stash does not understand NTFS junctions and replaces them with plain folders
# when it has tracked placeholder files to write there, so links are recorded and restored.
function Get-RecordedLinks {
    param([string]$BaseDir, [string[]]$Rels)
    $found = @()
    foreach ($rel in $Rels) {
        $p = Join-Path $BaseDir $rel
        $i = Get-Item -Path $p -Force -ErrorAction SilentlyContinue
        if ($i -and $i.LinkType) {
            $found += [pscustomobject]@{
                Rel      = $rel
                Path     = $p
                LinkType = [string]$i.LinkType
                Target   = (@($i.Target) -join '')
            }
        }
    }
    return $found
}

function Restore-Links {
    param($Links)
    foreach ($l in $Links) {
        $cur = Get-Item -Path $l.Path -Force -ErrorAction SilentlyContinue
        if ($cur -and $cur.LinkType -and ((@($cur.Target) -join '') -eq $l.Target)) {
            Write-Host "  ok: $($l.Rel) still -> $($l.Target)"
            continue
        }
        try {
            if ($cur) {
                $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
                $asideName = (Split-Path $l.Path -Leaf) + ".orphaned-$stamp"
                $n = 1
                while (Test-Path (Join-Path (Split-Path $l.Path -Parent) $asideName)) {
                    $n++
                    $asideName = (Split-Path $l.Path -Leaf) + ".orphaned-$stamp-$n"
                }
                $note = ''
                if (-not $cur.LinkType) {
                    $files = @(Get-ChildItem -Path $l.Path -Recurse -File -Force -ErrorAction SilentlyContinue)
                    $other = @($files | Where-Object {
                        $_.Name -notlike 'put_*' -and $_.Name -ne '_output_images_will_be_put_here' -and
                        $_.Name -ne 'example.png' -and $_.Extension -ne '.yaml'
                    })
                    $note = " ($($files.Count) file(s), $($other.Count) beyond git placeholders - review before deleting)"
                }
                Rename-Item -Path $l.Path -NewName $asideName -ErrorAction Stop
                Write-Host "  moved aside: $($l.Rel) -> $asideName$note"
            }
            $parent = Split-Path $l.Path -Parent
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            New-Item -ItemType $l.LinkType -Path $l.Path -Target $l.Target -ErrorAction Stop | Out-Null
            Write-Host "  restored: $($l.Rel) -> $($l.Target)"
        } catch {
            Write-Warning "  FAILED to restore $($l.Rel): $($_.Exception.Message)"
        }
    }
}
#endregion links

if (-not (Test-Path $comfyDir))  { throw "No ComfyUI\ subfolder under $ComfyRoot" }
if (-not (Test-Path $pythonExe)) { throw "No embedded python at $pythonExe" }
if (-not (Test-Path $updatePy))  { throw "No official updater at $updatePy (expected the standard update\ folder)" }

$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and ($_.Path -like (Join-Path $ComfyRoot 'python_embeded\*'))
})

Push-Location $comfyDir
try {
    Write-Host "=== $ComfyRoot ==="
    Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'DRY RUN (pass -Apply to actually update)' })"
    Write-Host ""

    $branch = git rev-parse --abbrev-ref HEAD
    $detached = ($branch -eq 'HEAD')
    $beforeCommit = git rev-parse --short HEAD
    $beforeDate = git log -1 --format='%ci'
    Write-Host "Current: $(if ($detached) { 'DETACHED HEAD' } else { "branch '$branch'" }) at $beforeCommit ($beforeDate)"

    Write-Host "Fetching from origin (updates remote-tracking refs only)..."
    git fetch origin 2>&1 | Out-Null
    $behind = git rev-list --count 'HEAD..origin/master'
    Write-Host "$behind commit(s) behind origin/master."
    if ([int]$behind -gt 0) {
        git log --oneline 'HEAD..origin/master' | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" }
    }
    Write-Host ""

    $links = @(Get-RecordedLinks -BaseDir $comfyDir -Rels $linkRels)
    Write-Host "Links to keep intact:"
    if ($links.Count -eq 0) { Write-Host "  (none found)" }
    foreach ($l in $links) { Write-Host "  $($l.Rel) [$($l.LinkType)] -> $($l.Target)" }
    Write-Host ""

    if ($running.Count -gt 0) {
        $msg = "ComfyUI looks to be running from this install (python.exe pid $(($running | ForEach-Object { $_.Id }) -join ', ')). Close it first."
        if ($Apply) { throw $msg } else { Write-Warning $msg }
    }

    if ($detached -and -not $SwitchToMaster) {
        Write-Warning "Detached HEAD. Pass -SwitchToMaster (with -Apply) to move onto master. Stopping."
        return
    }

    if (-not $Apply) {
        Write-Host "[DRY RUN] Would run:"
        Write-Host "  $pythonExe $updatePy $comfyDir"
        Write-Host "  report stale '~*' folders in $sitePkgs$(if ($CleanPipLeftovers) { ' and delete them' })"
        if (-not $SkipNodeUpdate) {
            if (Test-Path $cmCli) { Write-Host "  $pythonExe $cmCli update all" }
            else { Write-Host "  (cm-cli.py not found - node update would be skipped)" }
        }
        Write-Host "  restore any of the $($links.Count) link(s) above that git replaced with a plain folder"
        Write-Host "  smoke test: import comfy.utils"
        return
    }

    Write-Host "Rollback (core code only): git checkout $beforeCommit   (see .DESCRIPTION for the DB caveat)"
    Write-Host ""

    $failed = $null
    try {
        Write-Host "1/5: official updater (update\update.py)"
        Push-Location $updateDir
        try {
            & $pythonExe '.\update.py' '..\ComfyUI\'
            if ($LASTEXITCODE -ne 0) { throw "update.py exited with code $LASTEXITCODE" }
            if (Test-Path 'update_new.py') {
                Move-Item -Force 'update_new.py' 'update.py'
                Write-Host "Updater self-updated; running it again..."
                & $pythonExe '.\update.py' '..\ComfyUI\' '--skip_self_update'
                if ($LASTEXITCODE -ne 0) { throw "update.py (second run) exited with code $LASTEXITCODE" }
            }
        } finally { Pop-Location }

        Write-Host "2/5: stale '~*' pip leftovers"
        $stale = @(Get-ChildItem -Path $sitePkgs -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '~*' })
        if ($stale.Count -eq 0) { Write-Host "  none" }
        foreach ($s in $stale) {
            if ($CleanPipLeftovers) {
                Write-Host "  removing $($s.FullName)"
                Remove-Item -Path $s.FullName -Recurse -Force
            } else {
                Write-Host "  found $($s.FullName) (re-run with -CleanPipLeftovers to delete)"
            }
        }

        if ($SkipNodeUpdate) {
            Write-Host "3/5: custom node update skipped (-SkipNodeUpdate)"
        } elseif (Test-Path $cmCli) {
            Write-Host "3/5: updating custom nodes via ComfyUI-Manager"
            & $pythonExe -s $cmCli update all
            if ($LASTEXITCODE -ne 0) { Write-Warning "cm-cli.py exited with code $LASTEXITCODE" }
        } else {
            Write-Warning "3/5: cm-cli.py not found at $cmCli - skipping node update."
        }
    } catch {
        $failed = $_
        Write-Warning "Update step failed: $($_.Exception.Message)"
    }

    Write-Host "4/5: restoring links"
    Restore-Links -Links $links

    Write-Host "5/5: smoke test (import comfy.utils)"
    $out = & $pythonExe -s -c "import comfy.utils; print('core import OK')" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  $out"
    } else {
        Write-Warning "core import FAILED - ComfyUI will probably not start:"
        @($out) | Select-Object -Last 12 | ForEach-Object { Write-Host "    $_" }
    }

    $afterCommit = git rev-parse --short HEAD
    $afterDate = git log -1 --format='%ci'
    Write-Host ""
    Write-Host "Core: $beforeCommit -> $afterCommit ($afterDate)"
    if (Test-Path (Join-Path $comfyDir 'user\comfyui.db.bkp')) {
        Write-Host "Note: user\comfyui.db.bkp exists (pre-migration asset DB). Keep it; a rollback needs it."
    }
    Write-Host "Start ComfyUI and open a real saved workflow before calling this box done."
    if ($failed) { exit 1 }
}
finally {
    Pop-Location
}
