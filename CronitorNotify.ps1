<#
.SYNOPSIS
    Monitor a Duplicati backup with Cronitor.

.DESCRIPTION
    If you set this script to execute before and after a Duplicati backup job,
    Cronitor will be notified when it starts running, when it finishes, and
    when it fails.

    Don't forget to set the MonitorCode parameter. It is not marked as
    mandatory, but Cronitor won't be pinged without it.

    This script was developed using Duplicati's own example pre- and post-
    backup scripts.

.PARAMETER MonitorCode
    The Cronitor monitor code that identifies the monitor to be pinged. Will
    look something like, "JUwLiX".
#>
[CmdletBinding()]
param(
    [Parameter()] # Intentionally not making this mandatory, to avoid freezing a backup job.
    [string]$MonitorCode
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 4.0

$operationName = $env:DUPLICATI__OPERATIONNAME
# $operationName could be: Backup, Cleanup, Restore, DeleteAllButN

if ($operationName -ne "Backup") {
    exit 0 # We don't care about the other operations at this point.
}

function notifyCronitor([string]$endpoint, [string]$message) {

    if (!$MonitorCode) {
        Write-Warning "-MonitorCode parameter is missing. Cronitor will not be pinged."
        return
    }

    $url = "https://cronitor.link/$MonitorCode/$endpoint"

    if ($message) {

        $encodedMessage = [Uri]::EscapeDataString($message)
        if ($encodedMessage.Length -gt 1000) {
            # Cronitor limits message length to 1000 characters
            $encodedMessage = $encodedMessage.Substring(0, 1000)
        }

        $url = "$($url)?msg=$encodedMessage"
    }

    try {
        Invoke-WebRequest -UseBasicParsing -Uri $url | Out-Null
    } catch {
        Write-Warning "Unable to ping Cronitor: $_"
        # It's ok to swallow errors here. Cronitor notifies us if we aren't able to successfully send pings.
    }
}

$eventName = $env:DUPLICATI__EVENTNAME

if ($eventName -eq "BEFORE") {

    # This script is being run before the backup starts
    notifyCronitor "run" "Backup started by $env:USERNAME on $env:COMPUTERNAME."

    # Notify Duplicati that everything's OK with a 0 exit code. This tells
    # Duplicati to go ahead and run the backup.
    #
    # IMPORTANT: This is NOT a return statement. This will actually stop the
    # current PowerShell session, and kill the PowerShell process with an exit
    # code of 0.
    exit 0

} elseif ($eventName -eq "AFTER") {

    # This script is being run after the backup has finished
    $backupResult = $env:DUPLICATI__PARSED_RESULT
    if ($backupResult -eq "Success") {
        notifyCronitor "complete" "Backup finished successfully."
    } else {
        $resultFile = $env:DUPLICATI__RESULTFILE
        notifyCronitor "fail" "Backup result: $backupResult. See ""$resultFile"" for more info."
    }
} else {
    Write-Host "Event name $eventName not recognized. Skipping Cronitor ping."
}
