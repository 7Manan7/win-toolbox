<#
.SYNOPSIS
    Backs up your important folders to another drive/partition using robocopy, with a dated log.
    Default mode only copies new/changed files (never deletes anything in the backup).
    -Mirror makes the backup an exact copy, DELETING files from the backup that no longer exist in the source.
.EXAMPLE
    .\Backup-Folders.ps1 -Destination E:\Backups
.NOTES
    Auto-detects available backup drives and standard folders.
#>
param(
    [string[]]$Sources,
    [string]$Destination,
    [switch]$Mirror
)

# ------------ config ------------
# Auto-detect secondary backup drive if present; otherwise fallback to system drive
$backupDrive = (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue |
    Where-Object { $_.DeviceID -ne $env:SystemDrive } | Select-Object -First 1).DeviceID
if (-not $backupDrive) { $backupDrive = $env:SystemDrive }

$DefaultDestination = Join-Path $backupDrive 'Backups'

$suggestedSources = @(
    (Join-Path $HOME 'Projects'),
    (Join-Path $HOME 'Documents\Projects'),
    [Environment]::GetFolderPath('MyDocuments'),
    [Environment]::GetFolderPath('Desktop')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$DefaultSources = if ($suggestedSources.Count -gt 0) { $suggestedSources } else { @([Environment]::GetFolderPath('MyDocuments')) }
$ExcludeDirs    = @('node_modules', 'target', 'build', '.gradle', '.idea', '$RECYCLE.BIN', 'System Volume Information')
# --------------------------------

if (-not $Sources) { $Sources = $DefaultSources }
if (-not $Destination) {
    $d = Read-Host "Backup destination [$DefaultDestination]"
    $Destination = if ($d) { $d } else { $DefaultDestination }
}

$qual = Split-Path -Qualifier $Destination -ErrorAction SilentlyContinue
if (-not $qual -or -not (Test-Path "$qual\")) {
    Write-Host "Destination drive not available: $Destination" -ForegroundColor Red
    return
}

Write-Host "`nSources:" -ForegroundColor Cyan
$Sources | ForEach-Object { Write-Host "  $_" }
Write-Host "Destination: $Destination"
Write-Host ("Mode: {0}" -f $(if ($Mirror) { 'MIRROR (deletes extra files in backup)' } else { 'Copy new/changed files only' }))
Write-Host "Skipping folders named: $($ExcludeDirs -join ', ')`n"

if ($Mirror) {
    $c = Read-Host 'Mirror mode will DELETE files in the backup that are gone from the source. Type YES to continue'
    if ($c -cne 'YES') { Write-Host 'Cancelled.'; return }
}

$logDir = Join-Path $Destination '_logs'
New-Item $logDir -ItemType Directory -Force | Out-Null
$log = Join-Path $logDir ('Backup_{0:yyyyMMdd_HHmmss}.log' -f (Get-Date))

$failed = 0
foreach ($src in $Sources) {
    if (-not (Test-Path $src)) { Write-Host "Skipping (not found): $src" -ForegroundColor Yellow; continue }
    $name = Split-Path $src -Leaf
    if (-not $name) { $name = ($src -replace '[:\\]', '') + '_drive' }
    $dst = Join-Path $Destination $name

    Write-Host ">>> $src  ->  $dst" -ForegroundColor Cyan
    $modeFlag = if ($Mirror) { '/MIR' } else { '/E' }
    $roboArgs = @($src, $dst, $modeFlag, '/R:2', '/W:2', '/MT:8', '/XJ', '/FFT', '/NP', "/LOG+:$log", '/TEE', '/XD') + $ExcludeDirs
    & robocopy.exe @roboArgs | Out-Null

    if ($LASTEXITCODE -ge 8) { $failed++; Write-Host "    Finished with errors (robocopy code $LASTEXITCODE)" -ForegroundColor Red }
    else { Write-Host "    OK (robocopy code $LASTEXITCODE)" -ForegroundColor Green }
}

Write-Host "`nBackup complete. Log: $log" -ForegroundColor $(if ($failed) { 'Yellow' } else { 'Green' })
