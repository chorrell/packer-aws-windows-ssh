$ErrorActionPreference = 'Stop'

$keysFile = [io.path]::combine($env:ProgramData, 'ssh', 'authorized_keys')
Remove-Item -Recurse -Force -Path $keysFile

Enable-ScheduledTask "Download Key Pair"

echo "Running Sysprep Instance"
& "$Env:Programfiles\Amazon\EC2Launch\ec2launch.exe" sysprep
