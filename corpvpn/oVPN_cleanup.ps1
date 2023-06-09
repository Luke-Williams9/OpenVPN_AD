
<# Clean up previous OVPN install #>
$search = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
$installed = Get-ChildItem -Path $search | Get-ItemProperty | Where-Object DisplayName -match "OpenVPN"

Foreach ($i in $installed) {
  cmd /c $i.UninstallString /qn
}
<##>

# Clear out old profiles
$users = (Get-ChildItem "$env:systemdrive\Users").FullName
$users += @(
    "$env:programfiles",
    "${env:programfiles(x86)}"
)
Foreach ($u in $users) {
    $path = "$u\OpenVPN"
    if (Test-Path $path) {
        Remove-Item ($path + "\config-auto\*") -Recurse -Force -erroraction SilentlyContinue
        Remove-Item ($path + "\config\*") -Recurse -Force
        Remove-Item ($path + "\log\*") -Recurse -Force
    }
}

# Delete tasks
$tasklist = Get-ScheduledTask -taskPath "\corpVPN\*"
if ($tasklist) {
    foreach ($t in $tasklist) {
        write-host "Removing task" $t.Taskname
        Unregister-ScheduledTask -TaskName $t.TaskName -confirm:$false
    }
}

# Delete script folder
Remove-Item -path "$env:programData\corpvpn" -recurse -force -confirm:$false -erroraction silentlycontinue