<#
    OpenVPN configuration file generator for AD-integrated VPN
    By Luke Williams
    
    Version 0.8

    This script generates a new OpenVPN configuration for the current AD user
    It will use an AD-CA issued certificate, same type that can be used for wifi authentication
    The certificates have a shorter renewal time (ie less than a year) so this script will need to run periodically to update the openVPN configuration.

    This script will assume that the tls key file has already been written to the openVPN config folder.
#>

$ErrorActionPreference = 'Stop'
$logPath = "$env:userprofile\OpenVPN"
New-Item -ItemType Directory -path $logPath -force | Out-Null
$banner = @"

   ____               __      _______  _   _ 
  / __ \              \ \    / /  __ \| \ | |
 | |  | |_ __   ___ _ _\ \  / /| |__) |  \| |
 | |  | | '_ \ / _ \ '_ \ \/ / |  ___/| . ` |
 | |__| | |_) |  __/ | | \  /  | |    | |\  |
  \____/| .__/ \___|_| |_|\/   |_|    |_| \_|
        | |                                  
        |_|                                  


"@
Write-Host $banner -ForegroundColor green
Start-Transcript -path "$logPath\generate-log.txt"
Write-Host "Generate OpenVPN Config Start"
$conf = Get-Content "$PSScriptRoot\config_params.json" | ConvertFrom-JSON

$svc = Get-Service 'OpenVPNService'
Write-Host ($svc.Name + " status: " + $svc.Status)
Write-Host ("Root CA:    " + $conf.rootCA)
Write-Host ("Issuing CA: " + $conf.ca)

# File Names
$file_ovpn = $conf.configName + '.ovpn'

# Parameters to replace in the config file
$params = @{
    remoteIP = $conf.remoteIP
    remotePort = $conf.remotePort
    x509 = $conf.x509
    file_ca = $conf.rootCA + '.crt'
    file_key = $conf.configName + '-tls.key'
    thumbprint = ''
}

# Config file template. Anything between <<>> is a variable which will be replaced with corresponding values from $conf
# add "verb 4" to the config, to increase verbosity for troubleshooting
$configFile = Get-Content 'config.ovpn.template'

# Static key from OpenVPN server settings in pfSense - replace the contents of static.key with your own
$static_key = Get-Content 'static.key'

# Get the CA Cert, error out if not present
Write-Host ("Looking for CA certificate for " + $conf.rootCA)
$ca_cert = Get-ChildItem -path cert:\LocalMachine\Root | Where-Object Subject -match $conf.rootCA
if (!($ca_cert)) {
    Write-Host "No CA found - Cannot continue"
    Exit 1
}
Write-Host "Found!"

# Get the thumbprint for the certificate issued by $conf.ca, error out if not present
Write-Host ("Looking for Client Authentication certificate, issued from " + $conf.ca)
$cert = Get-ChildItem -path cert:\CurrentUser\My | Where-Object {
    ($_.issuer -match $conf.ca) `
    -and ((Get-Date) -gt $_.notBefore) `
    -and ((Get-Date) -lt $_.notAfter) `
    -and $_.EnhancedKeyUsageList.count -eq 1 `
    -and $_.EnhancedKeyUsageList.friendlyName -eq 'Client Authentication'
} | Sort-Object -property NotAfter | Select-Object -last 1

if (!($cert)) {
    Write-Host "No certificate found, cannot continue"
    Exit 1
}
Write-Host "Found!"

# Create config folder
$basePath = "$env:userProfile\OpenVPN\config\"
if (!(Test-Path $basePath)) {
    $dirsplat = @{
        ItemType = 'Directory'
        Path = $basePath
        Force = $true
        ErrorAction = 'SilentlyContinue'
    }
    New-Item @dirsplat
}
Write-Host ("Config path: " + $basePath)

# Save Static Key
$static_key_path = $basePath + $params.file_key
$static_key | Out-File $static_key_path -encoding ascii
Write-Host ("Saved static key to " + $static_key_path)

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
$ca_file = $basePath + $params.file_ca
Write-Output ("CA Certificate: `n" + $ca_b64 + "`n`n")

$ca_b64 | Out-File $ca_file -encoding ascii
Write-Host ("Saved CA certificate to " + $ca_file)

# Generate ovpn-readable client cert thumbprint
$params.thumbprint = ($cert.Thumbprint -replace '([0-9a-f]{2})', '$1 ').ToLower().trim()

Write-Output ("Client certificate: `n" + ($cert | Select-Object Subject, Issuer, Thumbprint, FriendlyName, NotBefore, NotAfter, EnhancedKeyUsageList| Format-List | Out-String))
Write-Host ('Using Client certificate "' + $cert.Subject + '"')
Write-Host ('certifcate thumbprint: ' + $cert.Thumbprint)

# Loop through conf, and replace parameters in configFile
foreach ($k in $params.keys) {
    $search = "<<" + $k + ">>"
    $configFile = $configFile.replace($search,$params.$k)
}

Write-Host "Stopping OpenVPN GUI"
# Stop the OpenVPN GUI process before writing the config
$procs = Get-Process 'openvpn-gui' -erroraction silentlycontinue
if ($procs) {
  $ovpn_gui_path = $procs[0].Path
  foreach ($p in $procs) {
    Stop-Process -id $p.id -force
  }
}

Write-Output ("Configuration:`n" + $configFile + "`n`n")
$configFile_path = $basePath + $file_ovpn
$configFile | Out-File $configFile_path  -encoding ascii
Write-Host ("Saved configuration to " + $configFile_path + "`n")

# Define the registry path and the config name
$regPath = "HKCU:\Software\OpenVPN-GUI\configs"
$configName = $conf.configName
$fullPath = "$regPath\$configName"

# Check if the registry key exists
if (-not (Test-Path $fullPath)) {
    Write-Host "Setting default username"
    New-Item -Path $regPath -Name $configName -Force
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($env:username)
    Set-ItemProperty -Path $fullPath -Name "username" -Value $bytes -Type Binary
}
Write-Host "Starting OpenVPN GUI"
Start-Process $ovpn_gui_path
Write-Host "Completed generating OpenVPN profile."
Stop-Transcript