#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Starts / stops / shows status of your local dev services: database Windows services
    (MySQL, PostgreSQL, Redis, MongoDB) and Docker containers.
.EXAMPLE
    .\Dev-Services.ps1 -Action start
.NOTES
    Edit the config block below to match your setup.
#>
param([ValidateSet('start', 'stop', 'status')][string]$Action)

# ------------ config ------------
$ServicePatterns = @('MySQL*', 'postgresql*', 'Redis*', 'MongoDB*')   # Windows service names (wildcards ok)
$Containers      = @()    # container names to manage; leave empty to manage ALL containers
$DockerDesktop   = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
# --------------------------------

if (-not $Action) {
    $a = (Read-Host 'Action [start/stop/status]').Trim().ToLower()
    if ($a -notin 'start', 'stop', 'status') { Write-Host 'Invalid action.' -ForegroundColor Red; return }
    $Action = $a
}

# ---- Windows services ----
Write-Host "`n=== Windows services ===" -ForegroundColor Cyan
$svcs = @(Get-Service -Name $ServicePatterns -ErrorAction SilentlyContinue)
if ($svcs.Count -eq 0) { Write-Host 'No matching services installed.' -ForegroundColor DarkGray }
foreach ($s in $svcs) {
    try {
        switch ($Action) {
            'start' { if ($s.Status -ne 'Running') { Start-Service $s.Name -ErrorAction Stop } }
            'stop'  { if ($s.Status -ne 'Stopped') { Stop-Service $s.Name -Force -ErrorAction Stop } }
        }
    }
    catch { Write-Host "  Could not $Action $($s.Name): $($_.Exception.Message)" -ForegroundColor Red }
}
if ($svcs.Count) { Get-Service -Name $ServicePatterns -ErrorAction SilentlyContinue | Format-Table Name, Status, StartType -AutoSize }

# ---- Docker ----
Write-Host "=== Docker ===" -ForegroundColor Cyan
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Host 'Docker is not installed.' -ForegroundColor DarkGray; return }

function Test-DockerUp { docker info *> $null; return ($LASTEXITCODE -eq 0) }

if (-not (Test-DockerUp)) {
    if ($Action -eq 'start' -and (Test-Path $DockerDesktop)) {
        Write-Host 'Starting Docker Desktop (waiting up to 2 minutes)...'
        Start-Process $DockerDesktop
        $deadline = (Get-Date).AddSeconds(120)
        while (-not (Test-DockerUp) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 4 }
    }
    if (-not (Test-DockerUp)) { Write-Host 'Docker engine is not running.' -ForegroundColor Yellow; return }
}

$all     = @(docker ps -a --format '{{.Names}}')
$running = @(docker ps --format '{{.Names}}')
if ($Containers.Count -gt 0) { $all = @($all | Where-Object { $Containers -contains $_ }); $running = @($running | Where-Object { $Containers -contains $_ }) }

switch ($Action) {
    'start' { $todo = @($all | Where-Object { $running -notcontains $_ }); if ($todo) { docker start $todo | Out-Null } }
    'stop'  { if ($running) { docker stop $running | Out-Null } }
}
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

if ($Action -eq 'stop') {
    $q = Read-Host "`nAlso quit Docker Desktop to free RAM? [y/N]"
    if ($q -match '^[Yy]') { Stop-Process -Name 'Docker Desktop' -Force -ErrorAction SilentlyContinue; Write-Host 'Docker Desktop closed.' }
}
