# https://www.alkanesolutions.co.uk/2016/05/13/use-adsi-to-check-if-a-user-is-a-member-of-an-ad-group/

# This runs.... at 8am and 5pm? also when you try to connect manually?
. .\logger.ps1
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
    $LL = ($LU.split("\")[1]).split('@')[0]
    $lastUser = $prefix + "\" + $LL    
    Switch ($LU) {
      {$_.contains('@')} {
        $searchprefix = $LU.split("@")[1]
      }
      {$_.contains('\')} {
        $searchprefix = ($LU.split("\")[0]).split('@')[0]
      }
      Default {
        $searchPrefix = ''
      }
    }
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
Write-Log "Enforce Hours Start"

$install_path = "$env:programData\corpvpn"
$global:conf = Get-Content "$install_path\config_params.json" | ConvertFrom-JSON

$userName = (Get-LastUser).user

Write-Log "Last user logged into computer: $userName"

# Try to query the AD for live user info, then save it for later
Try {
  $userObj = ([ADSISearcher] "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$userName))").FindOne()
  $out = @{
    timestamp = Get-Date
    data = $userObj
  }
  $out | Export-CLIXML "$install_path\usercached.xml"
  Write-Log "Querying live user info from domain"
}
# If failed, then load the most recent user info
Catch {
  $userObj = (Import-CLIXML "$install_path\usercached.xml").data
  Write-Log "Using cached user info"
}
Write-Log ('SAMaccountName of user queried from AD: ' + $userObj.properties.samaccountname)

# a couple Boolean values
$isDomainAdmin = (($userObj.properties.memberof -match 'CN=Domain Admins').length -gt 0)
$is24x7        = (($userObj.properties.memberof -match ('CN=' + $conf.adgroup)).length -gt 0)

Write-Log ('Is user domain admin? ' + [string]$isDomainAdmin)
Write-Log ('User allowed 24x7 access? ' + [string]$is24x7)
$activateVPN = $false
if ($isDomainAdmin -or $is24x7) {
  # VPN always active for domain admins or 24x7 users
  $activateVPN = $true
} else {
  $t_start = [DateTime]$conf.time_start
  $t_end   = [DateTime]$conf.time_end
  $now = Get-Date
  if ($now.DayOfWeek -in $conf.work_days) {
    if (($now.timeofday -ge $t_start.timeofday) -and ($now.timeofday -lt $t_end.timeofday)) {
      # VPN allowed within work hours  
      $activateVPN = $true
    } else {
      # VPN not allowed outside work hours
      $activateVPN = $false
    }
  }
}
Write-Log ("ActivateVPN: $activateVPN")

$svc = Get-Service 'OpenVPNService'
Write-Log ("ServiceName: " + $svc.Name + " | Status: " + $svc.Status)

if ($activateVPN -eq $true ) {
  # Work Hours start
  if ($svc.StartupType -eq 'Disabled') {
    # Only modify / start service if its disabled. If its set to auto/manual then it may be off for a reason
    $svc | Set-Service -startupType "Manual"
    Write-Log "Invoking IFUP"
    & "$install_path\ifup.ps1" # instead of starting the service, run ifup.ps1, which will start it only if they are remote
  }
} else {
  Write-Log ("Work Hours end. Disabling VPN")
  # Work Hours end
  $svc | Stop-Service
  $svc | Set-Service -startupType "Disabled"
}

Start-Sleep -Seconds 7
$s = Get-Service 'OpenVPNService'
Write-Log ("ServiceName: " + $s.Name + " | Status: " + $s.Status)
Write-Log "Enforce Office Hours End"