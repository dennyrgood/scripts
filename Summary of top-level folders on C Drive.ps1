# Summary of top-level folders on C: (including hidden/system files)
$root = "C:\users\pc"
Get-ChildItem -Path $root -Directory -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
        $size = (Get-ChildItem -Path $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum
        [PSCustomObject]@{
            Folder = $_.Name
            SizeGB = [math]::Round($size / 1GB, 2)
            SizeMB = [math]::Round($size / 1MB, 0)
        }
    } |
    Sort-Object SizeGB -Descending |
    Format-Table -AutoSize

