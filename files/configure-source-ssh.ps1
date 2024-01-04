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

# Move OpenSSH-Win64 into Program Files
Move-Item -Path (Join-Path $env:TEMP 'OpenSSH-Win64') -Destination $openSSHInstallDir

& Powershell.exe -ExecutionPolicy Bypass -File $openSSHInstallScript
if ($LASTEXITCODE -ne 0) {
	throw("Failed to install OpenSSH Server")
}

# Add a firewall for sshd
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

# Start sshd automatically at boot
Set-Service sshd -StartupType Automatic

# Set the default login shell to Powershell
New-Item -Path HKLM:\SOFTWARE\OpenSSH -Force
New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH `
    -Name DefaultShell `
    -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

$keyDownloadScript = @'
# Download instance key pair to $env:ProgramData\administrators_authorized_keys
$openSSHAuthorizedKeys = Join-Path $env:ProgramData 'administrators_authorized_keys'

$keyUrl = "http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key"
$keyReq = [System.Net.WebRequest]::Create($keyUrl)
$keyResp = $keyReq.GetResponse()
$keyRespStream = $keyResp.GetResponseStream()
    $streamReader = New-Object System.IO.StreamReader $keyRespStream
$keyMaterial = $streamReader.ReadToEnd()

$keyMaterial | Out-File -Append -FilePath $openSSHAuthorizedKeys -Encoding ASCII

# Ensure ACL for administrators_authorized_keys is correct
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$dacl = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM","FullControl","Allow")
$acl.SetAccessRule($dacl)
$dacl = New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators","FullControl","Allow")
$acl.SetAccessRule($dacl)
$acl.SetAccessRuleProtection($true,$false)
Set-Acl -Path $openSSHAuthorizedKeys -AclObject $acl

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

# Run the install script, terminate if it fails
& Powershell.exe -ExecutionPolicy Bypass -File $openSSHDownloadKeyScript
if ($LASTEXITCODE -ne 0) {
	throw("Failed to download key pair")
}

# Restart to ensure public key authentication works and SSH comes up
Restart-Computer
</powershell>
