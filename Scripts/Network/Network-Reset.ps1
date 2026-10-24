#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Fixes common connectivity problems: flushes DNS, clears ARP/NetBIOS caches, renews the IP lease.
    With -Full it also resets Winsock and the TCP/IP stack (needs a restart).
.NOTES
    Your connection drops for a few seconds while the IP address is renewed.
#>
param([switch]$Full)

if (-not $PSBoundParameters.ContainsKey('Full')) {
    $a = Read-Host 'Full reset too (Winsock + TCP/IP stack, requires restart)? [y/N]'
    $Full = [bool]($a -match '^[Yy]')
}

function Step([string]$Label, [scriptblock]$Block) {
    Write-Host "[*] $Label" -ForegroundColor Cyan
    & $Block 2>&1 | ForEach-Object { if ("$_".Trim()) { Write-Host "    $_" -ForegroundColor DarkGray } }
}

Step 'Flushing DNS cache'            { ipconfig /flushdns }
Step 'Re-registering DNS'            { ipconfig /registerdns }
Step 'Clearing ARP cache'            { arp -d * }
Step 'Refreshing NetBIOS names'      { nbtstat -R; nbtstat -RR }
Step 'Releasing IP address'          { ipconfig /release }
Step 'Renewing IP address'           { ipconfig /renew }

if ($Full) {
    Step 'Resetting Winsock'         { netsh winsock reset }
    Step 'Resetting TCP/IP (IPv4)'   { netsh int ip reset }
    Step 'Resetting TCP/IP (IPv6)'   { netsh int ipv6 reset }
}

Start-Sleep -Seconds 3
Write-Host "`nConnectivity test..." -ForegroundColor Cyan
$ok = Test-Connection -ComputerName 1.1.1.1 -Count 2 -Quiet -ErrorAction SilentlyContinue
if ($ok) { Write-Host 'Internet reachable.' -ForegroundColor Green }
else { Write-Host 'No reply yet - wait a few seconds or restart if you ran the full reset.' -ForegroundColor Yellow }

if ($Full) {
    $r = Read-Host "`nA restart is required to finish the full reset. Restart now? [y/N]"
    if ($r -match '^[Yy]') { Restart-Computer -Force }
}
