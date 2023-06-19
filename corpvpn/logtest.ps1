$script:process = "logtest"
. .\_logger.ps1
Write-Log "hello"


$myInvocation | Export-CLIXML "c:\temp\invoc.xml"