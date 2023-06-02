[CmdletBinding()]
param (
    [switch]$wait
)

# OpenVPN client installer
# By Luke Williams

# Make this script run in a 64 bit powershell... NINJARMM WHY YOU NO PREFER 64 BIT SHELL??
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
function serviceFound () {
  param (
    [parameter(position=0)][string]$svc
  )
  return (Get-Service -name $svc -erroraction silentlycontinue)
}

# Delay random amount of time, to ease network congestion
if ($wait) {
  get-random -minimum 10 -maximum 180 | start-sleep
}

# Try getting the lastest installer URL from the OpenVPN website. If that fails, then just use the static URL
Try {
  $downloadURL = ((Invoke-WebRequest -URI "https://openvpn.net/community-downloads/" -useBasicParsing).links | Where-Objecthref -match 'amd64.msi$').href[0]  
}
Catch {
  $_
  $downloadURL = 'https://swupdate.openvpn.org/community/releases/OpenVPN-2.6.3-I001-amd64.msi'
}

# This script was built originally in NinjaOne RMM, using a LAN cache download system I built. (the cacheDL function)
# If you set $lanCache to a UNC path for the installer, and ensure the $file.sha256 hash is correct, then cacheDL will use the local file. Otherwise it will download from the internet.
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

# Install options - Don't install GUI options, since autoconfig doesn't support the GUI
$install_Options = @(
  #'OpenVPN.GUI',
  'OpenVPN.Service',
  'OpenVPN.Documentation',
  'OpenVPN.SampleCfg',
  'Drivers.OvpnDco',
  'OpenVPN',
  #'OpenVPN.GUI.OnLogon',
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

if (serviceFound "OpenVPNService") {
  Write-Host "Success!"
}


# -------------------------------

# Configure service security, allow user to stop/start the service (but not disable / enable):
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