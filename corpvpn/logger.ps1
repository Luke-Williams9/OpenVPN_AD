# Logger include
$a = $MyInvocation.ScriptName.split('\')
$global:parent = $a[$a.count-1].split('.')[0]
$global:logfile = "scripts_log.txt"
$global:logfile_old = $logfile + '.old'
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
    "Date       Time     :: ScriptName :: Message" | Out-File $logfile -append
    "-------------------------------------------------------" | Out-File $logfile -append
}

function Write-Log {
    [CmdletBinding()]
    param (
        [string]$process = $parent,
        [Parameter(position=0)][string]$message
    )
    $log_line = (Get-Date -format "dd-MM-yyyy HH:mm:ss") + ' :: ' + $process + ' :: ' + $message
    $log_line | Out-File $logfile -append -force
    Return $log_line
}