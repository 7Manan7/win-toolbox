<#
.SYNOPSIS
    Clears Windows search history and file access history for the current user.

.PARAMETER ResetSearchIndex
    Also stops the Windows Search service and deletes the search index database
    (it rebuilds automatically; search may be slow for a while). Requires admin.

.PARAMETER ClearPrefetch
    Also clears the Prefetch folder (records of apps launched). Requires admin.

.PARAMETER ClearThumbnails
    Also deletes the Explorer thumbnail/icon caches.

.EXAMPLE
    .\Clear-WindowsHistory.ps1 -WhatIf       # preview only
    .\Clear-WindowsHistory.ps1               # clear everything per-user
    .\Clear-WindowsHistory.ps1 -ResetSearchIndex -ClearPrefetch   # run as admin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$ResetSearchIndex,
    [switch]$ClearPrefetch,
    [switch]$ClearThumbnails
)

$ErrorActionPreference = 'SilentlyContinue'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Clear-Folder($path, $label) {
    if (Test-Path $path) {
        if ($PSCmdlet.ShouldProcess($path, "Delete contents ($label)")) {
            Get-ChildItem -Path $path -Force -Recurse | Remove-Item -Force -Recurse
            Write-Host "[+] Cleared: $label"
        }
    }
}

function Clear-RegistryKey($path, $label) {
    if (Test-Path $path) {
        if ($PSCmdlet.ShouldProcess($path, "Clear registry key ($label)")) {
            Remove-Item -Path $path -Recurse -Force
            New-Item -Path $path -Force | Out-Null
            Write-Host "[+] Cleared: $label"
        }
    }
}

$isAdmin = Test-Admin
$explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'

# ---------- File access history ----------
Clear-Folder "$env:APPDATA\Microsoft\Windows\Recent" 'Recent files'
Clear-Folder "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations" 'Jump lists (automatic)'
Clear-Folder "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations" 'Jump lists (custom)'

Clear-RegistryKey "$explorer\RecentDocs" 'RecentDocs registry'
Clear-RegistryKey "$explorer\TypedPaths" 'File Explorer address bar history'
Clear-RegistryKey "$explorer\RunMRU" 'Run dialog history'
Clear-RegistryKey "$explorer\ComDlg32\OpenSavePidlMRU" 'Open/Save dialog history'
Clear-RegistryKey "$explorer\ComDlg32\LastVisitedPidlMRU" 'Last visited folders (Open/Save)'
Clear-RegistryKey "$explorer\ComDlg32\LastVisitedPidlMRULegacy" 'Last visited folders (legacy)'

# ---------- Search history ----------
Clear-RegistryKey "$explorer\WordWheelQuery" 'File Explorer search box history'

# Taskbar / Start search cache (Windows 10/11)
Clear-Folder "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Search_cw5n1h2txyewy\LocalState\DeviceSearchCache" 'Taskbar search cache'
Clear-Folder "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Search_cw5n1h2txyewy\AC\Microsoft\Windows\Search" 'Search app cache'

# Activity history / Timeline
Clear-Folder "$env:LOCALAPPDATA\ConnectedDevicesPlatform" 'Activity history (Timeline) database'

# ---------- Optional ----------
if ($ClearThumbnails) {
    if ($PSCmdlet.ShouldProcess('Explorer caches', 'Delete thumbnail/icon caches')) {
        Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Include 'thumbcache_*.db', 'iconcache_*.db' -Force -Recurse | Remove-Item -Force
        Write-Host '[+] Cleared: Thumbnail and icon caches'
    }
}

if ($ClearPrefetch) {
    if ($isAdmin) { Clear-Folder "$env:SystemRoot\Prefetch" 'Prefetch' }
    else { Write-Warning 'Skipping Prefetch: run PowerShell as Administrator.' }
}

if ($ResetSearchIndex) {
    if ($isAdmin) {
        if ($PSCmdlet.ShouldProcess('Windows Search index', 'Stop service, delete index, restart')) {
            Stop-Service WSearch -Force
            Remove-Item "$env:ProgramData\Microsoft\Search\Data\Applications\Windows\*" -Recurse -Force
            Start-Service WSearch
            Write-Host '[+] Search index deleted; it will rebuild in the background.'
        }
    }
    else { Write-Warning 'Skipping search index reset: run PowerShell as Administrator.' }
}

# ---------- Refresh Explorer ----------
if ($PSCmdlet.ShouldProcess('explorer.exe', 'Restart to apply changes')) {
    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 1
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Write-Host '[+] Explorer restarted.'
}

Write-Host "`nDone." -ForegroundColor Green
