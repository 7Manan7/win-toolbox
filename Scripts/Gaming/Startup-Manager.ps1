#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Lists startup programs (Run registry keys + Startup folders) and lets you enable/disable them.
    Uses the same mechanism as Task Manager > Startup, so it's fully reversible.
.NOTES
    Scheduled-task and service based startup items are not covered (see Task Scheduler / services.msc).
#>
$ra = 'Software\Microsoft\Windows\CurrentVersion'

function Get-StartupItems {
    $items = @()
    $runKeys = @(
        @{ Path = "HKCU:\$ra\Run"; Approved = "HKCU:\$ra\Explorer\StartupApproved\Run"; Scope = 'User' },
        @{ Path = "HKLM:\$ra\Run"; Approved = "HKLM:\$ra\Explorer\StartupApproved\Run"; Scope = 'Machine' },
        @{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$ra\Explorer\StartupApproved\Run32"; Scope = 'Machine (32-bit)' }
    )
    foreach ($k in $runKeys) {
        if (-not (Test-Path $k.Path)) { continue }
        $props = Get-ItemProperty $k.Path
        foreach ($p in ($props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
            $items += [pscustomobject]@{ Name = $p.Name; Command = [string]$p.Value; Scope = $k.Scope; Approved = $k.Approved }
        }
    }
    $folders = @(
        @{ Path = [Environment]::GetFolderPath('Startup');       Approved = "HKCU:\$ra\Explorer\StartupApproved\StartupFolder"; Scope = 'User folder' },
        @{ Path = [Environment]::GetFolderPath('CommonStartup'); Approved = "HKLM:\$ra\Explorer\StartupApproved\StartupFolder"; Scope = 'All-users folder' }
    )
    foreach ($f in $folders) {
        if (-not (Test-Path $f.Path)) { continue }
        Get-ChildItem $f.Path -File -Force | Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object {
            $items += [pscustomobject]@{ Name = $_.Name; Command = $_.FullName; Scope = $f.Scope; Approved = $f.Approved }
        }
    }
    $items
}

function Get-ItemStatus($item) {
    $v = $null
    if (Test-Path $item.Approved) {
        $v = (Get-ItemProperty $item.Approved -Name $item.Name -ErrorAction SilentlyContinue).($item.Name)
    }
    if ($v -is [byte[]] -and $v.Length -gt 0 -and ($v[0] -band 1)) { 'Disabled' } else { 'Enabled' }
}

function Set-ItemStatus($item, [bool]$enable) {
    if (-not (Test-Path $item.Approved)) { New-Item -Path $item.Approved -Force | Out-Null }
    $first = if ($enable) { 2 } else { 3 }
    $bytes = [byte[]]($first, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    Set-ItemProperty -Path $item.Approved -Name $item.Name -Value $bytes -Type Binary
}

while ($true) {
    Clear-Host
    Write-Host '=== Startup Manager ===' -ForegroundColor Cyan
    $items = @(Get-StartupItems)
    for ($i = 0; $i -lt $items.Count; $i++) {
        $st = Get-ItemStatus $items[$i]
        $color = if ($st -eq 'Enabled') { 'Green' } else { 'DarkGray' }
        $cmd = $items[$i].Command
        if ($cmd.Length -gt 60) { $cmd = $cmd.Substring(0, 57) + '...' }
        Write-Host ('[{0,2}] {1,-9} {2,-28} {3,-16} {4}' -f ($i + 1), $st, $items[$i].Name, $items[$i].Scope, $cmd) -ForegroundColor $color
    }
    if ($items.Count -eq 0) { Write-Host 'No startup items found.' }

    $in = (Read-Host "`nNumbers to toggle (e.g. 2,5), R = refresh, Q = quit").Trim()
    if ($in -match '^[Qq]$') { break }
    if ($in -match '^[Rr]?$') { continue }
    foreach ($tok in ($in -split '[,\s]+' | Where-Object { $_ -match '^\d+$' })) {
        $n = [int]$tok
        if ($n -ge 1 -and $n -le $items.Count) {
            $it = $items[$n - 1]
            $enable = (Get-ItemStatus $it) -eq 'Disabled'
            Set-ItemStatus $it $enable
        }
    }
}
Write-Host 'Changes apply at next sign-in.' -ForegroundColor Green
