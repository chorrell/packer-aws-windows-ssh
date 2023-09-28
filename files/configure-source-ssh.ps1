<powershell>
# Don't display progress bars
# See: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables?view=powershell-7.3#progresspreference
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

Write-Host "Disabling anti-virus monitoring"
Set-MpPreference -DisableRealtimeMonitoring $true

# Version and download URL
$openSSHVersion = "7.6.1.0p1-Beta"
$openSSHURL = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v$openSSHVersion/OpenSSH-Win64.zip"

Set-ExecutionPolicy Unrestricted

# Set various known paths
$openSSHZip = Join-Path $env:TEMP 'OpenSSH.zip'
$openSSHInstallDir = Join-Path $env:ProgramFiles 'OpenSSH'
$openSSHInstallScript = Join-Path $openSSHInstallDir 'install-sshd.ps1'
$openSSHDownloadKeyScript = Join-Path $openSSHInstallDir 'download-key-pair.ps1'
$openSSHDaemon = Join-Path $openSSHInstallDir 'sshd.exe'
$openSSHDaemonConfig = [io.path]::combine($env:ProgramData, 'ssh', 'sshd_config')

Write-Host "Donwloading OpenSSH"
Invoke-WebRequest -Uri $openSSHURL -OutFile $openSSHZip

Write-Host "Unzipping OpenSSH"
Expand-Archive $openSSHZip "$env:TEMP"

$ErrorActionPreference = 'SilentlyContinue'
Remove-Item -Force $openSSHZip
$ErrorActionPreference = 'Stop'

# Move into Program Files
Move-Item -Path (Join-Path $env:TEMP 'OpenSSH-Win64') -Destination $openSSHInstallDir

# Run the install script, terminate if it fails
& Powershell.exe -ExecutionPolicy Bypass -File $openSSHInstallScript
if ($LASTEXITCODE -ne 0) {
	throw("Failed to install OpenSSH Server")
}

# Add a firewall rule to allow inbound SSH connections to sshd.exe
New-NetFirewallRule -Name sshd `
    -DisplayName "OpenSSH Server (sshd)" `
    -Group "Remote Access" `
    -Description "Allow access via TCP port 22 to the OpenSSH Daemon" `
    -Enabled True `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 22 `
    -Program "$openSSHDaemon" `
    -Action Allow

# Ensure sshd automatically starts on boot
Set-Service sshd -StartupType Automatic

# Set the default login shell for SSH connections to Powershell
New-Item -Path HKLM:\SOFTWARE\OpenSSH -Force
New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH `
    -Name DefaultShell `
    -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

$keyDownloadScript = @'
# Download the instance key pair and authorize Administrator logins using it
$openSSHAdminUser = 'c:\ProgramData\ssh'
$openSSHAuthorizedKeys = Join-Path $openSSHAdminUser 'authorized_keys'

If (-Not (Test-Path $openSSHAdminUser)) {
    New-Item -Path $openSSHAdminUser -Type Directory
}

$keyUrl = "http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key"
$keyReq = [System.Net.WebRequest]::Create($keyUrl)
$keyResp = $keyReq.GetResponse()
$keyRespStream = $keyResp.GetResponseStream()
    $streamReader = New-Object System.IO.StreamReader $keyRespStream
$keyMaterial = $streamReader.ReadToEnd()

$keyMaterial | Out-File -Append -FilePath $openSSHAuthorizedKeys -Encoding ASCII

# Ensure access control on authorized_keys meets the requirements
$acl = Get-ACL -Path $openSSHAuthorizedKeys
$acl.SetAccessRuleProtection($True, $True)
Set-Acl -Path $openSSHAuthorizedKeys -AclObject $acl

$acl = Get-ACL -Path $openSSHAuthorizedKeys
$ar = New-Object System.Security.AccessControl.FileSystemAccessRule( `
	"NT Authority\Authenticated Users", "ReadAndExecute", "Allow")
$acl.RemoveAccessRule($ar)
$ar = New-Object System.Security.AccessControl.FileSystemAccessRule( `
	"BUILTIN\Administrators", "FullControl", "Allow")
$acl.RemoveAccessRule($ar)
$ar = New-Object System.Security.AccessControl.FileSystemAccessRule( `
	"BUILTIN\Users", "FullControl", "Allow")
$acl.RemoveAccessRule($ar)
Set-Acl -Path $openSSHAuthorizedKeys -AclObject $acl

Disable-ScheduledTask -TaskName "Download Key Pair"

$sshdConfigContent = @"
# Modified sshd_config, created by Packer provisioner

PasswordAuthentication yes
PubKeyAuthentication yes
PidFile __PROGRAMDATA__/ssh/logs/sshd.pid
AuthorizedKeysFile __PROGRAMDATA__/ssh/authorized_keys
AllowUsers Administrator

Subsystem       sftp    sftp-server.exe
"@

Set-Content -Path C:\ProgramData\ssh\sshd_config `
    -Value $sshdConfigContent

'@
$keyDownloadScript | Out-File $openSSHDownloadKeyScript

# Create Task - Ensure the name matches the verbatim version above
$taskName = "Download Key Pair"
$principal = New-ScheduledTaskPrincipal `
    -UserID "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest
$action = New-ScheduledTaskAction -Execute 'Powershell.exe' `
  -Argument "-NoProfile -File ""$openSSHDownloadKeyScript"""
$trigger =  New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -TaskName $taskName `
    -Description $taskName
Disable-ScheduledTask -TaskName $taskName

# Run the install script, terminate if it fails
& Powershell.exe -ExecutionPolicy Bypass -File $openSSHDownloadKeyScript
if ($LASTEXITCODE -ne 0) {
	throw("Failed to download key pair")
}

# Restart to ensure public key authentication works and SSH comes up
Restart-Computer
</powershell>
<runAsLocalSystem>true</runAsLocalSystem>
