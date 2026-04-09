$file1 = "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\text_encoders\qwen_3_4b.safetensors"
$file2 = "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\text_encoders\FLUX2\qwen_3_4b.safetensors"

(Get-FileHash $file1).Hash
(Get-FileHash $file2).Hash

function Get-SafetensorsFullHeader {
    param($path)
    $fs = [System.IO.File]::OpenRead($path)
    try {
        $lenBytes = New-Object byte[] 8
        $fs.Read($lenBytes, 0, 8) | Out-Null
        $headerLen = [BitConverter]::ToInt64($lenBytes, 0)
        Write-Host "Header length: $headerLen bytes"
        $headerBytes = New-Object byte[] $headerLen
        $fs.Read($headerBytes, 0, $headerLen) | Out-Null
        [System.Text.Encoding]::UTF8.GetString($headerBytes)
    } finally {
        $fs.Close()
    }
}

Get-SafetensorsFullHeader $file1 | Out-File "$env:TEMP\header1.json"
Get-SafetensorsFullHeader $file2 | Out-File "$env:TEMP\header2.json"

(Get-Item $file1).LastWriteTime
(Get-Item $file2).LastWriteTime


 Compare-Object (Get-Content "$env:TEMP\header1.json") (Get-Content "$env:TEMP\header2.json")