<powershell>
# Don't display progress bars
# See: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables?view=powershell-7.3#progresspreference
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy Unrestricted

Write-Host "Disabling anti-virus monitoring"
Set-MpPreference -DisableRealtimeMonitoring $true

Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

Set-Service -Name sshd -StartupType 'Automatic'
Start-Service sshd

# Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Select-Object Name, Enabled)) {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
} else {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
}

# Set the default shell to Powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force

$openSSHDownloadKeyScript = Join-Path $env:ProgramData 'ssh\download-key-pair.ps1'

$keyDownloadScript = @'
# Download instance key pair to $env:ProgramData\ssh\administrators_authorized_keys
$openSSHAuthorizedKeys = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'

$keyUrl = "http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key"
$keyReq = [System.Net.WebRequest]::Create($keyUrl)
$keyResp = $keyReq.GetResponse()
$keyRespStream = $keyResp.GetResponseStream()
    $streamReader = New-Object System.IO.StreamReader $keyRespStream
$keyMaterial = $streamReader.ReadToEnd()

$keyMaterial | Out-File -Append -FilePath $openSSHAuthorizedKeys -Encoding ASCII

# Ensure ACL for administrators_authorized_keys is correct
icacls.exe $openSSHAuthorizedKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"

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

# Restart to ensure public key authentication works and SSH comes up
Restart-Computer
</powershell>
