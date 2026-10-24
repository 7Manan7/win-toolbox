#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Checks for and installs Windows updates using the PSWindowsUpdate module
    (installed automatically from the PowerShell Gallery if missing).
.PARAMETER ListOnly
    Only list available updates.
.PARAMETER AutoReboot
    Reboot automatically if an update requires it.
#>
param([switch]$ListOnly, [switch]$AutoReboot)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Host 'Installing PSWindowsUpdate module (one time)...' -ForegroundColor Cyan
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
        Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -ErrorAction Stop
    }
    catch {
        Write-Host "Could not install PSWindowsUpdate: $_" -ForegroundColor Red
        return
    }
}
Import-Module PSWindowsUpdate

Write-Host 'Checking for updates...' -ForegroundColor Cyan
$updates = @(Get-WindowsUpdate)
if ($updates.Count -eq 0) { Write-Host 'Windows is up to date.' -ForegroundColor Green; return }

$updates | Format-Table KB, Size, Title -AutoSize -Wrap
if ($ListOnly) { return }

$ans = Read-Host "Install $($updates.Count) update(s)? [y/N]"
if ($ans -notmatch '^[Yy]') { return }

if ($AutoReboot) { Install-WindowsUpdate -AcceptAll -AutoReboot }
else { Install-WindowsUpdate -AcceptAll -IgnoreReboot }

if (Get-WURebootStatus -Silent) {
    Write-Host "`nA restart is required to finish installing updates." -ForegroundColor Yellow
    $r = Read-Host 'Restart now? [y/N]'
    if ($r -match '^[Yy]') { Restart-Computer -Force }
}
else { Write-Host "`nDone. No restart needed." -ForegroundColor Green }
