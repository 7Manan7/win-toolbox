#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ON : switches to the High Performance power plan, enables Windows Game Mode, pauses background
         services (Windows Update, SysMain, Windows Search, telemetry) and closes chosen background apps.
    OFF: restores your previous power plan and restarts the paused services.
.EXAMPLE
    .\Game-Mode.ps1 -Mode On
.NOTES
    Edit $ServicesToPause / $ProcessesToClose below. Paused services also come back on their own after a reboot.
#>
param([ValidateSet('On', 'Off')][string]$Mode)

# ------------ config ------------
$ServicesToPause  = @('wuauserv', 'SysMain', 'WSearch', 'DiagTrack')
$ProcessesToClose = @('OneDrive', 'Teams', 'ms-teams', 'Skype', 'Dropbox', 'GoogleDriveFS')
# --------------------------------

$StateDir  = Join-Path $env:ProgramData 'GameMode'
$StateFile = Join-Path $StateDir 'state.json'
$HighPerf  = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$Balanced  = '381b4222-f694-41f0-9685-ff5bb260df2e'

if (-not $Mode) {
    $m = (Read-Host 'Game mode [on/off]').Trim().ToLower()
    $Mode = switch ($m) { 'on' { 'On' } 'off' { 'Off' } default { $null } }
    if (-not $Mode) { Write-Host 'Invalid choice.' -ForegroundColor Red; return }
}

function Get-ActiveSchemeGuid {
    $line = powercfg /getactivescheme
    if ($line -match '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { $Matches[1] }
}

if ($Mode -eq 'On') {
    if (Test-Path $StateFile) {
        Write-Host 'Game mode already looks active (state file exists). Run with -Mode Off first to restore settings.' -ForegroundColor Yellow
        return
    }
    $prevScheme = Get-ActiveSchemeGuid

    # Power plan
    $target = $HighPerf
    if (-not ((powercfg /list) -match $HighPerf)) {
        $dup = powercfg -duplicatescheme $HighPerf
        if ($dup -match '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { $target = $Matches[1] } else { $target = $null }
    }
    if ($target) { powercfg /setactive $target; Write-Host '[+] Power plan: High performance' }
    else { Write-Host '[!] Could not enable the High performance plan on this PC.' -ForegroundColor Yellow }

    $onBattery = (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1).BatteryStatus -eq 1
    if ($onBattery) { Write-Host '[!] On battery: plug in for full performance (this plan drains it fast).' -ForegroundColor Yellow }

    # Windows Game Mode
    $gb = 'HKCU:\Software\Microsoft\GameBar'
    if (-not (Test-Path $gb)) { New-Item $gb -Force | Out-Null }
    Set-ItemProperty $gb -Name AutoGameModeEnabled -Value 1 -Type DWord
    Write-Host '[+] Windows Game Mode enabled'

    # Pause services
    $paused = @()
    foreach ($s in $ServicesToPause) {
        $svc = Get-Service $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            try { Stop-Service $s -Force -ErrorAction Stop; $paused += $s; Write-Host "[+] Paused service: $s" }
            catch { Write-Host "[!] Could not pause $s" -ForegroundColor Yellow }
        }
    }

    # Close apps
    foreach ($p in $ProcessesToClose) {
        $procs = Get-Process -Name $p -ErrorAction SilentlyContinue
        if ($procs) { $procs | Stop-Process -Force -ErrorAction SilentlyContinue; Write-Host "[+] Closed: $p" }
    }

    New-Item $StateDir -ItemType Directory -Force | Out-Null
    @{ scheme = $prevScheme; services = $paused } | ConvertTo-Json | Set-Content $StateFile
    Write-Host "`nGame mode ON. Run with -Mode Off when you're done." -ForegroundColor Green
}
else {
    $scheme = $Balanced
    $services = $ServicesToPause
    if (Test-Path $StateFile) {
        $state = Get-Content $StateFile -Raw | ConvertFrom-Json
        if ($state.scheme) { $scheme = $state.scheme }
        $services = @($state.services)
    }
    powercfg /setactive $scheme
    Write-Host '[+] Power plan restored'

    foreach ($s in $services) {
        if ($s) {
            try { Start-Service $s -ErrorAction Stop; Write-Host "[+] Restarted service: $s" } catch { }
        }
    }
    Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
    Write-Host "`nGame mode OFF. (Closed apps like OneDrive/Teams must be reopened manually.)" -ForegroundColor Green
}
