# =============================================================================
# Get-Models.ps1
# Scans ComfyUI models directory and exports inventory to CSV
# Covers: checkpoints, loras, diffusion_models (unet), vae, controlnet,
#         embeddings, clip, ipadapter, upscale_models, and anything else found
# =============================================================================

param(
    [string]$ComfyRoot  = "C:\ComfyUI_easy\ComfyUI-Easy-Install\comfyui",
    [string]$ModelsPath  = "",   # Direct path to models dir, bypasses ComfyRoot\models
    [string]$OutputDir   = ".\comfy-reports",
    [switch]$NoFile     # Print summary to console only, skip CSV
)

# --- File extensions to capture ---
$modelExtensions = @('.safetensors', '.ckpt', '.pt', '.pth', '.bin', '.gguf')

# --- Setup ---
$timeStamp  = Get-Date -Format "yyyy-MM-dd_HHmm"
$hostName   = $env:COMPUTERNAME
$modelsPath = if ($ModelsPath) { $ModelsPath } else { Join-Path $ComfyRoot "models" }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  ComfyUI Models Inventory" -ForegroundColor Cyan
Write-Host "  Host : $hostName" -ForegroundColor Cyan
Write-Host "  Root : $ComfyRoot" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

if (!(Test-Path $modelsPath)) {
    Write-Host "ERROR: models path not found: $modelsPath" -ForegroundColor Red
    exit 1
}

# --- Scan ---
Write-Host "Scanning models..." -ForegroundColor Yellow

$allFiles = Get-ChildItem -Path $modelsPath -File -Recurse |
    Where-Object { $modelExtensions -contains $_.Extension.ToLower() } |
    Sort-Object FullName

Write-Host "Found $($allFiles.Count) model file(s)" -ForegroundColor Green
Write-Host ""

# Build records
$records = foreach ($file in $allFiles) {
    # Category = first subdirectory under models\
    $relativePath = $file.FullName.Substring($modelsPath.Length).TrimStart('\', '/')
    $parts        = $relativePath -split '[/\\]'
    $category     = if ($parts.Count -gt 1) { $parts[0] } else { "root" }

    # Sub-folder within category (e.g. models\loras\sdxl\file.safetensors -> sdxl)
    $subFolder    = if ($parts.Count -gt 2) { $parts[1..($parts.Count - 2)] -join '\' } else { "" }

    [PSCustomObject]@{
        category    = $category
        sub_folder  = $subFolder
        filename    = $file.Name
        extension   = $file.Extension.ToLower().TrimStart('.')
        size_gb     = [math]::Round($file.Length / 1GB, 3)
        size_mb     = [math]::Round($file.Length / 1MB, 1)
        size_bytes  = $file.Length
        file_date   = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        full_path   = $file.FullName
        relative_path = $relativePath
    }
}

# --- Console summary by category ---
$grouped = $records | Group-Object category | Sort-Object Name
foreach ($grp in $grouped) {
    $totalGB = ($grp.Group | Measure-Object size_gb -Sum).Sum
    Write-Host ("  {0,-28} {1,4} file(s)   {2,7:N2} GB" -f $grp.Name, $grp.Count, $totalGB)
}

$grandTotal = ($records | Measure-Object size_gb -Sum).Sum
Write-Host ""
Write-Host ("  {0,-28} {1,4} file(s)   {2,7:N2} GB" -f "TOTAL", $records.Count, $grandTotal) -ForegroundColor Green
Write-Host ""

# --- Save CSV ---
if (!$NoFile) {
    if (!(Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }
    $outFile = Join-Path $OutputDir "$hostName-Models-$timeStamp.csv"
    $records | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
    Write-Host "Saved: $outFile" -ForegroundColor Yellow
}
