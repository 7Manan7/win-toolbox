#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates a System Restore point (enabling System Protection on the system drive if needed).
    Windows normally allows only one restore point per 24 hours; this temporarily lifts that limit.
#>
param([string]$Description)

if (-not $Description) {
    $Description = Read-Host 'Restore point name [Manual restore point]'
    if (-not $Description) { $Description = 'Manual restore point' }
}

$sys = $env:SystemDrive + '\'
try { Enable-ComputerRestore -Drive $sys -ErrorAction Stop }
catch { Write-Host "Could not enable System Protection on ${sys}: $_" -ForegroundColor Red; return }

$key  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
$name = 'SystemRestorePointCreationFrequency'
$old  = (Get-ItemProperty $key -Name $name -ErrorAction SilentlyContinue).$name
Set-ItemProperty $key -Name $name -Value 0 -Type DWord

try {
    Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    Write-Host "Restore point created: $Description" -ForegroundColor Green
}
catch { Write-Host "Failed to create restore point: $_" -ForegroundColor Red }
finally {
    if ($null -ne $old) { Set-ItemProperty $key -Name $name -Value $old -Type DWord }
    else { Remove-ItemProperty $key -Name $name -ErrorAction SilentlyContinue }
}

Write-Host "`nLatest restore points:" -ForegroundColor Cyan
Get-ComputerRestorePoint | Sort-Object SequenceNumber -Descending | Select-Object -First 5 |
    Select-Object SequenceNumber, Description,
        @{n = 'Created'; e = { [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) } } |
    Format-Table -AutoSize
