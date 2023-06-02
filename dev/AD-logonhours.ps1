<#
Unfinished script to decode AD user login hours to a set of dateTime objects

#>

<#


if ($userObj.Properties.logonhours) {
  $logonHours = [System.BitConverter]::ToString($userObj.Properties.logonhours[0])
  $array = ($userObj.Properties.logonhours[0] | ForEach-Object {[System.Convert]::ToString($_, 2).PadLeft(8, '0')})
  $days = @()
  for ($i = 0; $i -lt $array.Length; $i += 3) {
      # Swap the second and third elements in the current group of three
      $days += ($array[$i] + $array[$i + 2] + $array[$i + 1])
  }
} else {

}
$days


# Output the modified array
$array
$binaryString = $array -join ''

$days = @()
for ($i = 0; $i -lt $binaryString.length; $i += 24) { 
    if ($i -lt $binaryString.length) {
        $length = [Math]::Min(24, $binaryString.Length - $i)
        $days += $binaryString.substring($i,$length)
    }
}

foreach ($ll in $l) {
    [system.convert]::ToString($ll, 2)
}
#check if user is a member of the group
$ADGroupObj = (([ADSISearcher] "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$userName))").FindOne().properties.memberof -match "CN=$ADGroup,")

if ($ADGroupObj -and $ADGroupObj.count -gt 0) {
    $true # user is member
} else {
    $false
}




# Define the byte array representing the logon hours
$logonHours = 

# Convert the logon hours byte array to a binary string
#$binaryString = [System.String]::Join("", $logonHours | ForEach-Object { [System.Convert]::ToString($_, 2).PadLeft(8, '0') })

# Split the binary string into 7 substrings, one for each day of the week
$dayStrings = $binaryString -split "(?<=.{24})"

# Convert each day's binary string to a TimeSpan object
$dayTimeSpans = $dayStrings | ForEach-Object {
    $hours = [System.String]::Join("", ($_ -split "(?<=.{8})" | ForEach-Object { [System.Convert]::ToInt32($_, 2) }))
    [TimeSpan]::FromHours($hours)
}

#>
