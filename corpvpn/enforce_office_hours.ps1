<#
    OpenVPN Office hours enforcement
    By Luke Williams
    
    Version 0.7

    This script checks if the current users is in a 24x7 users security group. 
    If not, then it disables the VPN service outside of business hours.

    https://www.alkanesolutions.co.uk/2016/05/13/use-adsi-to-check-if-a-user-is-a-member-of-an-ad-group/
#>

# This runs.... at 8am and 5pm? also when you try to connect manually?
param (
  [switch]$bootstrap # Start VPN first, to query AD about the last user
)
$script:process = "enforce"
. .\_logger.ps1
. .\_lastuser.ps1
. .\_config.ps1

Write-Log "__Enforce Hours Start"
$svc = Get-Service 'OpenVPNService'

# Store a list of user objects, so when users switch, their permissions can be read accurately
$cache = "$install_path\userscache.xml"
If (Test-Path $cache) {
  $users = Import-CLIXML $cache
} Else {
  $users = @()
}

if ($bootstrap) {
  Write-Log "Bootstrap param specified. Starting OpenVPN service to query user info from AD"
  $svc | Set-Service -startuptype Manual 
  $svc | Start-Service
  Start-Sleep -seconds 2
  Write-Log ("Service check | " + $svc.Name + " status: " + $svc.Status)
}


$lastUser = Get-LastUser
$userName = $lastUser.user
Write-Log ('Last User: ' + $userName)

if ($lastUser.accountType -ne 'Domain') {
  Write-Log "User is not a domain user. Disabling VPN"
  $svc | Stop-Service
  $svc | Set-Service -startupType "Disabled"
  Write-Log "Enforce_work_hours Abort"
  Exit 0
}

Try {
  Write-Log ("Service check | " + $svc.Name + " status: " + $svc.Status)
  Write-Log "Trying live ADSI query"
  $userObj = ([ADSISearcher] "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$userName))").FindOne()
  Write-Log ("Result: " + $userObj | Select-Object *)
  $result = @{
    timestamp = Get-Date
    data = $userObj
  }
  # Update users cache
  Foreach ($i in (0..($users.length))) {
    if ($users[$i]) {
      $users[$i] = $result
      $updated = $true
      Write-Log ('Found cached user. Updating #' + $i)
      Break
    } 
  }
  # If the user was not found, then append it
  if (!($updated)) {
    Write-Log ('User not previously cached. Appending to cache')
    $users += $result
  }
}
# If failed, then load the most recent user info
Catch {
  Write-Log $_
  Write-Log "ADSI query failed. Checking local user cache"
  $u = $users | Where-Object {$_.Data.Properties.samaccountname -eq $userName}
  if ($u) {
    Write-Log "Using cached user info"
    $userObj = $u.data
  } else {
    Write-Host "Cannot determine user permissions. Disabling VPN"
    $svc | Stop-Service
    $svc | Set-Service -startupType "Disabled"
    Write-Log "Enforce_work_hours Abort"
    Exit 0
  }
  
}


$out | Export-CLIXML $cache

Write-Log ('SAMaccountName of user queried from AD: ' + $userObj.properties.samaccountname)

# a couple Boolean values
$isDomainAdmin = (($userObj.properties.memberof -match 'CN=Domain Admins').length -gt 0)
$is24x7        = (($userObj.properties.memberof -match ('CN=' + $conf.adgroup)).length -gt 0)

Write-Log ('Is user domain admin? ' + [string]$isDomainAdmin)
Write-Log ('User allowed 24x7 access? ' + [string]$is24x7)
$activateVPN = $false
if ($isDomainAdmin -or $is24x7) {
  Write-Log "User is permitted 24x7 access"
  # VPN always active for domain admins or 24x7 users
  $activateVPN = $true
} else {
  
  Write-Log "Running time of day check"
  $t_start = [DateTime]$conf.time_start
  $t_end   = [DateTime]$conf.time_end
  $now = Get-Date
  Write-Log ('Current time of day: ' + $now.timeOfDay)
  Write-Log ('Work hours begin: ' + $t_start.timeOfDay)
  Write-Log ('Work hours end  : ' + $t_end.timeOfDay)
  
  if ($now.DayOfWeek -in $conf.work_days) {
    if (($now.timeofday -ge $t_start.timeofday) -and ($now.timeofday -lt $t_end.timeofday)) {
      # VPN allowed within work hours
      Write-Log "Current time is within work hours"  
      $activateVPN = $true
    } else {
      # VPN not allowed outside work hours
      Write-Log "Current time is outside of work hours"  
      $activateVPN = $false
    }
  }
}
Write-Log ("ActivateVPN: $activateVPN")


Write-Log ("Service check | " + $svc.Name + " status: " + $svc.Status)

if ($activateVPN -eq $true) {
  $svc | Set-Service -startupType "Manual"
  Write-Log "Invoking IFUP"
  & "$install_path\ifup.ps1" # instead of starting the service, run ifup.ps1, which will start it only if they are remote
} else {
  Write-Log ("Work Hours end. Disabling VPN")
  # Work Hours end
  $svc | Stop-Service
  $svc | Set-Service -startupType "Disabled"
}

Start-Sleep -Seconds 7
Write-Log ($svc.Name + " status: " + $svc.Status)
Write-Log "__Enforce Office Hours End"