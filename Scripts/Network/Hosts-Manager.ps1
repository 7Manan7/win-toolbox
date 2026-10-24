#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Menu to view, add and remove entries in the Windows hosts file.
    A timestamped backup is saved to C:\ProgramData\HostsBackups before every change.
#>
$hosts = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$backupDir = Join-Path $env:ProgramData 'HostsBackups'

function Backup-Hosts {
    New-Item $backupDir -ItemType Directory -Force | Out-Null
    $dest = Join-Path $backupDir ('hosts_{0:yyyyMMdd_HHmmss}.bak' -f (Get-Date))
    Copy-Item $hosts $dest
    $dest
}

function Save-Hosts([string[]]$Lines) {
    $null = Backup-Hosts
    (Get-Item $hosts).IsReadOnly = $false
    [IO.File]::WriteAllLines($hosts, $Lines, (New-Object Text.UTF8Encoding $false))
    ipconfig /flushdns | Out-Null
}

function Get-Entries {
    $n = 0
    foreach ($line in @(Get-Content $hosts)) {
        $n++
        $t = ($line -split '#')[0].Trim()
        if (-not $t) { continue }
        $p = $t -split '\s+'
        if ($p.Count -ge 2) {
            [pscustomobject]@{ Line = $n; IP = $p[0]; Hosts = ($p[1..($p.Count - 1)] -join ' ') }
        }
    }
}

function Show-Entries {
    $e = @(Get-Entries)
    if ($e.Count -eq 0) { Write-Host '  (no active entries)' -ForegroundColor DarkGray }
    else { $e | Format-Table Line, IP, Hosts -AutoSize }
}

while ($true) {
    Write-Host "`n=== Hosts file manager ===" -ForegroundColor Cyan
    Write-Host ' 1) List entries    2) Add entry    3) Remove entry'
    Write-Host ' 4) Restore a backup    5) Open in Notepad    Q) Quit'
    $c = (Read-Host 'Choose').Trim()

    switch -Regex ($c) {
        '^1$' { Show-Entries }
        '^2$' {
            $ip = (Read-Host 'IP address (e.g. 127.0.0.1)').Trim()
            $name = (Read-Host 'Hostname (e.g. myapp.local)').Trim()
            $parsed = $null
            if (-not [Net.IPAddress]::TryParse($ip, [ref]$parsed)) { Write-Host 'Invalid IP address.' -ForegroundColor Red; break }
            if ($name -notmatch '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$') { Write-Host 'Invalid hostname.' -ForegroundColor Red; break }
            $lines = @(Get-Content $hosts)
            $exists = @(Get-Entries | Where-Object { ($_.Hosts -split ' ') -contains $name })
            if ($exists.Count) { Write-Host "'$name' already exists (line $($exists[0].Line)). Remove it first." -ForegroundColor Yellow; break }
            Save-Hosts ($lines + "$ip`t$name")
            Write-Host "Added: $ip  $name" -ForegroundColor Green
        }
        '^3$' {
            Show-Entries
            $sel = (Read-Host 'Line number(s) or hostname to remove (comma separated)').Trim()
            if (-not $sel) { break }
            $tokens = $sel -split '[,\s]+' | Where-Object { $_ }
            $lines = @(Get-Content $hosts)
            $drop = @()
            foreach ($tok in $tokens) {
                if ($tok -match '^\d+$') { $drop += [int]$tok }
                else { $drop += @(Get-Entries | Where-Object { ($_.Hosts -split ' ') -contains $tok } | ForEach-Object { $_.Line }) }
            }
            if ($drop.Count -eq 0) { Write-Host 'Nothing matched.' -ForegroundColor Yellow; break }
            $keep = for ($i = 0; $i -lt $lines.Count; $i++) { if (($i + 1) -notin $drop) { $lines[$i] } }
            Save-Hosts @($keep)
            Write-Host "Removed $($drop.Count) line(s)." -ForegroundColor Green
        }
        '^4$' {
            $bk = @(Get-ChildItem $backupDir -Filter *.bak -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 15)
            if ($bk.Count -eq 0) { Write-Host 'No backups yet.' -ForegroundColor Yellow; break }
            for ($i = 0; $i -lt $bk.Count; $i++) { Write-Host ('[{0}] {1}  ({2})' -f ($i + 1), $bk[$i].Name, $bk[$i].LastWriteTime) }
            $n = Read-Host 'Restore which backup? [number]'
            if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $bk.Count) {
                $content = @(Get-Content $bk[[int]$n - 1].FullName)
                Save-Hosts $content
                Write-Host 'Restored (current file was backed up first).' -ForegroundColor Green
            }
        }
        '^5$' { Start-Process notepad.exe $hosts }
        '^[Qq]$' { return }
        default { Write-Host 'Invalid choice.' -ForegroundColor Red }
    }
}
