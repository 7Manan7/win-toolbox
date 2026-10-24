<#
.SYNOPSIS
    Shows drive usage, the biggest folders and the biggest files under a path.
.EXAMPLE
    .\Disk-SpaceReport.ps1 -Path C:\Users -Top 20 -MinFileMB 100
#>
param(
    [string]$Path,
    [int]$Top = 15,
    [int]$MinFileMB = 50,
    [switch]$SkipFiles
)

if (-not $Path) {
    $Path = Read-Host 'Path to analyze [C:\]'
    if (-not $Path) { $Path = 'C:\' }
}
if (-not (Test-Path $Path)) { Write-Host "Path not found: $Path" -ForegroundColor Red; return }

Write-Host "`n--- Drives ---" -ForegroundColor Cyan
Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    [pscustomobject]@{
        Drive     = $_.DeviceID
        'Size GB' = [math]::Round($_.Size / 1GB, 1)
        'Free GB' = [math]::Round($_.FreeSpace / 1GB, 1)
        'Used %'  = [math]::Round(100 * ($_.Size - $_.FreeSpace) / $_.Size)
    }
} | Format-Table -AutoSize

Write-Host "--- Largest folders in $Path ---" -ForegroundColor Cyan
$dirs = @(Get-ChildItem $Path -Force -Directory -ErrorAction SilentlyContinue |
    Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
$i = 0
$rows = foreach ($d in $dirs) {
    $i++
    Write-Progress -Activity 'Measuring folders' -Status $d.Name -PercentComplete (100 * $i / [math]::Max(1, $dirs.Count))
    $sum = (Get-ChildItem $d.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum).Sum
    [pscustomobject]@{ 'Size GB' = [math]::Round($sum / 1GB, 2); Folder = $d.FullName }
}
Write-Progress -Activity 'Measuring folders' -Completed
$rows | Sort-Object 'Size GB' -Descending | Select-Object -First $Top | Format-Table -AutoSize

if (-not $SkipFiles) {
    Write-Host "--- Largest files (>= $MinFileMB MB) - this can take a while ---" -ForegroundColor Cyan
    Get-ChildItem $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge ($MinFileMB * 1MB) } |
        Sort-Object Length -Descending | Select-Object -First $Top |
        Select-Object @{n = 'Size MB'; e = { [math]::Round($_.Length / 1MB) } }, FullName |
        Format-Table -AutoSize -Wrap
}
