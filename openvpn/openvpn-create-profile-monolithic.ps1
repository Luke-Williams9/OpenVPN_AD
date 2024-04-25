<# ------------------------------------------------- Script init ------------------------------------------------------------------------------------------------- #>

param (
  [switch]$wait,
  [switch]$force,
  [switch]$remove
)

# Ensure we are running in a 64 bit powershell
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

# Delay random amount of time, to ease network congestion
if ($wait) {
  get-random -minimum 10 -maximum 180 | start-sleep
}

# Some global variables
$global:schTaskName = "OpenVPN generate user profile"
$global:install_path = "$env:programData\corpvpn"

<# ------------------------------------------------- Functions --------------------------------------------------------------------------------------------------- #>

function cacheDL () {
	 <#
      .SYNOPSIS
      Efficient web file downloader
      
      .DESCRIPTION
      Downloads a file from the web. 
			If the file is already present, and a matching SHA256 hash is provided, then the download is skipped.
			If a LAN cache SMB address is provided, the file is found on it, and the hash matches, then the LAN cache file will be used instead of downloading.
			
			.PARAMETER name
			The name to save the file as

			.PARAMETER path
			The path to save the file to

			.PARAMETER URL
			The download URL

			.PARAMETER lanCache
			Optional SMB path to check for the file before downloading from the internet.
			This will only work with domain joined computers. Create an SMB share and give SMB / NTFS read access to the 'Domain Computers' group.

			.PARAMETER SHA256
      Optional SHA256 hash, used to verify if a local copy of the file is valid. If it doesn't match (or if left blank) then one will be output by the function.

      .OUTPUTS
      @{
				[string]fullPath
				[string]SHA256
			}

            .EXAMPLE
            $a = cacheDL -name "derp.exe" -path "c:\temp" -URL "https://derp.com/aNotSketchyBinary.exe" -lanCache "\\server.domain.ad\fileshare"

			.EXAMPLE
			$dlSplat = @{
				name = 'derp.exe'
				path = 'c:\temp'
				URL = "https://derp.com/aNotSketchyBinary.exe"
				SHA256 = 'DFFC17B4B0F9C841D94802E2C9578758DBB52CA1AB967A506992C26AABECC43A'
				lanCache = "\\server.domain.ad\fileshare"
			}
			$a = cacheDL @dlSplat
        #>
	[CmdletBinding()]
	param (
		[parameter(Mandatory=$true)][string]$name,
		[parameter(Mandatory=$true)][string]$path,
		[parameter(Mandatory=$true)][string]$URL,
		[string]$lanCache,
		[string]$SHA256
	)
	$dl = $False
	
	if (!(test-path "$path")) {
        Try {
            Write-Verbose "Creating directory:"
            Write-Verbose $path
            mkdir "$path"
        }
        Catch {
            Throw $_
        }		
	}
    # The full path and filename of our download
	$fullName = Join-Path -path $path -childpath $name
	if ($lanCache) {
        # Full path and filename of our LAN cached file
		$netPath = Join-Path -path $lanCache -childpath $name
	}
	# Does it already exist locally?
    Write-Verbose $fullName
	if (Test-Path $fullName) {
		Write-Verbose "Exists locally"
	} else {
		Write-Verbose "Doesn't exist locally"
		$dl = $true
		# Is in a local network cache?
		if ($lanCache) {
			Write-Verbose "Checking network cache for: " 
            Write-Verbose $netPath
			if (Test-Path $netPath) {
				Write-Verbose "Found!"
				Copy-Item $netPath -destination $path
				Write-Verbose "Copying to: " 
                Write-Verbose $path
				$dl = $false
			} else {
			    Write-Verbose "... Not found."
			}
		}  
	}
	# Does the SHA256 hash match?
	if (!$dl) {
        $oldHash = (Get-Filehash $fullName -algorithm SHA256).Hash 
		if ($oldHash -ne $SHA256) {
			Write-Verbose "Filehash mismatch. redownloading..."
			Remove-Item $fullName
			$dl = $true
		} else {
			Write-Verbose "Filehash matches."
            $newHash = $oldHash
		}
	}
	# Download the file?
	if ($dl) {
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Verbose "Download URL:"
        Write-Verbose $URL
		Try {
			(New-Object System.Net.webClient).DownloadFile($URL,"$fullName")  
		}
		Catch {
			throw $_
		}
		$newHash = (Get-Filehash $fullName -algorithm SHA256).hash
		Write-Verbose "Download path:" 
        Write-Verbose $fullName
		Write-Verbose 'To avoid unnecessary re-downloads of this file, provide this function with the followins SHA256 hash: '
		Write-Verbose $newHash
		if ($cache) {
			Write-Verbose "And copy the file to " $netPath.substring(0,$netPath.lastIndexOf('\'))
		}
	}
	return [PSCustomObject] @{
		fullName = $fullName
		SHA256 = $newHash
	}
}

function Get-LastUser () {
  [cmdletbinding()]
  Param ()
  # https://github.com/imabdk/PowerShell/blob/master/Edit-HKCURegistryfromSystem.ps1
  $cim = Get-CimInstance Win32_ComputerSystem
  $LU = (get-itemproperty -path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI" -Name "LastLoggedOnUser" -errorAction SilentlyContinue).LastLoggedOnUser.toLower()
  if (!$LU) {
    $LU = $cim.username
  }
  if ($LU) {
    if ($cim.domainRole -eq 0) {
      # domain role 0 = standalone / non domain joined computer
      $NetBIOSname = ''
      $domainDNSname = ''
    } else {
      # any nonzero domain role means the computer is part of a domain
      $NetBIOSname = ([ADSI]('LDAP://' + $cim.Domain)).dc
      $domainDNSname = $cim.Domain
    }
    # Parse $userProfileName - for domain users it needs to be in the format "domain\username", for local accounts, it needs to be "computername\username"... or it can be a UPN / email address
    $prefix = $env:userdomain
    
    Switch ($LU) {
      {$_.contains('@')} {
        $searchprefix = $LU.split("@")[1]
        $LL = $LU.split('@')[0]
      }
      {$_.contains('\')} {
        $searchprefix = ($LU.split("\")[0]).split('@')[0]
        $LL = $LU.split("\")[1]
      }
      Default {
        $searchPrefix = ''
      }
    }
    $lastUser = $prefix + "\" + $LL
    if (($searchPrefix -notin '',$null) -and (($searchPrefix -eq $NetBIOSname) -or ($searchPrefix -eq $domainDNSname))) {
      $accType = "Domain"
    } else {
      $LocalU = Get-LocalUser -name $LL -ea 'SilentlyContinue'
      if ($LocalU.count -gt 0) {
        $accType = $LocalU.PrincipalSource 
      } else {
        $accType = 'Unknown'
      }
    }
    

    $prc = Get-Process -IncludeUserName | Select-Object -Unique -Property UserName
    $isloggedIn = ($LastUser -in $prc.UserName)
    Write-Verbose ("Current/Last user: " + $LastUser)
    Write-Verbose ("Currently Logged in? " + $isLoggedIn)
    # Find the profile path
    Try {
      $User = New-Object System.Security.Principal.NTAccount($LastUser)
      $LastUserSID = $User.Translate([System.Security.Principal.SecurityIdentifier]).value
      Write-Verbose ("SID: " + $LastUserSID)
      $userProfilePath = (gwmi Win32_UserProfile -filter "SID='$LastUserSID'").LocalPath
    }
    Catch {
      Write-Verbose $_
      $userProfilePath = "Unknown"
    }
    Write-Verbose ("Profile path: " + $userProfilePath)
  } else {
    Write-Verbose $_
    Throw "Error - Could not determine last user."
  }
  Return [PSCustomObject] @{
    prefix = $prefix
    user = $LL
    userName = $LastUser
    isLoggedIn = $isLoggedIn
    profilePath = $userProfilePath
    accountType = $accType
    SID = $LastUserSID
  }
}

function Remove-Program () {
  [CmdletBinding()]
  param (
    [parameter(position=0)][string]$pName
  )
  $pName = 'OpenVPN'
  $search = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
  $installed = Get-ChildItem -Path $search | Get-ItemProperty | Where DisplayName -match $pName
  
  Foreach ($i in $installed) {
    cmd /c $i.UninstallString /qn
  }
  
  $leftOver = Get-ChildItem -Path $search | Get-ItemProperty | Where DisplayName -match $pName
  
  if ($leftOver) {
    Write-Verbose "Problems uninstalling $pName. Installations still found:"
    $result = ($leftOver | FL | Out-String)
    Write-Verbose $result
    
  } else {
    Write-Verbose "Successfully uninstalled $pName."
    $result = $true
  }
  
  if ($result -eq $true) {
    $procs = Get-Process 'openvpn-gui' -erroraction silentlycontinue
    if ($procs) {
      foreach ($p in $procs) {
        Stop-Process -id $p.id -force
      }
    }
  }
  
  return $result
}

function Cleanup-OVPNprofiles () {
  # Clear out old OpenVPN profiles
  $users = (Get-ChildItem "$env:systemdrive\Users").FullName
  $users += @(
      "$env:programfiles",
      "${env:programfiles(x86)}"
  )
  Foreach ($u in $users) {
      $path = "$u\OpenVPN"
      if (Test-Path $path) {
          Remove-Item ($path + "\config-auto\*") -Recurse -Force -erroraction SilentlyContinue
          Remove-Item ($path + "\config\*") -Recurse -Force -erroraction SilentlyContinue
          Remove-Item ($path + "\log\*") -Recurse -Force -erroraction SilentlyContinue
      }
  }
  Remove-Item $install_path -Recurse -Force -erroraction SilentlyContinue
  return $true
}

function Remove-SchTask () {
  param (
    [parameter(position=0)]$n
  )
  if (Get-ScheduledTask $n -errorAction silentlyContinue) {
    Unregister-ScheduledTask $n -confirm:$false
    return $true
  } else {
    return $false
  }
}

<# ------------------------------------------------- Optional Removal  ------------------------------------------------------------------------------------------- #>

# Remove reg HKCU\SOFTWARE\OpenVPN*
# kill OpenVPN-GUI.exe process, it sometimes is still running after uninstall
# delete $install_path

if ($remove) {
  $a = Remove-Program "OpenVPN" -verbose
  if ($a -eq $true) { 
    Cleanup-OVPNprofiles
    Remove-SchTask $schTaskName
    exit 0 
  } 
  else { 
    exit 1 
  }
}

<# ------------------------------------------------- VPN Parameters ---------------------------------------------------------------------------------------------- #>

# ***************** These should all come from org custom fields

# config_params.json
$conf = @{
    x509 = "my.vpn.tld"
    remoteIP = "1.2.3.4"
    rootCA = "CA-Name"
    configName = "FileName-for-clientconfig"
    ca = "CA-Name"
    remotePort = "1194"
}

<# ------------------------------------------------- Embedded file - config.ovpn.template ------------------------------------------------------------------------ #>

$config_ovpn_template = @'
# Auto generated OpenVPN config file

verb 4
dev tun
persist-tun
persist-key
data-ciphers AES-128-GCM:AES-192-GCM:AES-256-GCM:AES-128-CBC:CHACHA20-POLY1305
data-ciphers-fallback AES-128-CBC
auth SHA256
tls-client
client
resolv-retry infinite
remote <<remoteIP>> <<remotePort>> udp4
setenv opt block-outside-dns
nobind
verify-x509-name <<x509>> name
auth-user-pass
ca <<file_ca>>
cryptoapicert "THUMB:<<thumbprint>>"
tls-auth <<file_key>> 1 
remote-cert-tls server
explicit-exit-notify
'@

<# ------------------------------------------------- Embedded file - generate_ovpn_config.ps1 -------------------------------------------------------------------- #>

$generate_ovpn_config = @'
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
'@

<# ------------------------------------------------- Embedded file - static.key ---------------------------------------------------------------------------------- #>

# ****************************** This should also be defined in an org custom field

$static_key = @'
#
# 2048 bit OpenVPN static key
#
-----BEGIN OpenVPN Static key V1-----
abcdef1234567890abcdef1234567890
-----END OpenVPN Static key V1-----
'@

<# ------------------------------------------------- Define and create folders / files --------------------------------------------------------------------------- #>


New-Item -itemType 'Directory' -Path $install_path -ErrorAction SilentlyContinue

$conf | ConvertTo-JSON -depth 100 | Out-File "$install_path\config_params.json"
$config_ovpn_template | Out-File "$install_path\config.ovpn.template"
$generate_ovpn_config | Out-File "$install_path\generate_ovpn_config.ps1"
$static_key | Out-File "$install_path\static.key"

<# ------------------------------------------------- Clean up old profiles --------------------------------------------------------------------------------------- #>


# Clear out old OpenVPN profiles
$users = (Get-ChildItem "$env:systemdrive\Users").FullName
$users += @(
    "$env:programfiles",
    "${env:programfiles(x86)}"
)
Foreach ($u in $users) {
    $path = "$u\OpenVPN"
    if (Test-Path $path) {
        Remove-Item ($path + "\config-auto\*") -Recurse -Force -erroraction SilentlyContinue
        Remove-Item ($path + "\config\*") -Recurse -Force -erroraction SilentlyContinue
        Remove-Item ($path + "\log\*") -Recurse -Force -erroraction SilentlyContinue
    }
}

<# ------------------------------------------------- Get latest OpenVPN version, decide if it needs to be installed ---------------------------------------------- #>

# Try getting the latest installer URL from the OpenVPN website. If that fails, then just use the static URL
Try {
  $downloadURL = ((Invoke-WebRequest -URI "https://openvpn.net/community-downloads/" -useBasicParsing).links | Where-Object href -match 'amd64.msi$').href[0]  
}
Catch {
  $_
  $downloadURL = 'https://swupdate.openvpn.org/community/releases/OpenVPN-2.6.8-I001-amd64.msi'
}

Write-Host "Using download URL: " $downloadURL
# Get the current installer version, turn it into an integer so we can compare with an installed version
$match = [regex]::Match($downloadURL, '\d+\.\d+\.\d+')
if ($match.Success) {
    $currentversion = [system.version]$match.Value
} else {
    # If we can't extract the version from the URL, then just install it anyways
    $currentVersion = [system.version]'0.0.0'
}

$installInfo = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where DisplayName -match 'OpenVPN')
if ($installinfo) {
  Write-Host "Installed OpenVPN version: " $installInfo.DisplayVersion
  $match2 = [regex]::Match($installInfo.displayversion,'\d+.\d+.\d')
  $installedVersion = [system.version]$match2.Value
} else {
  $installedVersion = [system.version]'0.0.0'
}

$install = $false
if ($installedVersion.major -eq 0 -or $currentVersion.major -eq 0) {
  # Run the installer if any part of this version check failed
  $install = $true
}
if ($currentVersion -gt $installedVersion) {
  # Run the installer if currently installed version is older than the available version
  $install = $true
}

if (!($install)) {
  Write-Host "Skipping OpenVPN install"
}

<# ------------------------------------------------- Remove old OpenVPN, download and install new one ------------------------------------------------------------ #>

if ($install -or $force) {
  Write-Host "Installing / Updating OpenVPN client..."
  $a = Remove-Program "OpenVPN" -verbose
  if ($a -ne $true) {
    Write-Host "Error removing OpenVPN."
    exit 1
  }
  
  <# Install latest version #>
  # $lanCache = Ninja-Property-Docs-Get-Single "Local Software Caches" "lanCache"
  $lanCache = ''
  $file = @{
    name = "OpenVPNinstaller.msi"
  	path = "$env:programdata\gsit"
  	lanCache = $lanCache
  	URL = $downloadURL
  	sha256 = "DAA5B0271CD39AE88395F45120A3CB4ADAA8F0BB68CC94627FDEBF15425C0079"
  }
  
  # Download the installer, unless its already present and the hash matches
  $installer = cacheDL @file
  if (!$?) {
    $installer
    exit 1
  }
  
  # Install options
  $install_Options = @(
    'OpenVPN.GUI',
    'OpenVPN.Service',
    'OpenVPN.Documentation',
    'OpenVPN.SampleCfg',
    'Drivers.OvpnDco',
    'OpenVPN',
    'OpenVPN.GUI.OnLogon',
    'OpenVPN.PLAP.Register',
    'Drivers',
    'Drivers.TAPWindows6',
    'Drivers.Wintun'
  )
  
  $addLocal = ' ADDLOCAL=' + ($install_Options -join(','))
  # Install 
  $procSplat = @{
    FilePath = "$env:windir\system32\msiexec.exe"
    ArgumentList = '-i ' + $installer.fullName + $addLocal + ' /quiet /qn /norestart'
    Wait = $true
  }
  Write-Host "Installing..."
  Start-Process @procSplat
  
  if (Get-Service -name $svc -erroraction silentlycontinue) {
    Write-Host "Success!"
  } Else {
    Write-Error "Error installing OpenVPN"
    Exit 1
  }
}

<# ------------------------------------------------- Set up Scheduled task to generate OVPN profile -------------------------------------------------------------- #>

# To access an AD users' certificate, the OpenVPN config needs to be generated within the users context
# We will create a scheduled task to run the generator script on login of the current user

$usr = Get-LastUser
$usr | FL

$psPath = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" 
$desktopIns = "$install_path\generate_ovpn_config.ps1"


$task = @{
    taskName = $schTaskName
    Description = 'Regenerate OpenVPN profile on login, to ensure current certificates are used'
    Trigger = $(New-ScheduledTaskTrigger -AtLogon -user $Usr.UserName)
    User = $usr.UserName
    Force = $true
    Settings = $(New-ScheduledtaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:20:00)
    Action = @(
        New-ScheduledTaskAction -execute $psPath -Argument ('-file "' + $desktopIns + '"' + ' -WindowStyle Hidden') -workingDirectory $install_path
    )
}

# Remove duplicate tasks if present
Remove-SchTask $schTaskName

# Register + start the task
Register-ScheduledTask @task
Start-ScheduledTask $task.taskName

# Wait until its complete
Do {
    $taskState = Get-ScheduledTask $task.taskName 
    Start-Sleep -seconds 5
    $taskState
} while ($taskState.state -eq 'Running')

# Check the result code
$result = Get-ScheduledTaskInfo $task.taskName
if ($result.LastTaskResult -eq 0) {
    Write-Host "Task ran successfully."
} else {
    Write-Host "Error running task. Last result code " $result.lastRunResult
}
