# ============================================================
#  fleet-check.ps1  |  Quick service health check
#  Run on any fleet machine - auto-detects which one by hostname
#  Usage: .\fleet-check.ps1
# ============================================================

$host.UI.RawUI.WindowTitle = "Fleet Check"
$machine = $env:COMPUTERNAME.ToUpper()
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  FLEET QUICK CHECK  |  $machine  |  $timestamp" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# ---- Helper functions ----

function Check-Port {
    param([string]$Label, [string]$HostName, [int]$Port, [int]$Timeout = 1000)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $conn = $tcp.BeginConnect($HostName, $Port, $null, $null)
        $ok = $conn.AsyncWaitHandle.WaitOne($Timeout, $false)
        $tcp.Close()
        if ($ok) {
            Write-Host "  [OK]  $Label (port $Port)" -ForegroundColor Green
            return $true
        }
    } catch {}
    Write-Host "  [--]  $Label (port $Port) NOT responding" -ForegroundColor Red
    return $false
}

function Check-Process {
    param([string]$Label, [string]$ProcessName)
    $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($p) {
        Write-Host "  [OK]  $Label (process: $ProcessName)" -ForegroundColor Green
        return $true
    }
    Write-Host "  [--]  $Label (process: $ProcessName) NOT running" -ForegroundColor Red
    return $false
}

function Check-URL {
    param([string]$Label, [string]$URL, [int]$Timeout = 4)
    try {
        $resp = Invoke-WebRequest -Uri $URL -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
        if ($resp.StatusCode -lt 400) {
            Write-Host "  [OK]  $Label -> $URL ($($resp.StatusCode))" -ForegroundColor Green
            return $true
        }
    } catch {}
    Write-Host "  [--]  $Label -> $URL UNREACHABLE" -ForegroundColor Red
    return $false
}

function Section {
    param([string]$Title)
    Write-Host "  --- $Title ---" -ForegroundColor Yellow
}

# ---- Tailscale ----

Section "Tailscale"
$tsSvc = Get-Service -Name "Tailscale" -ErrorAction SilentlyContinue
if ($tsSvc -and $tsSvc.Status -eq "Running") {
    try {
        $tsLocal = & tailscale status 2>&1 | Select-String "^\s*100\." | Select-Object -First 1
        $localIP = if ($tsLocal) { ($tsLocal -replace '\s+', ' ').Trim().Split(' ')[0] } else { "unknown" }
        Write-Host "  [OK]  Tailscale running  |  $machine = $localIP" -ForegroundColor Green
    } catch {
        Write-Host "  [OK]  Tailscale running  (tailscale CLI not in PATH)" -ForegroundColor Green
    }
} elseif ($tsSvc) {
    Write-Host "  [--]  Tailscale service exists but status: $($tsSvc.Status)" -ForegroundColor Red
} else {
    Write-Host "  [--]  Tailscale service NOT found" -ForegroundColor Red
}

# ---- Cloudflared ----

Section "Cloudflare Tunnel"
Check-Process "cloudflared" "cloudflared" | Out-Null

# ---- Machine-specific service checks ----

switch -Wildcard ($machine) {

    # ============================================================
    "AMSTERDAMDESK*" {
        Section "Ollama"
        Check-Port "Ollama API" "localhost" 11434 | Out-Null

        Section "OpenWebUI  (chat.ldmathes.cc)"
        Check-Port "OpenWebUI" "localhost" 8080 | Out-Null

        Section "Flask APIs"
        Check-Port "Flask api.ldmathes.cc"        "localhost" 5000 | Out-Null
        Check-Port "Flask api-edit.ldmathes.cc"   "localhost" 5001 | Out-Null
        Check-Port "Flask weatherproxy"            "localhost" 5005 | Out-Null

        Section "Fleet Status"
        Check-Port "Fleet Status dashboard" "localhost" 5010 | Out-Null
    }

    # ============================================================
    "CHATWORKHORSE" {
        Section "Ollama  (Tailscale-only)"
        Check-Port "Ollama API" "localhost" 11434 | Out-Null

        Section "OpenWebUI  (talk.ldmathes.cc)"
        Check-Port "OpenWebUI" "localhost" 8080 | Out-Null

        Section "ComfyUI  (clips.ldmathes.cc)"
        Check-Port "ComfyUI" "localhost" 8188 | Out-Null

        Section "Fleet Status  (fleet-bkp.ldmathes.cc)"
        Check-Port "Fleet Status dashboard" "localhost" 5010 | Out-Null

        Section "NVMe Health Warning"
        Write-Host "  [!!]  ChatWorkHorse NVMe (Micron 2200s) is KNOWN FAILING" -ForegroundColor Magenta
        Write-Host "        If system rebooted and is unresponsive -> physical power cycle required" -ForegroundColor DarkGray
    }

    # ============================================================
    "IMAGEBEAST" {
        Section "ComfyUI  (image.ldmathes.cc)"
        Check-Port "ComfyUI" "localhost" 8188 | Out-Null

        Section "Ollama  (Tailscale-only)"
        Check-Port "Ollama API" "localhost" 11434 | Out-Null

        Section "RAM Note"
        $ram = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB
        Write-Host "  [i]   Detected RAM: $([math]::Round($ram))GB" -ForegroundColor Cyan
        if ($ram -lt 64) {
            Write-Host "  [!!]  Still on 32GB DDR5 (temp). ACE MAX + 128GB kit not yet installed." -ForegroundColor Magenta
        } else {
            Write-Host "  [OK]  128GB kit appears installed" -ForegroundColor Green
        }
    }

    # ============================================================
    "TRAVELBEAST" {
        Section "ComfyUI  (local)"
        Check-Port "ComfyUI" "localhost" 8188 | Out-Null

        Section "Ollama  (Tailscale-only)"
        Check-Port "Ollama API" "localhost" 11434 | Out-Null

        Section "OneDrive Sync"
        $od = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
        if ($od) {
            Write-Host "  [OK]  OneDrive running" -ForegroundColor Green
            Write-Host "        Reminder: OneDrive sync must complete before launching ComfyUI" -ForegroundColor DarkGray
        } else {
            Write-Host "  [--]  OneDrive NOT running" -ForegroundColor Red
            Write-Host "  [!!]  Do NOT launch ComfyUI until OneDrive sync completes" -ForegroundColor Magenta
        }
    }

    # ============================================================
    default {
        Write-Host "  [??]  Unknown machine: $machine" -ForegroundColor Magenta
        Write-Host "        Running generic checks only (Tailscale + cloudflared above)" -ForegroundColor DarkGray

        Section "Common Ports (generic)"
        Check-Port "Ollama"    "localhost" 11434 | Out-Null
        Check-Port "ComfyUI"   "localhost" 8188  | Out-Null
        Check-Port "OpenWebUI" "localhost" 3000  | Out-Null
    }
}

# ---- Disk space quick check ----

Section "Disk Space"
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } | ForEach-Object {
    $usedGB  = [math]::Round($_.Used / 1GB, 1)
    $freeGB  = [math]::Round($_.Free / 1GB, 1)
    $totalGB = [math]::Round(($_.Used + $_.Free) / 1GB, 1)
    $pct     = [math]::Round(($_.Used / ($_.Used + $_.Free)) * 100)
    $color   = if ($pct -gt 90) { "Red" } elseif ($pct -gt 75) { "Yellow" } else { "Green" }
    Write-Host ("  [{0,3}%]  {1}:\  {2}GB used of {3}GB  ({4}GB free)" -f $pct, $_.Name, $usedGB, $totalGB, $freeGB) -ForegroundColor $color
}

# ---- Done ----

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Done.  $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Read-Host
