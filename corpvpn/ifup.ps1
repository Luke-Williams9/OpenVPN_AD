
<#
    IFUP script for Tlicho Government AD-integrated VPN
    test if computer is on domain network or not
    By Luke Williams
    
    Version 0.3

    to disable VPN when computer is on the TG network, create a scheduled task
    https://www.groovypost.com/howto/automatically-run-script-on-internet-connect-network-connection-drop/

    trigger on event: Microsoft-WSindows_networkProfile/Operational
    Source: NetworkProfile
    ID: 10000
#>
$script:process = "ifup"
. .\logger.ps1
$svc = Get-Service OpenVPNservice
Write-Log "IFUP Start"
if ($svc.StartType -eq 'Disabled') {
    Write-Log "OpenVPN service is disabled when not on work hours. Nothing to do here"
    exit 0
}

# I think this doesn't work well with static IPs, but oh well. who on a work laptop should have a static IP anyways?
$networkName = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.IPEnabled -eq $true -and $_.serviceName -notlike '*tap*'}).DNSDomain
$ComputerDomain = (Get-WmiObject Win32_ComputerSystem).Domain

if ($ComputerDomain -eq $networkName) {
    Write-Log ("Computers domain and Network DNSdomain both = " + $ComputerDomain + " - Computer is in contact with corp network. Stopping OpenVPNservice")
    # Computer is connected to domain/office network, has local access to network resources. Stop OpenVPN service
    Stop-Service 'OpenVPNservice'
} else {
    # Computer is remote. Start VPN
    Write-Log ("Computer domain: " )
    Start-Service 'OpenVPNservice'
}
Start-Sleep -Seconds 7
$s = Get-Service 'OpenVPNService'
Write-Log ("ServiceName: " + $s.Name + " | Status: " + $s.Status)
Write-Log "IFUP End"