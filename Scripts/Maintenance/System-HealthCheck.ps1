#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Runs disk health check, DISM RestoreHealth, SFC and an online CHKDSK scan, logging everything.
    Log is saved in your Documents folder. Takes 10-40 minutes.
#>
param([switch]$SkipChkdsk)

$log = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('HealthCheck_{0:yyyyMMdd_HHmm}.log' -f (Get-Date))
Write-Host "Logging to: $log`n" -ForegroundColor Cyan

function Run-Step([string]$Title, [scriptblock]$Block) {
    $bar = '=' * 60
    "$bar`n$Title  [$(Get-Date -Format 'HH:mm:ss')]`n$bar" | Tee-Object -FilePath $log -Append
    & $Block 2>&1 | Tee-Object -FilePath $log -Append
    '' | Tee-Object -FilePath $log -Append
}

Run-Step '1/4  Physical disk health' {
    Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus,
        @{n = 'SizeGB'; e = { [math]::Round($_.Size / 1GB) } } | Format-Table -AutoSize | Out-String
}

Run-Step '2/4  DISM - restore component store health' {
    dism.exe /Online /Cleanup-Image /RestoreHealth
}

Run-Step '3/4  SFC - system file checker' {
    $old = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::Unicode   # sfc writes UTF-16
    sfc.exe /scannow
    [Console]::OutputEncoding = $old
}

if (-not $SkipChkdsk) {
    Run-Step "4/4  CHKDSK online scan ($env:SystemDrive)" {
        chkdsk.exe $env:SystemDrive /scan
    }
}

Write-Host "`nDone. Full log: $log" -ForegroundColor Green
Write-Host 'SFC details: %windir%\Logs\CBS\CBS.log'
