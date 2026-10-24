<#
.SYNOPSIS
    Lists every listening TCP/UDP port with the owning process (and the services inside svchost),
    flags which ports are reachable from the network vs local-only, and shows firewall status.
    Saves a CSV in your Documents folder.
#>
Write-Host "`n--- Firewall profiles ---" -ForegroundColor Cyan
Get-NetFirewallProfile | Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction -AutoSize

$procs = @{}
Get-Process | ForEach-Object { $procs[$_.Id] = $_ }

$svcByPid = @{}
Get-CimInstance Win32_Service | Where-Object { $_.ProcessId -gt 0 } | ForEach-Object {
    if (-not $svcByPid.ContainsKey([int]$_.ProcessId)) { $svcByPid[[int]$_.ProcessId] = @() }
    $svcByPid[[int]$_.ProcessId] += $_.Name
}

function Get-Exposure([string]$addr) {
    if ($addr -in '127.0.0.1', '::1') { 'Local only' } else { 'Network' }
}
function Get-ProcInfo([int]$procId) {
    $name = if ($procs.ContainsKey($procId)) { $procs[$procId].ProcessName } elseif ($procId -eq 4) { 'System' } else { '?' }
    $svc = if ($svcByPid.ContainsKey($procId) -and $name -eq 'svchost') { ($svcByPid[$procId] | Select-Object -First 3) -join ',' } else { '' }
    $path = if ($procs.ContainsKey($procId)) { $procs[$procId].Path } else { '' }
    [pscustomobject]@{ Name = $name; Services = $svc; Path = $path }
}

$rows = @()
foreach ($c in Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue) {
    $pi = Get-ProcInfo ([int]$c.OwningProcess)
    $rows += [pscustomobject]@{ Proto = 'TCP'; Port = $c.LocalPort; Address = $c.LocalAddress; Exposure = (Get-Exposure $c.LocalAddress); PID = $c.OwningProcess; Process = $pi.Name; Services = $pi.Services; Path = $pi.Path }
}
foreach ($u in Get-NetUDPEndpoint -ErrorAction SilentlyContinue) {
    $pi = Get-ProcInfo ([int]$u.OwningProcess)
    $rows += [pscustomobject]@{ Proto = 'UDP'; Port = $u.LocalPort; Address = $u.LocalAddress; Exposure = (Get-Exposure $u.LocalAddress); PID = $u.OwningProcess; Process = $pi.Name; Services = $pi.Services; Path = $pi.Path }
}

$net = @($rows | Where-Object Exposure -eq 'Network' | Sort-Object Proto, Port)
$loc = @($rows | Where-Object Exposure -eq 'Local only' | Sort-Object Proto, Port)

Write-Host "`n--- Listening on the network ($($net.Count)) ---" -ForegroundColor Yellow
$net | Format-Table Proto, Port, Address, PID, Process, Services -AutoSize -Wrap

Write-Host "--- Local-only listeners ($($loc.Count)) ---" -ForegroundColor Cyan
$loc | Format-Table Proto, Port, Address, PID, Process -AutoSize

$csv = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('OpenPorts_{0:yyyyMMdd_HHmm}.csv' -f (Get-Date))
$rows | Sort-Object Exposure, Proto, Port | Export-Csv $csv -NoTypeInformation
Write-Host "CSV saved: $csv" -ForegroundColor Green
Write-Host 'Tip: ports 135/139/445 on "Network" are normal Windows file sharing/RPC; anything unfamiliar is worth a look.'
