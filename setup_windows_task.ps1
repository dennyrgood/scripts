# Windows Setup — run this ONCE in PowerShell (as normal user, not admin)
# It registers a Task Scheduler job to run the monitor every 30 minutes.
#
# FIRST: Edit the $scriptPath below to point to where you saved the .pyw file.

$scriptPath = "$env:USERPROFILE\scripts\onedrive_monitor_windows.pyw"
$pythonPath = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source

if (-not $pythonPath) {
    # Try common locations
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\pythonw.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\pythonw.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python310\pythonw.exe",
        "C:\Python312\pythonw.exe"
    )
    $pythonPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $pythonPath) {
    Write-Error "Could not find pythonw.exe. Install Python and try again."
    exit 1
}

Write-Host "Using Python: $pythonPath"
Write-Host "Script: $scriptPath"

$action  = New-ScheduledTaskAction -Execute $pythonPath -Argument "`"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 30) `
           -Once -At (Get-Date) -RepetitionDuration ([TimeSpan]::MaxValue)
$trigger2 = New-ScheduledTaskTrigger -AtLogOn

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName "OneDriveSyncMonitor" `
    -Action $action `
    -Trigger @($trigger, $trigger2) `
    -Settings $settings `
    -Description "Monitors OneDrive sync health and alerts if stuck" `
    -Force

Write-Host "`n✅ Task registered! It will run every 30 minutes and at logon."
Write-Host "   To test immediately: Start-ScheduledTask -TaskName 'OneDriveSyncMonitor'"
Write-Host "   To remove:           Unregister-ScheduledTask -TaskName 'OneDriveSyncMonitor' -Confirm:`$false"
