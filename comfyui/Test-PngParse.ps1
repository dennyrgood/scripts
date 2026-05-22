
$path = "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\output\Flux2klein4bPadding_00011_.png"
$bytes = [System.IO.File]::ReadAllBytes($path)
Write-Host "File size: $($bytes.Length) bytes"
Write-Host "PNG sig: $($bytes[0]) $($bytes[1]) $($bytes[2]) $($bytes[3])"

$pos = 8
while ($pos -lt ($bytes.Length - 12)) {
    $chunkLen  = ([int]$bytes[$pos] -shl 24) -bor ([int]$bytes[$pos+1] -shl 16) -bor ([int]$bytes[$pos+2] -shl 8) -bor [int]$bytes[$pos+3]
    $chunkType = [System.Text.Encoding]::ASCII.GetString($bytes, $pos+4, 4)
    $dataStart = $pos + 8
    $dataEnd   = $dataStart + $chunkLen
    Write-Host "Chunk: $chunkType  len=$chunkLen  dataStart=$dataStart  dataEnd=$dataEnd"

    if ($chunkType -eq "tEXt") {
        $nullPos = $dataStart
        while ($nullPos -lt $dataEnd -and $bytes[$nullPos] -ne 0x00) { $nullPos++ }
        Write-Host "  nullPos=$nullPos  keyword_len=$($nullPos - $dataStart)"
        $kwLen = $nullPos - $dataStart
        if ($kwLen -gt 0) {
            $keyword = [System.Text.Encoding]::Latin1.GetString($bytes, $dataStart, $kwLen)
        } else {
            $keyword = ""
        }
        $valueStart = $nullPos + 1
        $valueLen = $dataEnd - $valueStart
        Write-Host "  keyword='$keyword'  valueStart=$valueStart  valueLen=$valueLen"
        if ($valueLen -gt 0) {
            $jsonStr = [System.Text.Encoding]::UTF8.GetString($bytes, $valueStart, $valueLen).Trim()
            Write-Host "  jsonStr first 50: $($jsonStr.Substring(0, [Math]::Min(50,$jsonStr.Length)))"
            Write-Host "  StartsWith {: $($jsonStr.StartsWith("{"))"
            try {
                $parsed = $jsonStr | ConvertFrom-Json -ErrorAction Stop
                Write-Host "  PARSED OK - type: $($parsed.GetType().Name)"
                Write-Host "  Top keys: $($parsed.PSObject.Properties.Name -join ", " | Select-Object -First 1)"
            } catch {
                Write-Host "  PARSE FAILED: $_"
            }
        }
    }
    $pos += 12 + $chunkLen
    if ($chunkType -eq "IEND") { break }
}

