
<#
    IFUP script for Tlicho Government AD-integrated VPN
    test if computer is on domain network or not
    By Luke Williams
    
    Version 0.4

    to disable VPN when computer is on the TG network, create a scheduled task
    https://www.groovypost.com/howto/automatically-run-script-on-internet-connect-network-connection-drop/

    trigger on event: Microsoft-WSindows_networkProfile/Operational
    Source: NetworkProfile
    ID: 10000
#>
$script:process = "ifup"
. .\logger.ps1
$svc = Get-Service OpenVPNservice
Write-Log "__IFUP Start"
if ($svc.StartType -eq 'Disabled') {
    Write-Log "OpenVPN service is disabled when not on work hours. Nothing to do here"
    exit 0
}

# I think this doesn't work well with static IPs, but oh well. who on a work laptop should have a static IP anyways?
$networkName = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.IPEnabled -eq $true -and $_.serviceName -notlike '*tap*'}).DNSDomain
$ComputerDomain = (Get-WmiObject Win32_ComputerSystem).Domain
Write-Log ("Computer Domain: " + $ComputerDomain )
Write-Log ("LAN/Wifi Domain: " + $networkName)

if ($ComputerDomain -eq $networkName) {
    Write-Log ("They match - Computer is in contact with corp network. Stopping VPN service")
    # Computer is connected to domain/office network, has local access to network resources. Stop OpenVPN service
    Stop-Service 'OpenVPNservice'
} else {
    # Computer is remote. Start VPN
    Write-Log "They do not match. Computer is not on the corp network. Starting VPN service"
    Start-Service 'OpenVPNservice'
}
Start-Sleep -Seconds 4
Write-Log ($svc.Name + " status: " + $svc.Status)
Write-Log "__IFUP End"