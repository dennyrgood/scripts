# TravelBeast\tb-nightly-summary.ps1
# 2026-08-31 UTC -- created, modeled on ImageBeast/ib-nightly-summary.ps1. Runs once
# nightly via Task Scheduler. Sends one email with a TLDR block + supporting detail.
#
# tb has no Fleet Checker task (confirmed via Get-ScheduledTask 2026-08-31) -- it isn't
# one of the two Fleet Status Checker instances (those are amsdt + cwh only), so there
# is no server_status_all.json section here, same as ib's nightly-summary.
#
# tb's own diagnostic (unique to this box): power-heartbeat.ps1's WiFi-flap CSV log,
# at C:\fleet_monitor\power_heartbeat_travelbeast\power_heartbeat_v{N}_travelbeast_<date>.csv
# (confirmed via reading the script's own $LogDir, not guessed). Schema version N bumps
# whenever power-heartbeat.ps1 gains a column (v3->v4 happened 2026-09-11) -- match by
# most-recently-written file, not an exact-version filename, so the next bump doesn't
# silently break this report the way it broke tb-health-monitor.ps1's equivalent check
# that same day (fixed there the same way).
#
# ASCII only -- PowerShell 5.1 has no BOM handling and mis-decodes non-ASCII (CLAUDE.md).
# Check/warning marks built from character codes so the SOURCE stays ASCII while still
# emitting real glyphs at runtime.

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Send-FleetMail.ps1"

$Check = [char]::ConvertFromUtf32(0x2705)
$Warn  = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F

$HostName = "travelbeast"
$MonitorStateFile = Join-Path $env:TEMP "$HostName-monitor-state.tmp"
$FleetMonitorDir = "C:\fleet_monitor"
$WatchdogLog = Join-Path $FleetMonitorDir "watchdog_$HostName.log"
$PowerHbDir = Join-Path $FleetMonitorDir "power_heartbeat_travelbeast"
$PowerHbErrLog = Join-Path $PowerHbDir "power_heartbeat_errors.log"

function Format-Age($ts) {
    $secs = (New-TimeSpan -Start $ts -End (Get-Date)).TotalSeconds
    if ($secs -lt 3600) { return "$([int]($secs / 60))m" }
    elseif ($secs -lt 172800) { return "$([int]($secs / 3600))h" }
    else { return "$([int]($secs / 86400))d" }
}

$Reason = "all healthy"
$Tldr = "============================= TLDR ===============================`r`n"
$Body = ""

# --- FleetMetricsWatchdog log tail ---
if (Test-Path $WatchdogLog) {
    $wdAge = Format-Age (Get-Item $WatchdogLog).LastWriteTime
    $Tldr += "  watchdog log: [$wdAge ago last write] $(Get-Content $WatchdogLog -Tail 1)`r`n"
    $Body += "=== FleetMetricsWatchdog log (last 10 lines) ===`r`n"
    $Body += (Get-Content $WatchdogLog -Tail 10 | Out-String)
    $Body += "`r`n"
} else {
    $Tldr += "$Warn  watchdog log: not found at $WatchdogLog`r`n"
    if ($Reason -eq "all healthy") { $Reason = "watchdog log missing" }
}

# --- power-heartbeat WiFi-flap CSV: most recent file by write time, not an exact
# "today's date + hardcoded schema version" filename -- see comment above for why.
$latestCsv = Get-ChildItem $PowerHbDir -Filter "power_heartbeat_v*_travelbeast_*.csv" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latestCsv -and ((Get-Date) - $latestCsv.LastWriteTime).TotalMinutes -lt 20) {
    $rows = Import-Csv $latestCsv.FullName
    $rowCount = ($rows | Measure-Object).Count
    $Tldr += "  power-heartbeat: today's log has $rowCount sample(s) $Check`r`n"
    $Body += "=== power-heartbeat (today, last 5 samples) ===`r`n"
    $Body += ($rows | Select-Object -Last 5 | Format-Table -AutoSize | Out-String)
    $Body += "`r`n"
} else {
    $detail = if ($latestCsv) { "most recent is $($latestCsv.Name), last written $([int]((Get-Date) - $latestCsv.LastWriteTime).TotalMinutes) min ago" } else { "no power_heartbeat_v*_travelbeast_*.csv found in $PowerHbDir" }
    $Tldr += "$Warn  power-heartbeat: no fresh log ($detail)`r`n"
    if ($Reason -eq "all healthy") { $Reason = "power-heartbeat log missing/stale" }
}
if (Test-Path $PowerHbErrLog) {
    $errAge = Format-Age (Get-Item $PowerHbErrLog).LastWriteTime
    if ($errAge -match '^[0-9]+m$' -or $errAge -match '^[0-9]+h$') {
        # Only surface it if written recently (within the log's own retention window is
        # hard to know generically, so just show it exists and how old -- reading WHICH
        # errors requires knowing the format, left to the body dump below).
        $Body += "=== power_heartbeat_errors.log (last 5 lines) ===`r`n"
        $Body += (Get-Content $PowerHbErrLog -Tail 5 | Out-String)
        $Body += "`r`n"
    }
}

# --- Health monitor state ---
if (Test-Path $MonitorStateFile) {
    $stateAge = (New-TimeSpan -Start (Get-Item $MonitorStateFile).LastWriteTime -End (Get-Date)).TotalMinutes
    if ($stateAge -gt 10) {
        $Tldr += "$Warn  tb-health-monitor: stale (last-run $([int]$stateAge)m ago; threshold 10m)`r`n"
        if ($Reason -eq "all healthy") { $Reason = "health monitor stale/missing" }
    } else {
        $Tldr += "  tb-health-monitor: last-run $([int]$stateAge)m ago $Check`r`n"
    }
    $stateLines = Get-Content $MonitorStateFile
    $active = $stateLines | Where-Object { $_ -match "_ACTIVE=1$" }
    if ($active) {
        $Tldr += "$Warn  tb-health-monitor: ACTIVE ALERTS`r`n"
        if ($Reason -eq "all healthy") { $Reason = "active health alerts" }
    } else {
        $Tldr += "  tb-health-monitor: no active alerts $Check`r`n"
    }
    $Body += "=== HEALTH MONITOR STATE ===`r`n"
    if ($active) { $Body += "ACTIVE ALERTS:`r`n$($active -join "`r`n")`r`n`r`n" } else { $Body += "No active alerts.`r`n`r`n" }
    $Body += ($stateLines | Out-String)
    $Body += "`r`n"
} else {
    $Tldr += "$Warn  tb-health-monitor: state file not found -- has not run`r`n"
    if ($Reason -eq "all healthy") { $Reason = "health monitor stale/missing" }
}

$Tldr += "===================================================================`r`n`r`n"
$Body = $Tldr + $Body

if ($Reason -eq "all healthy") { $Emoji = "$Check" } else { $Emoji = "$Warn" }
$Subject = "$Emoji TravelBeast nightly $(Get-Date -Format 'yyyy-MM-dd') -- $Reason"

Send-FleetMail -Subject $Subject -Body $Body -Cc "dennis.mathes@icloud.com" | Out-Null
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') nightly summary sent -- $Reason"
