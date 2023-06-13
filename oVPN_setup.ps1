# Full setup script
# Make this script run in a 64 bit powershell. May not be necessary, depending on your RMM
# https://ninjarmm.zendesk.com/hc/en-us/articles/360004665911-Custom-Script-Run-powershell-in-64-bit-mode

if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    write-warning "Executing your script in 64-bit mode"
    if ($myInvocation.Line) {
      &"$env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe" -NonInteractive -NoProfile $myInvocation.Line
    } else {
      &"$env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe" -NonInteractive -NoProfile -file "$($myInvocation.InvocationName)" $args
    }
    exit $lastexitcode
}
$errorActionPreference = 'Stop'


$conf = @{
    x509 = "server.cert.CN"
    remoteIP = "ovpn.ip.or.fqdn"
    rootCA = "MY_ADCA"
    configName = "Whatever_you_want"
    ca = "MY_IntermediateCA.. if you have one. if not then set this the same as rootCA"
    remotePort = "1194"
    time_start = "7:15am"
    time_end = "5:45pm"
    work_days = @("Monday","Tuesday","Wednesday","Thursday","Friday")
    adgroup = "SG-OpenVPN_users-24x7"
    ekuName = "IP security end system"
}
$install_path = "$env:programData\corpvpn"
New-Item -itemType Directory -path $install_path -errorAction silentlyContinue

$conf | ConvertTo-JSON | Out-File "$install_path\config_params.json"

$iconpath = $install_path + '\res\'
$psPath = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
$schPath = "$env:windir\System32\schtasks.exe"

# For links and shortcuts
$linksFolder_Path = "$env:programdata\Microsoft\Windows\Start Menu\Programs\OpenVPN\" + $conf.configName
$loglinkName = $linksFolder_Path + '\View ' + $conf.configName + ' Log.lnk'
$cfgLinkName = $linksFolder_Path + '\Open ' + $conf.configName + ' config path.lnk'
$svcStartName = $linksFolder_Path + '\Start ' + $conf.configName + '.lnk'
$svcStopName = $linksFolder_Path + '\Stop ' + $conf.configName + '.lnk'

# a scratch folder
$wrk = "$env:programdata\my_rmm"

# Create Folders
foreach ($pp in $install_path,$linksFolder_Path,$wrk) {
    if (!(Test-Path $pp)) {
        $dirsplat = @{
            ItemType = 'Directory'
            Path = $pp
            Force = $true
        }
        New-Item @dirsplat
    }
}

# ----------------------------------------------------------
# Deliver the corpvpn folder to the client computer somehow

# Copy-Item corpvpn -destination $install_path -force -Recurse

# or

<#
$configURL = 'https://url.of.zipped.corpvpn.folder/vpn.zip'
$zipdl = "$wrk\vpn.zip"
(New-Object System.Net.webClient).DownloadFile($configURL,$zipdl)  
Expand-Archive $zipdl -destination $install_path -force
#>


# --------------------------------------------------------
# Uncomment to clean remove any existing OpenVPN profiles
# & "$install_path\oVPN_cleanup.ps1"

# --------------------------------------------------------
# Uncomment to install the newest OpenVPN client
# & "$install_path\oVPN_client_install.ps1"


# -----------------------------------------------------
# Configure OpenVPNs service security, allow user to stop/start the service (but not disable / enable):
# https://www.winhelponline.com/blog/view-edit-service-permissions-windows/

$svcName = "OpenVPNservice"
$sddl = cmd /c SC sdshow $svcName | Where-Object {$_}
$d_part, $s_part = $sddl -split "(?<=\))([DS]):"
$ddd = $d_part.split(':')[1]
$d_parts = $ddd -split "\(|\)" | Where-Object {$_}

$d_part_new = 'D:'
foreach ($d in $d_parts) {
    if ($d.endswith(';;;IU')) {
        $d = "A;;CCLCSWLOCRRCRPWP;;;IU"
    }
    $d_part_new += '(' + $d + ')'
}
$sddl_new = $d_part_new + ($s_part -join ':')

Write-Host $sddl
Write-Host $sddl_new
cmd /c SC sdset $svcName $sddl_new
Set-Service $svName -StartupType Manual

# ----------------------------------------------------------------
# Interface up task - on network connection, disable VPN if on an office network
$schArgs = '/Create /TN "corpVPN\check if remote" /XML "' + "$install_path\ifup_task.xml" + '"'
Start-Process -FilePath $schPath -ArgumentList $schArgs -wait


# -------------------------------------------------------------------
# Config builder task - on startup, every 2 weeks
$task = @{
    taskName = 'corpVPN\Generate openVPN config'
    Description = 'Regenerate TG Corp OpenVPN config, ensuring usage of current certificate'
    Trigger = @(
        $(New-ScheduledTaskTrigger -AtStartup),
        $(New-ScheduledTaskTrigger -Weekly -WeeksInterval 2 -DaysOfWeek Monday -At 8am)
    )
    User = "NT AUTHORITY\SYSTEM"
    RunLevel = 'Highest'
    Force = $true
    Settings = $(New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:20:00)
    Action = New-ScheduledTaskAction -Execute $psPath -Argument ('-executionPolicy bypass -command "' + "$install_path\generate_ovpn_config.ps1" + '"') -WorkingDirectory "$install_path"
}
$existingTasks = Get-ScheduledTask | Where-Object {$_.TaskName -eq $task.TaskName}
If ($existingTasks.count -ge 1) {
    foreach ($t in $existingTasks) {
        Unregister-ScheduledTask -TaskName $task.TaskName -confirm:$false
    }
} 
Register-ScheduledTask @task

# Generate Initial config
Start-ScheduledTask -TaskName $task.TaskName


# ------------------------------------------------------------
# Create shortcuts
# https://stackoverflow.com/questions/9701840/how-to-create-a-shortcut-using-powershell


$WshShell = New-Object -comObject WScript.Shell

# Shortcut for log files
$loglnk = $WshShell.CreateShortcut($loglinkName)
$loglnk.TargetPath = "$env:systemdrive\Windows\System32\notepad.exe"
$loglnk.Arguments = ("$env:ProgramFiles\OpenVPN\log\" + $conf.configName + '.log')
$loglnk.iconLocation = $iconPath + 'connecting.ico'
$loglnk.save()

# Shortcut to config path
$clnk = $WshShell.CreateShortcut($cfgLinkName)
$clnk.TargetPath = "$env:systemdrive\Windows\explorer.exe"
$clnk.Arguments = "$env:ProgramFiles\OpenVPN\config-auto\"
$clnk.iconLocation = $iconPath + 'openvpn-gui.ico'
$clnk.save()

# Shortcut to start VPN
$ilnk = $WshShell.CreateShortcut($svcStartName)
$ilnk.TargetPath = "$env:systemdrive\Windows\System32\sc.exe"
$ilnk.Arguments = "start openVPNservice"
$ilnk.iconLocation = $iconPath + 'connected.ico'
$ilnk.save()

# Shortcut to stop VPN
$olnk = $WshShell.CreateShortcut($svcStopName)
$olnk.TargetPath = "$env:systemdrive\Windows\System32\sc.exe"
$olnk.Arguments = "stop openVPNservice"
$olnk.iconLocation = $iconPath + 'disconnected.ico'
$olnk.save()

# ---------------------------------------------------
# Start / Stop task for morning and evening

Write-Output $conf.time_start
$task = @{
    taskName = ('corpVPN\Enforce office hours')
    Description = ('Enable or disable OpenVPNservice for ' + $conf.configName + ' connection based on work hours')
    Trigger = @(
      $(New-ScheduledTaskTrigger -Daily -at $conf.time_start),
      $(New-ScheduledTaskTrigger -Daily -at $conf.time_end)
    )
    User = "NT AUTHORITY\SYSTEM"
    RunLevel = 'Highest'
    Force = $true
    Settings = $(New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:20:00)
    Action = New-ScheduledTaskAction -Execute $psPath -Argument ('-executionPolicy bypass -command "' + "$install_path\enforce_office_hours.ps1" + '"') -WorkingDirectory "$install_path"
}

# Remove any duplicates, register the start task
$existingTasks = Get-ScheduledTask | Where-Object {$_.TaskName -eq $task.TaskName}
If ($existingTasks.count -ge 1) {
foreach ($t in $existingTasks) {
    Unregister-ScheduledTask -TaskName $task.TaskName -confirm:$false
}
} 
Register-ScheduledTask @task

# ----------------------------
# Enforce office hours on logon / unlock / reboot / etc events - things that new-scheduledTaskAction doesn't support
$schArgs = '/Create /TN "corpVPN\Enforce office hours on events" /XML "' + "$install_path\enforce_on_unlock_task.xml" + '"'
Start-Process -FilePath $schPath -ArgumentList $schArgs -wait

# Start VPN
Start-ScheduledTask -TaskName $task.TaskName


# C:\Windows\System32\notepad.exe "C:\github\OpenVPN_ADCS\README.md"

# C:\Program Files\OpenVPN\res\ovpn.ico
  
  
  
