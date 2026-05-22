@echo off
REM ============================================================
REM  Run-FleetScan-IMAGEBEAST.bat
REM ============================================================

set COMFY=C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI
set SCRIPTS=C:\repos\scripts\comfyui
set MODELS=C:\ComfyUI_Models\models
set WFDIR=%COMFY%\user\default\workflows
set PNGDIR=C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\output
set OUTPUT=C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Work\comfy-reports

echo.
echo =============================================
echo  ComfyUI Fleet Scan -- IMAGEBEAST
echo =============================================
echo.

cd /d "%COMFY%"

echo [1/3] Scanning custom nodes...
powershell -ExecutionPolicy Bypass -File "%SCRIPTS%\Get-CustomNodes.ps1" . -OutputDir "%OUTPUT%"

echo.
echo [2/3] Scanning models...
powershell -ExecutionPolicy Bypass -File "%SCRIPTS%\Get-Models.ps1" -ModelsPath "%MODELS%" -OutputDir "%OUTPUT%"

echo.
echo [3/3] Mapping workflows to models...
powershell -ExecutionPolicy Bypass -File "%SCRIPTS%\Get-WorkflowModelMap.ps1" -ModelsPath "%MODELS%" -WorkflowDir "%WFDIR%" -PngDir "%PNGDIR%" -OutputDir "%OUTPUT%"

echo.
echo =============================================
echo  Done! Reports saved to:
echo  %OUTPUT%
echo  Now run comfy_fleet.py on your Mac.
echo =============================================
pause
