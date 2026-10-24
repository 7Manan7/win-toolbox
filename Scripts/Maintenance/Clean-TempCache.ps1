#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Clears temp files, Windows Update download cache, browser caches and the Recycle Bin,
    then reports how much disk space was actually freed.
.NOTES
    Close your browsers first. Use -WhatIf to preview. Use -SkipBrowsers to leave browser caches alone.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$SkipBrowsers)

$ErrorActionPreference = 'SilentlyContinue'
$driveLetter = $env:SystemDrive.TrimEnd(':')

function Get-DirSize([string]$Path) {
    $s = (Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
          Measure-Object -Property Length -Sum).Sum
    if ($s) { $s } else { 0 }
}
function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { '{0:N2} GB' -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { '{0:N1} MB' -f ($Bytes / 1MB) }
    else { '{0:N0} KB' -f ($Bytes / 1KB) }
}
function Clear-Dir([string]$Path, [string]$Label) {
    if (-not (Test-Path $Path)) { return }
    $size = Get-DirSize $Path
    if ($PSCmdlet.ShouldProcess($Path, 'Delete contents')) {
        Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host ('  {0,-44} {1,10}' -f $Label, (Format-Size $size))
}

$before = (Get-PSDrive -Name $driveLetter).Free

Write-Host "`nTemp locations" -ForegroundColor Cyan
Clear-Dir $env:TEMP 'User temp'
Clear-Dir "$env:SystemRoot\Temp" 'Windows temp'
Clear-Dir "$env:LOCALAPPDATA\Microsoft\Windows\INetCache" 'Internet cache'
Clear-Dir "$env:LOCALAPPDATA\CrashDumps" 'Crash dumps'
Clear-Dir "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" 'Error reports (queue)'
Clear-Dir "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" 'Error reports (archive)'

Write-Host "`nWindows Update cache" -ForegroundColor Cyan
$svcs = 'wuauserv', 'bits' | Where-Object { (Get-Service $_ -ErrorAction SilentlyContinue).Status -eq 'Running' }
if (-not $WhatIfPreference) { $svcs | ForEach-Object { Stop-Service $_ -Force } }
Clear-Dir "$env:SystemRoot\SoftwareDistribution\Download" 'Windows Update downloads'
if (-not $WhatIfPreference) { $svcs | ForEach-Object { Start-Service $_ } }

if (-not $SkipBrowsers) {
    Write-Host "`nBrowser caches" -ForegroundColor Cyan
    $chromium = [ordered]@{
        'Chrome' = "$env:LOCALAPPDATA\Google\Chrome\User Data"
        'Edge'   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        'Brave'  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    }
    foreach ($b in $chromium.GetEnumerator()) {
        if (-not (Test-Path $b.Value)) { continue }
        $profiles = Get-ChildItem $b.Value -Directory | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }
        foreach ($p in $profiles) {
            foreach ($sub in 'Cache', 'Code Cache', 'GPUCache') {
                Clear-Dir (Join-Path $p.FullName $sub) "$($b.Key) / $($p.Name) / $sub"
            }
        }
    }
    $ff = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $ff) {
        Get-ChildItem $ff -Directory | ForEach-Object { Clear-Dir (Join-Path $_.FullName 'cache2') "Firefox / $($_.Name)" }
    }
}

Write-Host "`nRecycle Bin" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess('Recycle Bin', 'Empty')) { Clear-RecycleBin -Force -ErrorAction SilentlyContinue }
Write-Host '  Emptied'

$after = (Get-PSDrive -Name $driveLetter).Free
$freed = $after - $before
Write-Host ("`nFree space on {0}: gained {1}" -f $env:SystemDrive, (Format-Size ([math]::Max(0, $freed)))) -ForegroundColor Green
