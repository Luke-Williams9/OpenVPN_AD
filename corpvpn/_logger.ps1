# Logger include

$script:logfile = "scripts_log.txt"
$script:logfile_old = $logfile + '.old'
$script:myPID = (100..999) | Get-Random
# Rotate Log file @ 2mb
if (Test-Path $logfile) {
    if ((Get-Item $logfile).length -ge 2mb) {
        Write-Host "Rotating log"
        Remove-Item $logfile_old -Force
        Rename-Item $logfile -newName $logfile_old
    }
}
if (!(Test-Path $logfile)) {
    Write-Host "Creating new log file"
    ("`r`nCorp VPN Scripts Log - " + [String](Get-Date)) | Out-File $logfile -force
    "---------------------------------------------" | Out-File $logfile -append
    "DD-MM-YYYY HH:mm:SS :: Script(PID) :: Message" | Out-File $logfile -append
    "-------------------------------------------------------" | Out-File $logfile -append
}

# Must define $script:process before dot sourcing this script
#if ($script:process -in '',$null) {
#    $script:process = 'unknown'
#}
function Write-Log {
    [CmdletBinding()]
    param (
        [string]$process = ($script:process + '(' + [string]$myPID + ')'),
        [Parameter(position=0)][string]$message
    )
    $log_line = ((Get-Date -format "dd-MM-yyyy HH:mm:ss") + ' :: ' + $process + ' :: ' + $message).trim()
    $log_line | Out-File $logfile -append -force
    Return $log_line
}