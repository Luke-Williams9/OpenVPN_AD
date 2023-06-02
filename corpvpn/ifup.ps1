
<#
    IFUP script for Tlicho Government AD-integrated VPN
    test if computer is on domain network or not
    By Luke Williams
    
    Version 0.2

    to disable VPN when computer is on the TG network, create a scheduled task
    https://www.groovypost.com/howto/automatically-run-script-on-internet-connect-network-connection-drop/

    trigger on event: Microsoft-WSindows_networkProfile/Operational
    Source: NetworkProfile
    ID: 10000
#>
$svc = Get-Service OpenVPNservice
if ($svc.StartType -eq 'Disabled') {
    # Service will be disabled when not on work hours. Nothing to do here
    exit 0
}

# I think this doesn't work well with static IPs, but oh well. who on a work laptop should have a static IP anyways?
$networkName = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.IPEnabled -eq $true -and $_.serviceName -notlike '*tap*'}).DNSDomain
$ComputerDomain = (Get-WmiObject Win32_ComputerSystem).Domain

if ($ComputerDomain -eq $networkName) {
    # Computer is connected to domain/office network, has local access to network resources. Stop OpenVPN service
    Stop-Service OpenVPNservice
} else {
    # Computer is remote. Start VPN
    Start-Service OpenVPNservice
}