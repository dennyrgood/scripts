# notify.ps1 - iMessage yourself via FleetDev (Windows). Keep this file plain ASCII (PowerShell 5.1).
#   notify.ps1 "message"            send the message
#   "message" | notify.ps1          message from the pipeline
#   notify.ps1 --email "message"    also email it
#   notify.ps1 --help
# Goes over ssh to dennishmathes@fleetdev, so this box needs key login to it.

$fd = "dennishmathes@fleetdev"
$remote = "repos/scripts/FleetDev/notify-me"
$rest = @($args)

if ($rest.Count -gt 0 -and ($rest[0] -eq "-h" -or $rest[0] -eq "--help")) {
    ssh -n -o ConnectTimeout=10 $fd $remote --help
    exit $LASTEXITCODE
}

$emailFlag = @()
if ($rest.Count -gt 0 -and $rest[0] -eq "--email") {
    $emailFlag = @("--email")
    if ($rest.Count -gt 1) { $rest = $rest[1..($rest.Count - 1)] } else { $rest = @() }
}

if ($rest.Count -gt 0) { $text = ($rest -join " ") } else { $text = ($input | Out-String) }

# Send UTF-8 (no BOM) so non-ASCII characters in the message survive the pipe.
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$text | ssh -o ConnectTimeout=10 $fd $remote @emailFlag
exit $LASTEXITCODE
