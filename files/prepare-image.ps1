$ErrorActionPreference = 'Stop'

Write-Output "Cleaning up keys"
$keysFile = [io.path]::combine($env:ProgramData, 'ssh', 'administrators_authorized_keys')
Remove-Item -Recurse -Force -Path $keysFile

# Make sure task is enabled
Enable-ScheduledTask "Download Key Pair"

Write-Output "Running Sysprep"
& "$Env:Programfiles\Amazon\EC2Launch\ec2launch.exe" sysprep
