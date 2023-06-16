<#
    OpenVPN configuration file generator for Tlicho Government AD-integrated VPN
    By Luke Williams
    
    Version 0.6

    This script generates a new OpenVPN configuration for the current AD user
    The certificate it uses is issued by TGs issuing CA, to any AD users who are part of the SG-OpenVPNusers group.
    The certificates have a shorter renewal time (ie less than a year) so this script will need to run periodically to update the openVPN configuration.
#>

#Start-Transcript -path '.\generate_ovpn_config.log.txt'
$script:process = "generate_config"
. .\logger.ps1
Write-Log "__Generate OpenVPN Config Start"
$s = Get-Service 'OpenVPNService'
Write-Log ("Service check | " + $svc.Name + " status: " + $svc.Status)

$startSvc = $false
if ($s.status -eq 'Running') {
    $startSvc = $true
}
# Load variable parameters
$var = Get-Content "config_params.json" | ConvertFrom-JSON



Write-Log ("Root CA:    " + $var.rootCA)
Write-Log ("Issuing CA: " + $var.ca)

# File Names
$file_ovpn = $var.configName + '.ovpn'

# Parameters to replace in the config file
$conf = @{
    remoteIP = $var.remoteIP
    remotePort = $var.remotePort
    x509 = $var.x509
    file_ca = $var.rootCA + '.crt'
    file_key = $var.configName + '-tls.key'
    thumbprint = ''
}

# Config file template. Anything between <<>> is a variable which will be replaced with corresponding values from $conf
# add "verb 4" to the config, to increase verbosity for troubleshooting
$configFile = Get-Content 'config.ovpn.template'

# Static key from OpenVPN server settings in pfSense - replace the contents of static.key with your own
$static_key = Get-Content 'static.key'

# Get the CA Cert, error out if not present
Write-Log ("Looking for CA certificate for " + $var.rootCA)
$ca_cert = Get-ChildItem -path cert:\LocalMachine\Root | Where-Object Subject -match $var.rootCA
if (!($ca_cert)) {
    Write-Log "No CA found - Cannot continue"
    Exit 1
}
Write-Log "Found!"

# $myFQDN = ([System.Net.Dns]::GetHostByName($env:computerName)).HostName
$myFQDN = $env:computerName
# Get the thumbprint for the certificate issued by $var.ca, error out if not present
Write-Log ("Looking for Client Authentication certificate, issued from " + $var.ca)
$cert = Get-ChildItem -path cert:\LocalMachine\My | Where-Object {
    ($_.issuer -match $var.ca) `
    -and ($var.ekuName -in $_.EnhancedKeyUsageList.FriendlyName) `
    -and ((Get-Date) -gt $_.notBefore) `
    -and ((Get-Date) -lt $_.notAfter) `
    -and $_.Subject -like "*$myFQDN*"
} | Sort-Object -property NotAfter | Select-Object -last 1

if (!($cert)) {
    Write-Log "No certificate found, cannot continue"
    Exit 1
}
Write-Log "Found!"

# Create config folder
$basePath = "$env:ProgramFiles\OpenVPN\config-auto\"
if (!(Test-Path $basePath)) {
    $dirsplat = @{
        ItemType = 'Directory'
        Path = $basePath
        Force = $true
        ErrorAction = 'SilentlyContinue'
    }
    New-Item @dirsplat
}
Write-Log ("Config path: " + $basePath)

# Save Static Key
$static_key_path = $basePath + $conf.file_key
$static_key | Out-File $static_key_path -encoding ascii
Write-Log ("Saved static key to " + $static_key_path)

# Save CA Certificate
$fff = [System.Convert]::ToBase64String($ca_cert.RawData)

# Make EACH LINE EXACTLY 64 characters
$ca_newlines = ''
for ($i = 0; $i -lt $fff.length; $i += 64) { 
    if ($i -lt $fff.length) {
        $length = [Math]::Min(64, $fff.Length - $i)
        $ca_newlines += $fff.substring($i,$length) + "`r`n"
    }
}
$ca_b64 = ("-----BEGIN CERTIFICATE-----`r`n" + $ca_newlines + "-----END CERTIFICATE-----") 
$ca_file = $basePath + $conf.file_ca
Write-Output ("CA Certificate: `n" + $ca_b64 + "`n`n")

$ca_b64 | Out-File $ca_file -encoding ascii
Write-Log ("Saved CA certificate to " + $ca_file)


# Generate ovpn-readable client cert thumbprint
$conf.thumbprint = ($cert.Thumbprint -replace '([0-9a-f]{2})', '$1 ').ToLower().trim()

Write-Output ("Client certificate: `n" + ($cert | Select-Object Subject, Issuer, Thumbprint, FriendlyName, NotBefore, NotAfter, EnhancedKeyUsageList| Format-List | Out-String))
Write-Log ('Using Client certificate "' + $cert.Subject + '"')
Write-Log ('certifcate thumbprint: ' + $cert.Thumbprint)

# Loop through conf, and replace parameters in configFile
foreach ($k in $conf.keys) {
    $search = "<<" + $k + ">>"
    $configFile = $configFile.replace($search,$conf.$k)
}


Write-Output ("Configuration:`n" + $configFile + "`n`n")
$configFile_path = $basePath + $file_ovpn
$configFile | Out-File $configFile_path  -encoding ascii
Write-Log ("Saved configuration to " + $configFile_path + "`n")

# OpenVPN service autostart
Write-Log "Stopping OpenVPN service"
Stop-Service 'OpenVPNService'
Start-Sleep -Seconds 7
$s = Get-Service 'OpenVPNService'
Write-Log ("Service check | " + $svc.Name + " status: " + $svc.Status)
Write-Log "Triggering enforce office hours script"
if ($startSvc) {
    Write-Log "Starting OpenVPN service"
    Start-Service "OpenVPNService"
    Start-Sleep -seconds 2
    Write-Log ("Service check | " + $svc.Name + " status: " + $svc.Status)
    Write-Log "Including -start param"
    & ".\enforce_office_hours.ps1" -start
} else {
    Write-Log "Not including -start param"
    & ".\enforce_office_hours.ps1" 
}


Write-Log "__Generate OpenVPN Config End"
#Stop-Transcript