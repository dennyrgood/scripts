@echo off
REM Sets Windows Boot Manager as the next one-time boot entry.
REM Run as Administrator.

echo Setting next boot to Windows...
bcdedit /set {fwbootmgr} bootsequence {bootmgr}
if %errorlevel% neq 0 (
    echo ERROR: bcdedit failed.
    pause
    exit /b 1
)
echo Done. Rebooting in 5 seconds...
timeout /t 5
shutdown /r /t 0
