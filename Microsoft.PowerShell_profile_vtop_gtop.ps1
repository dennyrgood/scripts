# Custom Alias for GPU Monitoring on ImageBeast
function Run-Nvitop {
    & "C:\Misc\Scripts\nvitop.exe" $args
}

Set-Alias gtop Run-Nvitop

function Get-GPUInventory {
    $Data = (Get-Counter "\GPU Process Memory(*)\Local Usage" -ErrorAction SilentlyContinue).CounterSamples | Where-Object {$_.CookedValue -gt 10MB}
    $Report = $Data | ForEach-Object { 
        if($_.InstanceName -match 'pid_(\d+)') { 
            $TargetID = $Matches[1]
            $proc = Get-Process -Id $TargetID -EA 0
            $name = if($proc){$proc.Name}else{"Unknown-$TargetID"} 
            [PSCustomObject]@{Name=$name; MB=$_.CookedValue/1MB} 
        } 
    } | Group-Object Name | Select-Object Name, @{N="VRAM_MB";E={[math]::Round(($_.Group.MB | Measure-Object -Sum).Sum, 2)}} | Sort-Object VRAM_MB -Descending
    
    if ($Report) {
        $Report | Format-Table -AutoSize
    } else {
        Write-Host "No significant GPU usage detected (>10MB)." -ForegroundColor Cyan
    }
}

# Create the alias
Set-Alias vtop Get-GPUInventory