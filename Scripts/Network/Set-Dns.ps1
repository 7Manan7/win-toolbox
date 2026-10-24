#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configure DNS servers on Windows network adapters, with many provider presets.

.EXAMPLES
    .\Set-Dns.ps1                                   # interactive menu
    .\Set-Dns.ps1 -List                             # list available providers
    .\Set-Dns.ps1 -Provider AdGuard                 # ad/tracker blocking DNS
    .\Set-Dns.ps1 -Provider Google -EnableDoH       # + DNS-over-HTTPS (Windows 11 / Server 2022+)
    .\Set-Dns.ps1 -Provider WARP                    # connect Cloudflare WARP client (must be installed)
    .\Set-Dns.ps1 -Servers 10.0.0.2,10.0.0.3        # custom DNS servers
    .\Set-Dns.ps1 -Provider Quad9 -InterfaceAlias "Wi-Fi"
    .\Set-Dns.ps1 -Reset                            # back to automatic (DHCP)
    .\Set-Dns.ps1 -Show                             # display current settings
#>
[CmdletBinding()]
param(
    [ValidateSet('Cloudflare', 'CloudflareSecurity', 'CloudflareFamily', 'Google', 'Quad9', 'OpenDNS',
                 'AdGuard', 'AdGuardFamily', 'AdGuardUnfiltered', 'CleanBrowsing', 'Mullvad', 'WARP')]
    [string]$Provider,

    [string[]]$Servers,
    [string[]]$InterfaceAlias,
    [switch]$EnableDoH,
    [switch]$Reset,
    [switch]$Show,
    [switch]$List
)

$ErrorActionPreference = 'Continue'

# ---- Provider presets -------------------------------------------------------
$Providers = [ordered]@{
    Cloudflare         = @{ Desc = 'Cloudflare 1.1.1.1 (fast, private)'
                            Servers = '1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001'
                            Doh = 'https://cloudflare-dns.com/dns-query' }
    CloudflareSecurity = @{ Desc = 'Cloudflare 1.1.1.2 (blocks malware)'
                            Servers = '1.1.1.2', '1.0.0.2', '2606:4700:4700::1112', '2606:4700:4700::1002'
                            Doh = 'https://security.cloudflare-dns.com/dns-query' }
    CloudflareFamily   = @{ Desc = 'Cloudflare 1.1.1.3 (blocks malware + adult content)'
                            Servers = '1.1.1.3', '1.0.0.3', '2606:4700:4700::1113', '2606:4700:4700::1003'
                            Doh = 'https://family.cloudflare-dns.com/dns-query' }
    Google             = @{ Desc = 'Google Public DNS'
                            Servers = '8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844'
                            Doh = 'https://dns.google/dns-query' }
    Quad9              = @{ Desc = 'Quad9 (malware blocking, privacy-focused)'
                            Servers = '9.9.9.9', '149.112.112.112', '2620:fe::fe', '2620:fe::9'
                            Doh = 'https://dns.quad9.net/dns-query' }
    OpenDNS            = @{ Desc = 'Cisco OpenDNS'
                            Servers = '208.67.222.222', '208.67.220.220', '2620:119:35::35', '2620:119:53::53'
                            Doh = 'https://doh.opendns.com/dns-query' }
    AdGuard            = @{ Desc = 'AdGuard DNS (blocks ads and trackers)'
                            Servers = '94.140.14.14', '94.140.15.15', '2a10:50c0::ad1:ff', '2a10:50c0::ad2:ff'
                            Doh = 'https://dns.adguard-dns.com/dns-query' }
    AdGuardFamily      = @{ Desc = 'AdGuard Family (ads + adult content + safe search)'
                            Servers = '94.140.14.15', '94.140.15.16', '2a10:50c0::bad1:ff', '2a10:50c0::bad2:ff'
                            Doh = 'https://family.adguard-dns.com/dns-query' }
    AdGuardUnfiltered  = @{ Desc = 'AdGuard Non-filtering (no blocking)'
                            Servers = '94.140.14.140', '94.140.14.141', '2a10:50c0::1:ff', '2a10:50c0::2:ff'
                            Doh = 'https://unfiltered.adguard-dns.com/dns-query' }
    CleanBrowsing      = @{ Desc = 'CleanBrowsing Family filter'
                            Servers = '185.228.168.168', '185.228.169.168', '2a0d:2a00:1::', '2a0d:2a00:2::'
                            Doh = 'https://doh.cleanbrowsing.org/doh/family-filter/' }
    Mullvad            = @{ Desc = 'Mullvad DNS (no logging, no filtering)'
                            Servers = '194.242.2.2', '2a07:e340::2'
                            Doh = 'https://dns.mullvad.net/dns-query' }
    WARP               = @{ Desc = 'Cloudflare WARP (VPN client, not a plain DNS server)'
                            Servers = $null; Doh = $null }
}

function Show-Providers {
    Write-Host "`nAvailable providers:" -ForegroundColor Cyan
    $i = 1
    foreach ($k in $Providers.Keys) {
        '{0,2}. {1,-19} {2}' -f $i, $k, $Providers[$k].Desc | Write-Host
        $i++
    }
}

function Show-Dns {
    Write-Host "`nCurrent DNS configuration:" -ForegroundColor Cyan
    Get-DnsClientServerAddress -AddressFamily IPv4, IPv6 |
        Where-Object { $_.ServerAddresses.Count -gt 0 } |
        Sort-Object InterfaceAlias, AddressFamily |
        Format-Table InterfaceAlias, AddressFamily, ServerAddresses -AutoSize
}

function Get-WarpCli {
    $cmd = Get-Command warp-cli.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $default = "$env:ProgramFiles\Cloudflare\Cloudflare WARP\warp-cli.exe"
    if (Test-Path $default) { return $default }
    return $null
}

# ---- Simple modes -----------------------------------------------------------
if ($List) { Show-Providers; return }
if ($Show) { Show-Dns; return }

# ---- Interactive menu when nothing was specified ----------------------------
if (-not $Provider -and -not $Servers -and -not $Reset) {
    Show-Providers
    Write-Host " 0. Reset to automatic (DHCP)"
    $choice = (Read-Host "`nChoose a number").Trim()
    if ($choice -eq '0') { $Reset = $true }
    elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $Providers.Count) {
        $Provider = @($Providers.Keys)[[int]$choice - 1]
    } else {
        Write-Host "Invalid choice." -ForegroundColor Red
        return
    }
}

# ---- WARP -------------------------------------------------------------------
if ($Provider -eq 'WARP') {
    $warp = Get-WarpCli
    if (-not $warp) {
        Write-Host "Cloudflare WARP isn't installed. Get it from https://one.one.one.one/ then re-run." -ForegroundColor Yellow
        return
    }
    if ($Reset) {
        & $warp disconnect
        Write-Host "WARP disconnected." -ForegroundColor Yellow
    } else {
        & $warp connect
        Write-Host "WARP connected." -ForegroundColor Green
    }
    Start-Sleep -Seconds 2
    & $warp status
    return
}

# ---- Pick target adapters ---------------------------------------------------
if ($InterfaceAlias) {
    $adapters = Get-NetAdapter -Name $InterfaceAlias -ErrorAction SilentlyContinue
} else {
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
}
if (-not $adapters) {
    Write-Host "No matching active network adapters found." -ForegroundColor Yellow
    return
}

$custom = [bool]$Servers
if (-not $custom -and -not $Reset) { $Servers = $Providers[$Provider].Servers }

foreach ($a in $adapters) {
    if ($Reset) {
        Write-Host "Resetting DNS to automatic on '$($a.Name)'..." -ForegroundColor Yellow
        Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses
    } else {
        Write-Host "Setting DNS on '$($a.Name)': $($Servers -join ', ')" -ForegroundColor Green
        Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $Servers
    }
}

# ---- Optional DNS-over-HTTPS ------------------------------------------------
if ($EnableDoH -and -not $Reset) {
    if ($custom) {
        Write-Warning "-EnableDoH only works with a built-in -Provider; skipping."
    } elseif (-not (Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue)) {
        Write-Warning "DNS-over-HTTPS isn't supported on this Windows version; skipping."
    } else {
        foreach ($ip in $Providers[$Provider].Servers) {
            try {
                if (-not (Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue)) {
                    Add-DnsClientDohServerAddress -ServerAddress $ip `
                        -DohTemplate $Providers[$Provider].Doh `
                        -AllowFallbackToUdp $true -AutoUpgrade $true | Out-Null
                }
            } catch {
                Write-Warning "Could not register DoH for ${ip}: $($_.Exception.Message)"
            }
        }
        Write-Host "DoH templates registered for $Provider." -ForegroundColor Green
    }
}

Clear-DnsClientCache
Write-Host "DNS cache flushed." -ForegroundColor Green
Show-Dns
