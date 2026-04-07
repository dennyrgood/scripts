# =============================================================================
# Get-WorkflowModelMap.ps1
#
# Scans ComfyUI workflow files (JSON + PNG with embedded workflow metadata)
# and maps every model reference found back to the actual model file on disk.
#
# Outputs:
#   *-full_map.csv        - one row per (workflow, model) pair
#   *-model_usage.csv     - one row per model: how many workflows use it
#   *-unused_models.csv   - models on disk never referenced in any workflow
#   *-missing_models.csv  - models referenced in workflows but not on disk
#   *-summary.txt         - human-readable summary
#
# Requirements: PowerShell 5.1+ (Windows 10/11). No extra modules needed.
# =============================================================================

param(
    [string]$ComfyRoot   = "C:\ComfyUI_easy\ComfyUI-Easy-Install\comfyui",
    [string]$WorkflowDir = "",       # JSON workflow folder (defaults to ComfyRoot\user\default\workflows)
    [string]$PngDir      = "",       # Separate folder to scan for PNG files with embedded workflows
    [string]$ModelsPath  = "",       # Override default models dir (e.g. -ModelsPath "D:\AI\models")
    [string]$OutputDir   = ".\comfy-reports",
    [switch]$NoFile
)

# ---------------------------------------------------------------------------
# 0. Setup
# ---------------------------------------------------------------------------
$timeStamp  = Get-Date -Format "yyyy-MM-dd_HHmm"
$hostName   = $env:COMPUTERNAME
$modelsPath = if ($ModelsPath) { $ModelsPath } else { Join-Path $ComfyRoot "models" }

if (!$WorkflowDir) {
    $WorkflowDir = Join-Path $ComfyRoot "user\default\workflows"
    if (!(Test-Path $WorkflowDir)) {
        $WorkflowDir = Join-Path $ComfyRoot "workflows"
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  ComfyUI Workflow -> Model Map"              -ForegroundColor Cyan
Write-Host "  Host      : $hostName"                      -ForegroundColor Cyan
Write-Host "  Workflows : $WorkflowDir"                   -ForegroundColor Cyan
if ($PngDir) {
Write-Host "  PNG Dir   : $PngDir"                        -ForegroundColor Cyan
}
Write-Host "  Models    : $modelsPath"                    -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

foreach ($p in @($modelsPath, $WorkflowDir)) {
    if (!(Test-Path $p)) {
        Write-Host "ERROR: Path not found: $p" -ForegroundColor Red
        exit 1
    }
}
if ($PngDir -and !(Test-Path $PngDir)) {
    Write-Host "ERROR: PngDir not found: $PngDir" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# 1. Build model inventory
# ---------------------------------------------------------------------------
Write-Host "Building model inventory..." -ForegroundColor Yellow

$modelExtensions = @('.safetensors', '.ckpt', '.pt', '.pth', '.bin', '.gguf')
$modelInventory  = @{}

Get-ChildItem -Path $modelsPath -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $modelExtensions -contains $_.Extension.ToLower() } |
    ForEach-Object {
        $file     = $_
        $relPath  = $file.FullName.Substring($modelsPath.Length).TrimStart('\','/')
        $parts    = $relPath -split '[/\\]'
        $category = if ($parts.Count -gt 1) { $parts[0] } else { "root" }
        $key      = $file.Name.ToLower()
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
# Helper: resolve model reference to inventory entry
# ---------------------------------------------------------------------------
function Resolve-ModelRef {
    param([string]$Ref)
    if (!$Ref) { return $null }
    $normalized = $Ref -replace '\\', '/'
    $basename   = ($normalized -split '/')[-1].ToLower()
    if ($modelInventory.ContainsKey($basename)) { return $modelInventory[$basename] }
    $hit = $modelInventory.Keys | Where-Object { $_ -like "$basename|*" } | Select-Object -First 1
    if ($hit) { return $modelInventory[$hit] }
    foreach ($entry in $modelInventory.Values) {
        if ($entry.relative_path.ToLower().EndsWith($normalized.ToLower())) { return $entry }
    }
    return $null
}

# ---------------------------------------------------------------------------
# 2. Model input keys used by ComfyUI nodes
# ---------------------------------------------------------------------------
$modelKeys = @(
    'ckpt_name', 'lora_name', 'model_name', 'vae_name',
    'control_net_name', 'unet_name', 'clip_name', 'clip_name1',
    'clip_name2', 'ipadapter_file', 'weight_name', 'file'
)

# ---------------------------------------------------------------------------
# Helper: extract model refs from parsed workflow JSON
# ---------------------------------------------------------------------------
function Get-RefsFromWorkflow {
    param($workflow)
    $refs = [System.Collections.Generic.List[PSObject]]::new()
    if ($null -eq $workflow) { return $refs }

    $nodesList = $null
    if ($workflow.PSObject.Properties['nodes']) {
        $nodesList = $workflow.nodes
    } else {
        $nodesList = $workflow.PSObject.Properties.Value |
            Where-Object { $_ -is [PSCustomObject] -and $_.PSObject.Properties['class_type'] }
    }
    if ($null -eq $nodesList) { return $refs }

    foreach ($node in $nodesList) {
        if ($null -eq $node) { continue }
        $classType = ""
        $nodeTitle = ""
        if ($node.PSObject.Properties['class_type']) { $classType = $node.class_type }
        if ($node.PSObject.Properties['type'])        { $classType = $node.type }
        if ($node.PSObject.Properties['_meta'])       { $nodeTitle = $node._meta.title }
        if (!$nodeTitle -and $node.PSObject.Properties['title']) { $nodeTitle = $node.title }
        if (!$nodeTitle) { $nodeTitle = $classType }
        $label = if ($nodeTitle -and $nodeTitle -ne $classType) { "$nodeTitle ($classType)" } else { $classType }

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
# Helper: properly parse PNG chunks to extract ComfyUI workflow JSON
#
# Handles all three text chunk types ComfyUI may use:
#   tEXt - uncompressed:  keyword\0text
#   zTXt - zlib deflate:  keyword\0\0<deflate-compressed text>
#   iTXt - international: keyword\0flag\0method\0lang\0translated\0text
# ---------------------------------------------------------------------------
function Get-WorkflowFromPng {
    param([string]$PngPath)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($PngPath)

        # Verify PNG signature
        if ($bytes.Length -lt 8) { return $null }
        if ($bytes[0] -ne 0x89 -or $bytes[1] -ne 0x50 -or
            $bytes[2] -ne 0x4E -or $bytes[3] -ne 0x47) { return $null }

        $pos = 8

        while ($pos -lt ($bytes.Length - 12)) {
            $chunkLen  = ([int]$bytes[$pos]   -shl 24) -bor `
                         ([int]$bytes[$pos+1] -shl 16) -bor `
                         ([int]$bytes[$pos+2] -shl 8)  -bor `
                          [int]$bytes[$pos+3]
            $chunkType = [System.Text.Encoding]::ASCII.GetString($bytes, $pos+4, 4)
            $dataStart = $pos + 8
            $dataEnd   = $dataStart + $chunkLen

            if ($chunkType -eq 'tEXt' -or $chunkType -eq 'zTXt' -or $chunkType -eq 'iTXt') {

                # Find null-terminated keyword
                $nullPos = $dataStart
                while ($nullPos -lt $dataEnd -and $bytes[$nullPos] -ne 0x00) { $nullPos++ }

                if ($nullPos -lt $dataEnd) {
                    $keyword    = [System.Text.Encoding]::Latin1.GetString($bytes, $dataStart, $nullPos - $dataStart)
                    $valueStart = $nullPos + 1

                    if ($keyword -eq 'workflow' -or $keyword -eq 'prompt') {

                        $jsonStr = $null

                        if ($chunkType -eq 'tEXt') {
                            # Plain text
                            $valueLen = $dataEnd - $valueStart
                            if ($valueLen -gt 0) {
                                $jsonStr = [System.Text.Encoding]::UTF8.GetString($bytes, $valueStart, $valueLen)
                            }

                        } elseif ($chunkType -eq 'zTXt') {
                            # zTXt: 1 byte compression method (always 0), then zlib/deflate data
                            # zlib stream starts with 2-byte header (0x78 ...), deflate data follows
                            $compMethod = $bytes[$valueStart]
                            $compStart  = $valueStart + 1
                            $compLen    = $dataEnd - $compStart
                            if ($compLen -gt 2) {
                                # Skip 2-byte zlib header, use raw deflate
                                $deflateStart = $compStart + 2
                                $deflateLen   = $compLen - 2
                                $deflateBytes = [byte[]]::new($deflateLen)
                                [Array]::Copy($bytes, $deflateStart, $deflateBytes, 0, $deflateLen)

                                $msIn   = [System.IO.MemoryStream]::new($deflateBytes)
                                $msOut  = [System.IO.MemoryStream]::new()
                                $deflate = [System.IO.Compression.DeflateStream]::new(
                                    $msIn, [System.IO.Compression.CompressionMode]::Decompress)
                                $deflate.CopyTo($msOut)
                                $deflate.Dispose()
                                $jsonStr = [System.Text.Encoding]::UTF8.GetString($msOut.ToArray())
                            }

                        } elseif ($chunkType -eq 'iTXt') {
                            # iTXt: compression_flag(1) + compression_method(1) + lang\0 + translated_keyword\0 + text
                            $compFlag   = $bytes[$valueStart]
                            $compMethod = $bytes[$valueStart + 1]
                            $skipPos    = $valueStart + 2
                            # Skip language tag (null-terminated)
                            while ($skipPos -lt $dataEnd -and $bytes[$skipPos] -ne 0x00) { $skipPos++ }
                            $skipPos++
                            # Skip translated keyword (null-terminated)
                            while ($skipPos -lt $dataEnd -and $bytes[$skipPos] -ne 0x00) { $skipPos++ }
                            $skipPos++
                            $textLen = $dataEnd - $skipPos
                            if ($textLen -gt 0) {
                                if ($compFlag -eq 1) {
                                    # Compressed iTXt - same deflate approach
                                    $deflateStart = $skipPos + 2
                                    $deflateLen   = $textLen - 2
                                    $deflateBytes = [byte[]]::new($deflateLen)
                                    [Array]::Copy($bytes, $deflateStart, $deflateBytes, 0, $deflateLen)
                                    $msIn    = [System.IO.MemoryStream]::new($deflateBytes)
                                    $msOut   = [System.IO.MemoryStream]::new()
                                    $deflate = [System.IO.Compression.DeflateStream]::new(
                                        $msIn, [System.IO.Compression.CompressionMode]::Decompress)
                                    $deflate.CopyTo($msOut)
                                    $deflate.Dispose()
                                    $jsonStr = [System.Text.Encoding]::UTF8.GetString($msOut.ToArray())
                                } else {
                                    $jsonStr = [System.Text.Encoding]::UTF8.GetString($bytes, $skipPos, $textLen)
                                }
                            }
                        }

                        if ($jsonStr) {
                            $parsed = $jsonStr | ConvertFrom-Json -ErrorAction SilentlyContinue
                            if ($parsed) { return $parsed }
                        }
                    }
                }
            }

            $pos += 12 + $chunkLen
            if ($chunkType -eq 'IEND') { break }
        }
    } catch { }
    return $null
}

# ---------------------------------------------------------------------------
# Helper: process a single file (json or png) and add rows to $mapRows
# ---------------------------------------------------------------------------
function Process-WorkflowFile {
    param($wf, [string]$sourceLabel)

    $workflow = $null

    if ($wf.Extension -eq '.json') {
        try {
            $content  = Get-Content -Path $wf.FullName -Raw -Encoding UTF8
            $workflow = $content | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Host "  SKIP (bad JSON): $($wf.Name)" -ForegroundColor DarkGray
            return $false
        }
    } elseif ($wf.Extension -eq '.png') {
        $workflow = Get-WorkflowFromPng -PngPath $wf.FullName
        if (!$workflow) { return $false }
    }

    $refs = Get-RefsFromWorkflow -workflow $workflow
    if ($refs.Count -eq 0) { return $false }

    $wfRel = "$sourceLabel\$($wf.Name)"

    foreach ($r in $refs) {
        $resolved      = Resolve-ModelRef -Ref $r.model_ref
        $normalizedRef = $r.model_ref.ToLower() -replace '\\','/'
        [void]$script:allModelRefs.Add($normalizedRef)

        $script:mapRows.Add([PSCustomObject]@{
            source            = $sourceLabel
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
    return $true
}

# ---------------------------------------------------------------------------
# 3. Scan workflow JSON files
# ---------------------------------------------------------------------------
Write-Host "Scanning JSON workflows in: $WorkflowDir" -ForegroundColor Yellow

$jsonFiles = @(Get-ChildItem -Path $WorkflowDir -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.json' })

Write-Host "  Found $($jsonFiles.Count) JSON file(s)" -ForegroundColor Green

$mapRows      = [System.Collections.Generic.List[PSObject]]::new()
$allModelRefs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$processed    = 0
$skipped      = 0

foreach ($wf in $jsonFiles) {
    $ok = Process-WorkflowFile -wf $wf -sourceLabel "workflows"
    if ($ok) { $processed++ } else { $skipped++ }
}

Write-Host "  Processed : $processed  |  Skipped: $skipped" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 4. Scan PNG files (workflow dir first, then PngDir if specified)
# ---------------------------------------------------------------------------
$pngDirsToScan = @()

# PNGs inside the workflow folder
$wfPngs = @(Get-ChildItem -Path $WorkflowDir -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.png' })
if ($wfPngs.Count -gt 0) { $pngDirsToScan += [PSCustomObject]@{ files = $wfPngs; label = "workflows-png" } }

# Dedicated output/PNG folder
if ($PngDir) {
    Write-Host ""
    Write-Host "Scanning PNG outputs in: $PngDir" -ForegroundColor Yellow
    $outputPngs = @(Get-ChildItem -Path $PngDir -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.png' })
    Write-Host "  Found $($outputPngs.Count) PNG file(s)" -ForegroundColor Green
    if ($outputPngs.Count -gt 0) { $pngDirsToScan += [PSCustomObject]@{ files = $outputPngs; label = "png-outputs" } }
}

$pngProcessed = 0
$pngSkipped   = 0

foreach ($batch in $pngDirsToScan) {
    foreach ($wf in $batch.files) {
        $ok = Process-WorkflowFile -wf $wf -sourceLabel $batch.label
        if ($ok) { $pngProcessed++ } else { $pngSkipped++ }
    }
}

if ($pngDirsToScan.Count -gt 0) {
    Write-Host "  PNG processed : $pngProcessed  |  Skipped (no workflow data): $pngSkipped" -ForegroundColor Green
}

Write-Host ""
$totalProcessed = $processed + $pngProcessed

# ---------------------------------------------------------------------------
# 5. Usage summary per model
# ---------------------------------------------------------------------------
$usageSummary = @($mapRows |
    Where-Object { $_.on_disk -eq "YES" } |
    Group-Object model_filename |
    ForEach-Object {
        $grp    = $_
        $first  = $grp.Group[0]
        $wfList = @($grp.Group | Select-Object -ExpandProperty workflow_file -Unique | Sort-Object)
        [PSCustomObject]@{
            model_filename = $grp.Name
            model_category = $first.model_category
            model_size_gb  = $first.model_size_gb
            workflow_count = $wfList.Count
            workflows      = $wfList -join " | "
        }
    } | Sort-Object -Property workflow_count -Descending)

# ---------------------------------------------------------------------------
# 6. Unused models
# ---------------------------------------------------------------------------
$unusedModels = @($modelInventory.Values | Where-Object {
    $fn = $_.filename.ToLower()
    -not ($allModelRefs | Where-Object { $_ -like "*$fn" })
} | Sort-Object category, filename)

# ---------------------------------------------------------------------------
# 7. Missing models
# ---------------------------------------------------------------------------
$missingModels = @($mapRows |
    Where-Object { $_.on_disk -eq "NO" } |
    Select-Object model_ref, workflow_file, node_label -Unique |
    Sort-Object model_ref)

# ---------------------------------------------------------------------------
# 8. Console output
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
$unusedModels | Select-Object -First 10 | Format-Table filename, category, size_gb -AutoSize

# ---------------------------------------------------------------------------
# 9. Save output files
# ---------------------------------------------------------------------------
if (!$NoFile) {
    if (!(Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }

    $prefix = Join-Path $OutputDir "$hostName-WorkflowMap-$timeStamp"

    $mapRows       | Export-Csv "$prefix-full_map.csv"       -NoTypeInformation -Encoding UTF8
    $usageSummary  | Export-Csv "$prefix-model_usage.csv"    -NoTypeInformation -Encoding UTF8
    $unusedModels  | Export-Csv "$prefix-unused_models.csv"  -NoTypeInformation -Encoding UTF8
    $missingModels | Export-Csv "$prefix-missing_models.csv" -NoTypeInformation -Encoding UTF8

    $div1 = "============================================================"
    $div2 = "------------------------------------------------------------"

    $invCount     = $modelInventory.Count
    $refsCount    = $allModelRefs.Count
    $usedCount    = $usageSummary.Count
    $unusedCount  = $unusedModels.Count
    $missingCount = $missingModels.Count

    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add("ComfyUI Workflow -> Model Map Summary")
    $out.Add("Host    : $hostName")
    $out.Add("Date    : $timeStamp")
    $out.Add($div1)
    $out.Add("")
    $out.Add("MODELS ON DISK       : $invCount")
    $out.Add("JSON WORKFLOWS       : $processed processed  |  $skipped skipped")
    $out.Add("PNG FILES            : $pngProcessed processed  |  $pngSkipped skipped (no embedded workflow)")
    $out.Add("TOTAL PROCESSED      : $totalProcessed")
    $out.Add("UNIQUE MODEL REFS    : $refsCount")
    $out.Add("MODELS USED          : $usedCount")
    $out.Add("MODELS UNUSED        : $unusedCount")
    $out.Add("MISSING (not on disk): $missingCount")
    $out.Add("")
    $out.Add($div1)
    $out.Add("TOP MODELS BY WORKFLOW COUNT")
    $out.Add($div2)

    foreach ($row in ($usageSummary | Select-Object -First 30)) {
        $line = "  [{0,2} workflows]  {1}  ({2})  {3} GB" -f `
            $row.workflow_count, $row.model_filename, $row.model_category, $row.model_size_gb
        $out.Add($line)
    }

    if ($unusedCount -gt 0) {
        $unusedGB = [math]::Round(($unusedModels | Measure-Object size_gb -Sum).Sum, 2)
        $out.Add("")
        $out.Add($div1)
        $out.Add("UNUSED MODELS  ($unusedCount files  |  $unusedGB GB wasted)")
        $out.Add($div2)
        foreach ($m in $unusedModels) {
            $line = "  {0,-55} {1} GB  [{2}]" -f $m.filename, $m.size_gb, $m.category
            $out.Add($line)
        }
    }

    if ($missingCount -gt 0) {
        $out.Add("")
        $out.Add($div1)
        $out.Add("MISSING MODELS (referenced in workflows but not on disk)")
        $out.Add($div2)
        foreach ($m in ($missingModels | Select-Object model_ref -Unique)) {
            $out.Add("  $($m.model_ref)")
        }
    }

    $out | Out-File "$prefix-summary.txt" -Encoding UTF8

    Write-Host ""
    Write-Host "Output files:" -ForegroundColor Yellow
    Write-Host "  $prefix-full_map.csv"
    Write-Host "  $prefix-model_usage.csv"
    Write-Host "  $prefix-unused_models.csv"
    Write-Host "  $prefix-missing_models.csv"
    Write-Host "  $prefix-summary.txt"
    Write-Host ""
    Write-Host "Done!" -ForegroundColor Green
}
