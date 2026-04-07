@echo off
REM ============================================================
REM  Run-FleetScan-CHATWORKHORSE.bat
REM  Run this from anywhere on ChatWorkhorse to generate fleet reports
REM  Outputs go to OneDrive comfy-reports folder automatically
REM ============================================================

set COMFY=C:\ComfyUI_windows_portable\ComfyUI
set SCRIPTS=C:\repos\scripts\comfyui
set MODELS=C:\Users\pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare
set PNGDIR=C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\output
set OUTPUT=C:\Users\pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Work\comfy-reports

echo.
echo =============================================
echo  ComfyUI Fleet Scan -- CHATWORKHORSE
echo =============================================
echo.

cd /d "%COMFY%"

echo [1/3] Scanning custom nodes...
%SCRIPTS%\Get-CustomNodes.ps1 . -OutputDir "%OUTPUT%"

echo.
echo [2/3] Scanning models...
%SCRIPTS%\Get-Models.ps1 -ModelsPath "%MODELS%" -OutputDir "%OUTPUT%"

echo.
echo [3/3] Mapping workflows to models...
%SCRIPTS%\Get-WorkflowModelMap.ps1 ^
    -ModelsPath "%MODELS%" ^
    -WorkflowDir ".\user\default\workflows\" ^
    -PngDir "%PNGDIR%" ^
    -OutputDir "%OUTPUT%"

echo.
echo =============================================
echo  Done! Reports saved to:
echo  %OUTPUT%
echo  Now run comfy_fleet.py on your Mac.
echo =============================================
pause
