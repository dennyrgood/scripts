@echo off
REM Sets Ubuntu as the next one-time boot entry via bcdedit.
REM Run as Administrator.

echo Setting next boot to Ubuntu...
bcdedit /set {fwbootmgr} bootsequence {2cd49416-53a7-11f1-8a93-806e6f6e6963}
if %errorlevel% neq 0 (
    echo ERROR: bcdedit failed.
    pause
    exit /b 1
)
echo Done. Rebooting in 5 seconds...
timeout /t 5
shutdown /r /t 0
