#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Finds what is using one or more TCP ports (e.g. a Spring Boot app that didn't shut down)
    and offers to kill it (including child processes).
.EXAMPLE
    .\Kill-Port.ps1 -Ports 8080,3306
#>
param([string]$Ports)

if (-not $Ports) { $Ports = Read-Host 'Port(s) to free (comma separated, e.g. 8080,3306)' }
$list = @($Ports -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
if ($list.Count -eq 0) { Write-Host 'No valid ports given.' -ForegroundColor Red; return }

foreach ($port in $list) {
    Write-Host "`n--- Port $port ---" -ForegroundColor Cyan
    $conns = @(Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue |
        Where-Object { $_.State -ne 'TimeWait' -and $_.OwningProcess -ne 0 })
    if ($conns.Count -eq 0) { Write-Host 'Free - nothing is using it.' -ForegroundColor Green; continue }

    foreach ($procId in ($conns.OwningProcess | Sort-Object -Unique)) {
        $states = ($conns | Where-Object OwningProcess -eq $procId | Select-Object -ExpandProperty State -Unique) -join ', '
        if ($procId -eq 4) {
            Write-Host "Held by the Windows System process (PID 4) [$states] - usually IIS/http.sys; can't be killed here." -ForegroundColor Yellow
            continue
        }
        $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
        $pname = if ($p) { $p.ProcessName } else { '(unknown)' }
        Write-Host ("PID {0}  {1}  [{2}]" -f $procId, $pname, $states)
        if ($p -and $p.Path) { Write-Host "     $($p.Path)" -ForegroundColor DarkGray }

        $a = Read-Host "Kill $pname (PID $procId) and its children? [y/N]"
        if ($a -match '^[Yy]') {
            taskkill.exe /PID $procId /T /F | Out-Host
        }
    }
}
