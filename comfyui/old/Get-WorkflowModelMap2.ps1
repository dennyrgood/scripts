# =============================================================================
# Get-WorkflowModelMap.ps1
#
# Scans ComfyUI workflow files (JSON + PNG with embedded workflow metadata)
# and maps every model reference found back to the actual model file on disk.
#
# Outputs:
#   workflow_model_map.csv  - one row per (workflow, model) pair
#   model_usage_summary.csv - one row per model: how many workflows use it
#   unused_models.csv       - models on disk never referenced in any workflow
#   missing_models.csv      - models referenced in workflows but not on disk
#   workflow_map_summary.txt - human-readable summary
#
# Requirements:
#   PowerShell 5.1+ (ships with Windows 10/11)
#   No extra modules needed - PNG metadata is read natively.
# =============================================================================

param(
    [string]$ComfyRoot    = "C:\ComfyUI_easy\ComfyUI-Easy-Install\comfyui",
    [string]$WorkflowDir  = "",      # Defaults to $ComfyRoot\user\default\workflows
    [string]$OutputDir    = ".\comfy-reports",
    [switch]$IncludePng,             # Also scan PNG files for embedded workflow data
    [switch]$NoFile                  # Skip file output, print summary only
)

# ---------------------------------------------------------------------------
# 0. Setup
# ---------------------------------------------------------------------------
$timeStamp   = Get-Date -Format "yyyy-MM-dd_HHmm"
$hostName    = $env:COMPUTERNAME
$modelsPath  = Join-Path $ComfyRoot "models"

if (!$WorkflowDir) {
    # Default ComfyUI workflow location
    $WorkflowDir = Join-Path $ComfyRoot "user\default\workflows"
    # Fallback: older installs put them here
    if (!(Test-Path $WorkflowDir)) {
        $WorkflowDir = Join-Path $ComfyRoot "workflows"
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  ComfyUI Workflow -> Model Map" -ForegroundColor Cyan
Write-Host "  Host      : $hostName" -ForegroundColor Cyan
Write-Host "  ComfyRoot : $ComfyRoot" -ForegroundColor Cyan
Write-Host "  Workflows : $WorkflowDir" -ForegroundColor Cyan
Write-Host "  Models    : $modelsPath" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Validate paths
foreach ($p in @($modelsPath, $WorkflowDir)) {
    if (!(Test-Path $p)) {
        Write-Host "ERROR: Path not found: $p" -ForegroundColor Red
        exit 1
    }
}

# ---------------------------------------------------------------------------
# 1. Build model inventory (filename -> full_path + category)
# ---------------------------------------------------------------------------
Write-Host "Building model inventory..." -ForegroundColor Yellow

$modelExtensions = @('.safetensors', '.ckpt', '.pt', '.pth', '.bin', '.gguf')

$modelInventory = @{}   # key = lowercase filename, value = PSObject

Get-ChildItem -Path $modelsPath -File -Recurse |
    Where-Object { $modelExtensions -contains $_.Extension.ToLower() } |
    ForEach-Object {
        $file     = $_
        $relPath  = $file.FullName.Substring($modelsPath.Length).TrimStart('\','/')
        $parts    = $relPath -split '[/\\]'
        $category = if ($parts.Count -gt 1) { $parts[0] } else { "root" }

        $key = $file.Name.ToLower()
        # If two files share the same name in different folders, keep both
        # by making the key unique with a counter
        if ($modelInventory.ContainsKey($key)) {
            $key = "$key|$($file.FullName.ToLower())"
        }

        $modelInventory[$key] = [PSCustomObject]@{
            filename      = $file.Name
            category      = $category
            full_path     = $file.FullName
            relative_path = $relPath
            size_gb       = [math]::Round($file.Length / 1GB, 3)
        }
    }

Write-Host "  Found $($modelInventory.Count) model file(s) on disk" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Helper: resolve a model reference string to the inventory entry
# ---------------------------------------------------------------------------
function Resolve-ModelRef {
    param([string]$Ref)

    if (!$Ref) { return $null }

    # Normalize slashes and get just the filename
    $normalized = $Ref -replace '\\', '/'
    $basename   = ($normalized -split '/')[-1].ToLower()

    # 1. Exact filename match
    if ($modelInventory.ContainsKey($basename)) {
        return $modelInventory[$basename]
    }

    # 2. Check keys that may have been made unique (name|path)
    $hit = $modelInventory.Keys | Where-Object { $_ -like "$basename|*" } | Select-Object -First 1
    if ($hit) { return $modelInventory[$hit] }

    # 3. Partial path match - ref may include a sub-folder e.g. "sdxl/model.safetensors"
    foreach ($entry in $modelInventory.Values) {
        if ($entry.relative_path.ToLower().EndsWith($normalized.ToLower())) {
            return $entry
        }
    }

    return $null   # Not found on disk
}

# ---------------------------------------------------------------------------
# 2. Node keys that typically hold model filenames in ComfyUI
# ---------------------------------------------------------------------------
$modelKeys = @(
    'ckpt_name',        # CheckpointLoaderSimple
    'lora_name',        # LoraLoader
    'model_name',       # Various loaders
    'vae_name',         # VAELoader
    'control_net_name', # ControlNetLoader
    'unet_name',        # UNETLoader (Flux etc.)
    'clip_name',        # CLIPLoader
    'clip_name1',       # DualCLIPLoader
    'clip_name2',       # DualCLIPLoader
    'ipadapter_file',   # IPAdapter
    'weight_name',      # Some LoRA loaders
    'file'              # Generic
)

# ---------------------------------------------------------------------------
# Helper: extract model references from a workflow dict (parsed JSON)
# ---------------------------------------------------------------------------
function Get-RefsFromWorkflow {
    param($workflow)

    $refs = [System.Collections.Generic.List[PSObject]]::new()

    if ($null -eq $workflow) { return $refs }

    # --- Format A: { "nodes": [ {id, type, widgets_values, inputs, ...} ] }
    # --- Format B: { "1": { class_type, inputs: {ckpt_name:...} }, "2": ... }

    $nodesList = $null

    if ($workflow.PSObject.Properties['nodes']) {
        $nodesList = $workflow.nodes
    } else {
        # Try dict-of-nodes format (API/prompt format)
        $nodesList = $workflow.PSObject.Properties.Value |
            Where-Object { $_ -is [PSCustomObject] -and $_.PSObject.Properties['class_type'] }
    }

    if ($null -eq $nodesList) { return $refs }

    foreach ($node in $nodesList) {
        if ($null -eq $node) { continue }

        # Determine a human-readable node label
        $classType = ""
        $nodeTitle = ""

        if ($node.PSObject.Properties['class_type'])  { $classType = $node.class_type }
        if ($node.PSObject.Properties['type'])         { $classType = $node.type }
        if ($node.PSObject.Properties['_meta']) {
            $nodeTitle = $node._meta.title
        }
        if (!$nodeTitle -and $node.PSObject.Properties['title']) { $nodeTitle = $node.title }
        if (!$nodeTitle) { $nodeTitle = $classType }

        $label = if ($nodeTitle -and $nodeTitle -ne $classType) {
            "$nodeTitle ($classType)"
        } else { $classType }

        # --- widgets_values (newer graph format) ---
        if ($node.PSObject.Properties['widgets_values']) {
            $wv = $node.widgets_values
            if ($wv -is [System.Collections.IEnumerable]) {
                foreach ($v in $wv) {
                    if ($v -is [string] -and $v -match '\.(safetensors|ckpt|pt|pth|bin|gguf)$') {
                        $refs.Add([PSCustomObject]@{ node_label = $label; model_ref = $v })
                    }
                }
            }
        }

        # --- inputs dict (API/prompt format and some nodes) ---
        if ($node.PSObject.Properties['inputs']) {
            $inputs = $node.inputs
            foreach ($key in $modelKeys) {
                if ($inputs.PSObject.Properties[$key]) {
                    $v = $inputs.$key
                    if ($v -is [string] -and $v -match '\.(safetensors|ckpt|pt|pth|bin|gguf)$') {
                        $refs.Add([PSCustomObject]@{ node_label = $label; model_ref = $v })
                    }
                }
            }
        }
    }

    return $refs
}

# ---------------------------------------------------------------------------
# Helper: read PNG tEXt chunk to get embedded workflow JSON
# ---------------------------------------------------------------------------
function Get-WorkflowFromPng {
    param([string]$PngPath)

    try {
        $bytes = [System.IO.File]::ReadAllBytes($PngPath)
        $text  = [System.Text.Encoding]::UTF8.GetString($bytes)

        # ComfyUI embeds workflow under "workflow" or "prompt" tEXt key
        foreach ($marker in @('workflow', 'prompt')) {
            $idx = $text.IndexOf($marker + '{')
            if ($idx -ge 0) {
                $jsonStart = $text.IndexOf('{', $idx)
                if ($jsonStart -ge 0) {
                    # Walk forward to find the matching closing brace
                    $depth  = 0
                    $end    = $jsonStart
                    for ($i = $jsonStart; $i -lt $bytes.Length; $i++) {
                        if ($bytes[$i] -eq 0x7B) { $depth++ }
                        elseif ($bytes[$i] -eq 0x7D) {
                            $depth--
                            if ($depth -eq 0) { $end = $i; break }
                        }
                    }
                    $jsonStr = $text.Substring($jsonStart, $end - $jsonStart + 1)
                    return $jsonStr | ConvertFrom-Json -ErrorAction SilentlyContinue
                }
            }
        }
    } catch { }

    return $null
}

# ---------------------------------------------------------------------------
# 3. Scan workflow files
# ---------------------------------------------------------------------------
Write-Host "Scanning workflow files in: $WorkflowDir" -ForegroundColor Yellow

$workflowFiles = Get-ChildItem -Path $WorkflowDir -File -Recurse |
    Where-Object {
        $_.Extension -eq '.json' -or ($IncludePng -and $_.Extension -eq '.png')
    }

Write-Host "  Found $($workflowFiles.Count) workflow file(s)" -ForegroundColor Green
Write-Host ""

$mapRows     = [System.Collections.Generic.List[PSObject]]::new()
$allModelRefs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

$processed  = 0
$skipped    = 0

foreach ($wf in $workflowFiles) {
    $workflow = $null

    if ($wf.Extension -eq '.json') {
        try {
            $content  = Get-Content -Path $wf.FullName -Raw -Encoding UTF8
            $workflow = $content | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Host "  SKIP (bad JSON): $($wf.Name)" -ForegroundColor DarkGray
            $skipped++
            continue
        }
    } elseif ($wf.Extension -eq '.png') {
        $workflow = Get-WorkflowFromPng -PngPath $wf.FullName
        if (!$workflow) {
            $skipped++
            continue
        }
    }

    $refs = Get-RefsFromWorkflow -workflow $workflow

    if ($refs.Count -eq 0) {
        $skipped++
        continue
    }

    $processed++
    $wfRel = $wf.FullName.Replace($WorkflowDir, '').TrimStart('\','/')

    foreach ($r in $refs) {
        $resolved = Resolve-ModelRef -Ref $r.model_ref
        $null     = $allModelRefs.Add($r.model_ref.ToLower() -replace '\\','/')

        $mapRows.Add([PSCustomObject]@{
            workflow_file     = $wfRel
            workflow_dir      = $wf.DirectoryName
            workflow_modified = $wf.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            node_label        = $r.node_label
            model_ref         = $r.model_ref
            model_filename    = if ($resolved) { $resolved.filename }  else { "(not found on disk)" }
            model_category    = if ($resolved) { $resolved.category }  else { "" }
            model_path        = if ($resolved) { $resolved.full_path } else { "" }
            model_size_gb     = if ($resolved) { $resolved.size_gb }   else { "" }
            on_disk           = if ($resolved) { "YES" } else { "NO" }
        })
    }
}

Write-Host "  Processed : $processed workflow(s)" -ForegroundColor Green
Write-Host "  Skipped   : $skipped (no model refs or unreadable)" -ForegroundColor DarkGray
Write-Host ""

# ---------------------------------------------------------------------------
# 4. Build usage summary (per model)
# ---------------------------------------------------------------------------
$usageSummary = $mapRows |
    Where-Object { $_.on_disk -eq "YES" } |
    Group-Object model_filename |
    ForEach-Object {
        $grp        = $_
        $first      = $grp.Group[0]
        $wfList     = ($grp.Group | Select-Object -ExpandProperty workflow_file -Unique | Sort-Object)
        [PSCustomObject]@{
            model_filename    = $grp.Name
            model_category    = $first.model_category
            model_size_gb     = $first.model_size_gb
            workflow_count    = ($wfList).Count
            workflows         = $wfList -join " | "
        }
    } | Sort-Object -Property workflow_count -Descending

# ---------------------------------------------------------------------------
# 5. Unused models (on disk, never referenced)
# ---------------------------------------------------------------------------
$unusedModels = $modelInventory.Values | Where-Object {
    $fn = $_.filename.ToLower()
    -not ($allModelRefs | Where-Object { $_ -like "*$fn" })
} | Sort-Object category, filename

# ---------------------------------------------------------------------------
# 6. Missing models (referenced in workflows, not on disk)
# ---------------------------------------------------------------------------
$missingModels = $mapRows |
    Where-Object { $_.on_disk -eq "NO" } |
    Select-Object model_ref, workflow_file, node_label -Unique |
    Sort-Object model_ref

# ---------------------------------------------------------------------------
# 7. Console output
# ---------------------------------------------------------------------------
Write-Host "--- Model Usage Summary (top 20) ---" -ForegroundColor Cyan
$usageSummary | Select-Object -First 20 |
    Format-Table model_filename, model_category, model_size_gb, workflow_count -AutoSize

if ($missingModels.Count -gt 0) {
    Write-Host ""
    Write-Host "--- Missing Models (referenced but NOT on disk): $($missingModels.Count) ---" -ForegroundColor Red
    $missingModels | Select-Object -First 10 | Format-Table model_ref, workflow_file -AutoSize
}

Write-Host ""
Write-Host "--- Unused Models (on disk but NEVER referenced): $($unusedModels.Count) ---" -ForegroundColor Yellow
$unusedModels | Select-Object -First 10 |
    Format-Table filename, category, size_gb -AutoSize

# ---------------------------------------------------------------------------
# 8. Save files
# ---------------------------------------------------------------------------
if (!$NoFile) {
    if (!(Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }

    $prefix = "$OutputDir\$hostName-WorkflowMap-$timeStamp"

    $mapRows      | Export-Csv "$prefix-full_map.csv"         -NoTypeInformation -Encoding UTF8
    $usageSummary | Export-Csv "$prefix-model_usage.csv"      -NoTypeInformation -Encoding UTF8
    $unusedModels | Export-Csv "$prefix-unused_models.csv"    -NoTypeInformation -Encoding UTF8
    $missingModels| Export-Csv "$prefix-missing_models.csv"   -NoTypeInformation -Encoding UTF8

    # Human-readable summary
    $summaryLines = @(
        "ComfyUI Workflow -> Model Map Summary",
        "Host    : $hostName",
        "Date    : $timeStamp",
        "=" * 60,
        "",
        "MODELS ON DISK       : $($modelInventory.Count)",
        "WORKFLOW FILES       : $processed (with model refs)",
        "UNIQUE MODEL REFS    : $($allModelRefs.Count)",
        "MODELS USED          : $($usageSummary.Count)",
        "MODELS UNUSED        : $($unusedModels.Count)",
        "MISSING (not on disk): $($missingModels.Count)",
        "",
        "=" * 60,
        "TOP MODELS BY WORKFLOW COUNT",
        "-" * 60
    )
    foreach ($row in ($usageSummary | Select-Object -First 30)) {
        $summaryLines += "  [{0,2} workflows]  {1}  ({2})  {3} GB" -f `
            $row.workflow_count, $row.model_filename, $row.model_category, $row.model_size_gb
    }

    if ($unusedModels.Count -gt 0) {
        $unusedGB = ($unusedModels | Measure-Object size_gb -Sum).Sum
        $summaryLines += ""
        $summaryLines += "=" * 60
        $summaryLines += "UNUSED MODELS  ($($unusedModels.Count) files  |  $([math]::Round($unusedGB,2)) GB wasted)"
        $summaryLines += "-" * 60
        foreach ($m in $unusedModels) {
            $summaryLines += "  {0,-55} {1} GB  [{2}]" -f $m.filename, $m.size_gb, $m.category
        }
    }

    if ($missingModels.Count -gt 0) {
        $summaryLines += ""
        $summaryLines += "=" * 60
        $summaryLines += "MISSING MODELS (referenced in workflows but not on disk)"
        $summaryLines += "-" * 60
        foreach ($m in ($missingModels | Select-Object model_ref -Unique)) {
            $summaryLines += "  $($m.model_ref)"
        }
    }

    $summaryLines | Out-File "$prefix-summary.txt" -Encoding UTF8

    Write-Host "Output files:" -ForegroundColor Yellow
    Write-Host "  $prefix-full_map.csv"
    Write-Host "  $prefix-model_usage.csv"
    Write-Host "  $prefix-unused_models.csv"
    Write-Host "  $prefix-missing_models.csv"
    Write-Host "  $prefix-summary.txt"
    Write-Host ""
    Write-Host "Done!" -ForegroundColor Green
}
