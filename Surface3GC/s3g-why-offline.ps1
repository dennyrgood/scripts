# s3g-why-offline.ps1 -- read-only evidence for "is it the link or the box?"
# Created: 2026-10-24.
#
# WHY THIS EXISTS
#   Since 2026-10-20 13:16 (Amsterdam) wbu's Syncthing sees s3g in short
#   sessions -- often ending ~60 min after they start -- with hours of nothing
#   in between. Before that a single connection held for four days. From wbu
#   the two causes look identical: a dead Gran Canaria link and a sleeping box
#   both just stop answering. Only this machine's own event log can tell them
#   apart:
#     - sleep/resume, AC <-> battery switches, unexpected power loss -> the BOX
#     - network disconnect/reconnect while the box stays awake       -> the LINK
#
# OUTPUT
#   C:\fleet_monitor\watchdog_s3g-why-offline_surface3-gc.txt -- the name fits
#   fleet_metrics_server.py's allowlist, so wbu can fetch it next time s3g is
#   up:  curl http://100.72.84.84:9100/watchdog_s3g-why-offline_surface3-gc.txt
#   C:\fleet_monitor\battery-report.html -- open locally (not served).
#
# Changes nothing. Run from an elevated PowerShell for the battery report;
# everything else works unelevated.
#
# ASCII only -- PowerShell 5.1 mis-decodes non-ASCII source (CLAUDE.md).

param([int]$Days = 7)

$outDir  = "C:\fleet_monitor"
$outFile = Join-Path $outDir "watchdog_s3g-why-offline_surface3-gc.txt"
$since   = (Get-Date).AddDays(-$Days)
$lines   = New-Object System.Collections.Generic.List[string]
function Say([string]$s = "") { $lines.Add($s); Write-Host $s }

Say "s3g-why-offline  generated $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))  window: last $Days days"
$os = Get-CimInstance Win32_OperatingSystem
Say "last boot: $($os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Say ""

# --- power source right now ---------------------------------------------------
Say "=== battery / power source now ==="
$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($bat) {
    # BatteryStatus: 1 = discharging (on battery), 2 = on AC
    $src = if ($bat.BatteryStatus -eq 2) { "AC" } elseif ($bat.BatteryStatus -eq 1) { "BATTERY (discharging)" } else { "status code $($bat.BatteryStatus)" }
    Say "source=$src  charge=$($bat.EstimatedChargeRemaining)%"
} else { Say "no battery reported" }
Say ""

# --- sleep settings -------------------------------------------------------------
# Sleep and hibernate timeouts for AC and battery. A 60-minute value here would
# match the ~1h sessions seen from wbu.
Say "=== sleep settings (active power plan) ==="
Say ((powercfg /getactivescheme) -join " ")
$q = powercfg /query SCHEME_CURRENT SUB_SLEEP
$name = ""
foreach ($l in $q) {
    if ($l -match 'Power Setting GUID: \S+\s+\((.+)\)') { $name = $Matches[1] }
    elseif ($l -match 'Current (AC|DC) Power Setting Index: 0x([0-9a-fA-F]+)') {
        $v = [Convert]::ToInt64($Matches[2], 16)
        $txt = if ($name -match 'after') { if ($v -eq 0) { "never" } else { "$([math]::Round($v/60)) min" } } else { "$v" }
        Say ("  {0,-35} {1}: {2}" -f $name, $Matches[1], $txt)
    }
}
Say "available sleep states:"
powercfg /a | ForEach-Object { Say "  $_" }
Say ""

# --- the timeline -----------------------------------------------------------------
# Every event that marks the box going away or coming back, merged and sorted.
Say "=== power + network timeline (local time) ==="
$sysIds = @{
    'Microsoft-Windows-Kernel-Power'           = @(41, 42, 105, 107, 109, 506, 507)
    'Microsoft-Windows-Power-Troubleshooter'   = @(1)
    'Microsoft-Windows-Kernel-General'         = @(12, 13)
    'EventLog'                                 = @(6005, 6006, 6008)
}
$labels = @{
    41 = "UNEXPECTED power loss / hard reset"; 42 = "entering SLEEP"; 105 = "power source change (AC/battery)"
    107 = "resumed from sleep"; 109 = "shutdown initiated"; 506 = "entering connected standby"
    507 = "exiting connected standby"; 1 = "woke up"; 12 = "OS started"; 13 = "OS shut down"
    6005 = "event log started (boot)"; 6006 = "clean shutdown"; 6008 = "previous shutdown was UNEXPECTED"
    10000 = "network CONNECTED"; 10001 = "network DISCONNECTED"
    8001 = "wifi connected"; 8003 = "wifi DISCONNECTED"
}
$ev = @()
foreach ($p in $sysIds.Keys) {
    $ev += Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = $p; Id = $sysIds[$p]; StartTime = $since } -ErrorAction SilentlyContinue
}
$ev += Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-NetworkProfile/Operational'; Id = 10000, 10001; StartTime = $since } -ErrorAction SilentlyContinue
$ev += Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-WLAN-AutoConfig/Operational'; Id = 8001, 8003; StartTime = $since } -ErrorAction SilentlyContinue
# Adapter-level link drops are logged by the NIC driver, whose provider name
# varies by hardware, so match on the message instead.
$ev += Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 2, 3; StartTime = $since } -ErrorAction SilentlyContinue |
       Where-Object { $_.Message -match 'link is disconnected|link has been established|Network link' }

foreach ($e in ($ev | Sort-Object TimeCreated)) {
    $what = $labels[[int]$e.Id]
    $first = (($e.Message -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ($first -and $first.Length -gt 110) { $first = $first.Substring(0, 110) }
    if ($e.Id -eq 105 -and $e.ProviderName -eq 'Microsoft-Windows-Kernel-Power') {
        # Named fields, not positions: AcOnline says which way it switched.
        $d = @{}; ([xml]$e.ToXml()).Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
        $first = if ($d['AcOnline'] -eq 'true') { "now on AC" } else { "now on BATTERY" }
        if ($d['RemainingCapacity'] -and $d['FullChargeCapacity']) {
            $first += " ($([math]::Round(100 * [double]$d['RemainingCapacity'] / [double]$d['FullChargeCapacity']))%)"
        }
    }
    if (-not $what) { $what = $first }
    elseif ($e.Id -in 1, 105, 10000, 10001, 8003) { $what = "$what -- $first" }
    Say ("{0}  {1,-5} {2}" -f $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $e.Id, $what)
}
if (-not $ev) { Say "(no matching events -- unexpected; check the logs are enabled)" }
Say ""

# --- what wakes it / keeps it awake ------------------------------------------------
Say "=== last wake source ==="
powercfg /lastwake | ForEach-Object { Say "  $_" }
Say "=== wake timers ==="
powercfg /waketimers | ForEach-Object { Say "  $_" }
Say ""

# --- tailscale's own view ----------------------------------------------------------
$ts = "C:\Program Files\Tailscale\tailscale.exe"
if (Test-Path $ts) {
    Say "=== tailscale netcheck ==="
    & $ts netcheck 2>&1 | ForEach-Object { Say "  $_" }
}

New-Item -ItemType Directory -Path $outDir -Force | Out-Null
# WriteAllLines with an explicit no-BOM encoding: Set-Content -Encoding UTF8 on
# 5.1 adds a BOM.
[System.IO.File]::WriteAllLines($outFile, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host ""
Write-Host "written: $outFile"

try {
    powercfg /batteryreport /output (Join-Path $outDir "battery-report.html") | Out-Null
    Write-Host "battery report: $(Join-Path $outDir 'battery-report.html')  (see 'Recent usage' -- AC vs battery, active vs suspended)"
} catch { Write-Host "battery report skipped (needs an elevated prompt)" }
