function ADquery () {
    [cmdletBinding()]
    param (
        [Parameter(Position=0)][string]$userName
    )
    # Try to query the AD for live user info, then save it for later
    Try {
        $userObj = ([ADSISearcher] "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$userName))").FindOne()
        $out = @{
            timestamp = Get-Date
            data = $userObj
        }
        Write-Verbose "Result:"
        Write-Verbose ($out.data | Select-Object * | Out-String)
    }
    # If failed, then return $false
    Catch {
        Write-Host "Cannot contact domain"
        $out = $false
    }
    Return $out
}