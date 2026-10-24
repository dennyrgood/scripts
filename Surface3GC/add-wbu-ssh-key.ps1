# add-wbu-ssh-key.ps1 -- let wbu (workbenchunix) ssh into this box with its key.
# Created: 2026-10-25. Run once in an ELEVATED PowerShell on s3g.
#
# Windows OpenSSH ignores ~\.ssh\authorized_keys for members of Administrators
# and reads C:\ProgramData\ssh\administrators_authorized_keys instead, which must
# be owned by SYSTEM/Administrators only. So the key goes in both, with the right ACL.

$key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM+4Y8+wkOQhuesbvshv6exZAkVCs2N7YfH7KJGTwd9G wbu (dhm@workbenchunix)'
$keyBody = ($key -split ' ')[1]

function Add-Key($path) {
    $dir = Split-Path $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ((Test-Path $path) -and (Select-String -Path $path -SimpleMatch $keyBody -Quiet)) {
        Write-Host "already present: $path"
    } else {
        Add-Content -Path $path -Value $key -Encoding ascii
        Write-Host "added: $path"
    }
}

Add-Key "$env:USERPROFILE\.ssh\authorized_keys"

$admin = 'C:\ProgramData\ssh\administrators_authorized_keys'
Add-Key $admin
icacls $admin /inheritance:r /grant "*S-1-5-32-544:F" /grant "SYSTEM:F" | Out-Null
Write-Host "ACL fixed on $admin"

Write-Host ""
Write-Host "user for ssh: $env:USERNAME"
Get-Service sshd | Format-Table Name, Status, StartType -AutoSize
