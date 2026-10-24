<#
.SYNOPSIS
    Shows which installed apps have updates (via winget) and upgrades them all.
.PARAMETER ListOnly
    Only list available upgrades.
.PARAMETER Yes
    Don't ask for confirmation.
#>
param([switch]$ListOnly, [switch]$Yes)

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host 'winget not found. Install "App Installer" from the Microsoft Store.' -ForegroundColor Red
    return
}

Write-Host 'Refreshing package sources...' -ForegroundColor Cyan
winget source update | Out-Null

Write-Host "`nAvailable upgrades:" -ForegroundColor Cyan
winget upgrade --accept-source-agreements
if ($ListOnly) { return }

if (-not $Yes) {
    $a = Read-Host "`nUpgrade everything listed above? [y/N]"
    if ($a -notmatch '^[Yy]') { return }
}

winget upgrade --all --silent --accept-package-agreements --accept-source-agreements
Write-Host "`nDone. Some apps (e.g. ones that were running) may need a restart to finish updating." -ForegroundColor Green
