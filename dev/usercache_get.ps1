$script:process = "usercache_get"
. .\_config.ps1
. .\_logger.ps1
. .\_lastuser.ps1
. .\_ADquery.ps1

Write-Log "usercache_get Start"

$userName = (Get-LastUser).user
$cache = "$install_path\usercached.xml"

Write-Log "Last user logged into computer: $userName"

if (Test-Path $cache) {
    
}
# Try to query the AD for live user info, then save it for later
$userObj = ADquery $userName
if (!$userObj) {
    # ADquery returns false if it cannot contact the domain

}


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
#$isDomainAdmin = (($userObj.properties.memberof -match 'CN=Domain Admins').length -gt 0)
#$is24x7        = (($userObj.properties.memberof -match ('CN=' + $conf.adgroup)).length -gt 0)