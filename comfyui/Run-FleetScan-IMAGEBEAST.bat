@echo off
REM ============================================================
REM  Run-FleetScan-IMAGEBEAST.bat
REM  Run this from anywhere on ImageBeast to generate fleet reports
REM  Outputs go to OneDrive comfy-reports folder automatically
REM ============================================================

set COMFY=C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI
set SCRIPTS=C:\repos\scripts\comfyui
set OUTPUT=C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Work\comfy-reports

echo.
echo =============================================
echo  ComfyUI Fleet Scan -- IMAGEBEAST
echo =============================================
echo.

cd /d "%COMFY%"

echo [1/3] Scanning custom nodes...
%SCRIPTS%\Get-CustomNodes.ps1 . -OutputDir "%OUTPUT%"

echo.
echo [2/3] Scanning models...
%SCRIPTS%\Get-Models.ps1 -ModelsPath "C:\ComfyUI_Models\models" -OutputDir "%OUTPUT%"

echo.
echo [3/3] Mapping workflows to models...
%SCRIPTS%\Get-WorkflowModelMap.ps1 ^
    -ModelsPath "C:\ComfyUI_Models\models" ^
    -WorkflowDir ".\user\default\workflows\" ^
    -PngDir "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\output\" ^
    -OutputDir "%OUTPUT%"

echo.
echo =============================================
echo  Done! Reports saved to:
echo  %OUTPUT%
echo  Now run comfy_fleet.py on your Mac.
echo =============================================
pause
