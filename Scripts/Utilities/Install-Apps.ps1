<#
.SYNOPSIS
    Installs your usual apps in one go with winget. Already-installed apps are skipped.
.PARAMETER All
    Install everything in the list without asking.
.NOTES
    EDIT THE LIST BELOW to match what you want. If an ID is wrong or renamed, winget just reports it
    and the script carries on; check IDs with:  winget search <name>
#>
param([switch]$All)

# ------------ your app list: 'winget ID' = 'Display name' ------------
$Apps = [ordered]@{
    'Git.Git'                              = 'Git'
    'JetBrains.IntelliJIDEA.Community'     = 'IntelliJ IDEA Community (use JetBrains.IntelliJIDEA.Ultimate for Ultimate)'
    'Microsoft.VisualStudioCode'           = 'Visual Studio Code'
    'EclipseAdoptium.Temurin.17.JDK'       = 'Temurin JDK 17'
    'EclipseAdoptium.Temurin.21.JDK'       = 'Temurin JDK 21'
    'Docker.DockerDesktop'                 = 'Docker Desktop'
    'Postman.Postman'                      = 'Postman'
    'DBeaver.DBeaver.Community'            = 'DBeaver (database client)'
    'GitHub.cli'                           = 'GitHub CLI'
    'Microsoft.WindowsTerminal'            = 'Windows Terminal'
    'Microsoft.PowerToys'                  = 'PowerToys'
    'Notepad++.Notepad++'                  = 'Notepad++'
    '7zip.7zip'                            = '7-Zip'
    'voidtools.Everything'                 = 'Everything (instant file search)'
    'Google.Chrome'                        = 'Google Chrome'
    'VideoLAN.VLC'                         = 'VLC media player'
    'Valve.Steam'                          = 'Steam'
    'Discord.Discord'                      = 'Discord'
}
# ---------------------------------------------------------------------

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host 'winget not found. Install "App Installer" from the Microsoft Store.' -ForegroundColor Red
    return
}

$ids = @($Apps.Keys)
Write-Host "`nApps available:" -ForegroundColor Cyan
for ($i = 0; $i -lt $ids.Count; $i++) { Write-Host ('[{0,2}] {1}' -f ($i + 1), $Apps[$ids[$i]]) }

$selected = $ids
if (-not $All) {
    $in = (Read-Host "`nNumbers to install (e.g. 1,3,5), A = all, Enter = cancel").Trim()
    if (-not $in) { Write-Host 'Cancelled.'; return }
    if ($in -notmatch '^[Aa]$') {
        $selected = @($in -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } |
            ForEach-Object { [int]$_ } | Where-Object { $_ -ge 1 -and $_ -le $ids.Count } | ForEach-Object { $ids[$_ - 1] })
    }
}
if ($selected.Count -eq 0) { Write-Host 'Nothing selected.'; return }

$ok = @(); $skipped = @(); $failed = @()
foreach ($id in $selected) {
    Write-Host "`n>>> $($Apps[$id])  ($id)" -ForegroundColor Cyan
    winget list --id $id -e --accept-source-agreements *> $null
    if ($LASTEXITCODE -eq 0) { Write-Host '    Already installed - skipping.' -ForegroundColor DarkGray; $skipped += $id; continue }

    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) { $ok += $id } else { $failed += $id }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Installed: $($ok.Count)   Skipped: $($skipped.Count)   Failed: $($failed.Count)"
if ($failed.Count) { Write-Host "Failed IDs: $($failed -join ', ')" -ForegroundColor Yellow }
