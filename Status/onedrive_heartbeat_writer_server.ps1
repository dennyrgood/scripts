# onedrive_heartbeat_writer_server.ps1
# Fleet FLEET_OPS - Heartbeat + Machine Info Writer
# Writes heartbeat_{host}.txt and machine_info_{host}.json to OneDrive _sync_monitor
# Runs on all Windows fleet machines via Task Scheduler
# Last updated: 2026-06-15 16:58 UTC

# ── Hostname resolution ────────────────────────────────────────

$hostnameMap = @{
    "amsterdamdeskto" = "amsterdamdesktop"
}

$rawHost = $env:COMPUTERNAME.ToLower()
$checkerHost = if ($hostnameMap.ContainsKey($rawHost)) { $hostnameMap[$rawHost] } else { $rawHost }

# ── OneDrive path resolution ───────────────────────────────────

$onedrivePath = if ($env:OneDriveConsumer) { $env:OneDriveConsumer }
                elseif ($env:OneDrive)         { $env:OneDrive }
                else                           { Join-Path $env:USERPROFILE "OneDrive" }

$heartbeatDir  = Join-Path $onedrivePath "_sync_monitor"
$heartbeatFile = Join-Path $heartbeatDir "heartbeat_$checkerHost.txt"
$infoFile      = Join-Path $heartbeatDir "machine_info_$checkerHost.json"

# ── Ensure directory exists ────────────────────────────────────

New-Item -ItemType Directory -Force -Path $heartbeatDir | Out-Null

# ── Helper: run PowerShell expression, return $null on error ──

function Safe-Get {
    param([scriptblock]$block)
    try { & $block } catch { $null }
}

# ── Helper: format datetime as local "Jun 9 23:35" ────────────

function Format-LocalDT {
    param([datetime]$dt)
    if ($null -eq $dt) { return $null }
    $local = $dt.ToLocalTime()
    return $local.ToString("MMM d HH:mm")
}

# ── Collect Windows-specific info via CIM/registry ────────────

function Get-MachineInfo {

    # OS / build
    $os      = Safe-Get { Get-CimInstance Win32_OperatingSystem }
    $osBuild = if ($os) { $os.BuildNumber } else { $null }
    $osVer   = if ($os) { "$($os.Version).$osBuild" } else { $null }

    # Last reboot
    $lastReboot = if ($os) { Format-LocalDT $os.LastBootUpTime } else { $null }

    # Last WU-triggered reboot (Event ID 1074, source TrustedInstaller)
    $lastWUReboot = Safe-Get {
        $ev = Get-WinEvent -LogName System -MaxEvents 5000 -ErrorAction SilentlyContinue |
              Where-Object { $_.Id -eq 1074 -and $_.Message -like "*TrustedInstaller*" } |
              Select-Object -First 1
        if ($ev) { Format-LocalDT $ev.TimeCreated } else { $null }
    }

    # Last installed update (date + KB)
    $lastWU     = $null
    $lastWUKB   = $null
    $wu = Safe-Get {
        Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
    }
    if ($wu) {
        $lastWU   = Format-LocalDT $wu.InstalledOn
        $lastWUKB = $wu.HotFixID
    }

    # Pending reboot — check common registry keys
    $pendingReboot = $false
    $pendingReboot = $pendingReboot -or (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending")
    $pendingReboot = $pendingReboot -or (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
    $pendingReboot = $pendingReboot -or (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations")

    # RAM
    $ramTotalGB = $null
    $ramUsedGB  = $null
    if ($os) {
        $ramTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $ramUsedGB  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
    }

    # CPU % (2-second sample)
    $cpuPercent = Safe-Get {
        $c = Get-CimInstance Win32_Processor
        if ($c) { [math]::Round(($c | Measure-Object -Property LoadPercentage -Average).Average, 0) } else { $null }
    }

    # Disks — all local fixed drives
    $disks = @()
    $drives = Safe-Get { Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" }
    if ($drives) {
        foreach ($d in $drives) {
            $totalGB = [math]::Round($d.Size / 1GB, 1)
            $freeGB  = [math]::Round($d.FreeSpace / 1GB, 1)
            $usedGB  = [math]::Round($totalGB - $freeGB, 1)
            $disks  += @{
                drive    = $d.DeviceID
                used_gb  = $usedGB
                total_gb = $totalGB
                free_gb  = $freeGB
            }
        }
    }

    return @{
        host            = $checkerHost
        timestamp_utc   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        os_build        = $osVer
        last_reboot     = $lastReboot
        last_wu_reboot  = $lastWUReboot
        last_wu_date    = $lastWU
        last_wu_kb      = $lastWUKB
        pending_reboot  = $pendingReboot
        ram_total_gb    = $ramTotalGB
        ram_used_gb     = $ramUsedGB
        cpu_percent     = $cpuPercent
        disks           = $disks
    }
}

# ── Main loop ─────────────────────────────────────────────────

$writeInterval = 150  # seconds — matches heartbeat cadence

while ($true) {

    try {
        # 1. Write heartbeat timestamp (existing behaviour, unchanged)
        (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.ffffffK") | Set-Content -Path $heartbeatFile -Encoding UTF8 -NoNewline
    } catch { <# silently continue #> }

    try {
        # 2. Collect and write machine info sidecar
        $info    = Get-MachineInfo
        $infoJson = $info | ConvertTo-Json -Depth 5 -Compress:$false
        Set-Content -Path $infoFile -Value $infoJson -Encoding UTF8
    } catch { <# silently continue #> }

    Start-Sleep -Seconds $writeInterval
}
