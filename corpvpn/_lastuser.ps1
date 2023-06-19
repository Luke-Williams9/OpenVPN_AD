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
        $NetBIOSname = $env:userdomain
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