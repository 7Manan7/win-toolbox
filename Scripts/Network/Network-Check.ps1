<#
.SYNOPSIS
    Measures latency/jitter/packet loss to your router and public servers, DNS lookup time and
    download speed. Every run is appended to Documents\NetworkLog.csv so you can track it over time.
.PARAMETER Count
    Pings per target (default 10).
.PARAMETER RepeatMinutes
    Repeat the test every N minutes until you press Q (0 = run once).
.PARAMETER SkipSpeedTest
    Skip the 25 MB download test.
#>
param([int]$Count = 10, [int]$RepeatMinutes = 0, [switch]$SkipSpeedTest)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$logFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'NetworkLog.csv'

function Test-Latency([string]$Target, [int]$N) {
    $ping = New-Object System.Net.NetworkInformation.Ping
    $times = New-Object System.Collections.Generic.List[double]
    $lost = 0
    for ($i = 0; $i -lt $N; $i++) {
        try {
            $r = $ping.Send($Target, 2000)
            if ($r.Status -eq 'Success') { $times.Add($r.RoundtripTime) } else { $lost++ }
        }
        catch { $lost++ }
        Start-Sleep -Milliseconds 200
    }
    $min = $null; $avg = $null; $max = $null; $jit = $null
    if ($times.Count -gt 0) {
        $s = $times | Measure-Object -Minimum -Maximum -Average
        $min = $s.Minimum; $avg = [math]::Round($s.Average, 1); $max = $s.Maximum
        $jit = 0
        if ($times.Count -gt 1) {
            $d = for ($k = 0; $k -lt $times.Count - 1; $k++) { [math]::Abs($times[$k + 1] - $times[$k]) }
            $jit = [math]::Round(($d | Measure-Object -Average).Average, 1)
        }
    }
    [pscustomobject]@{ Target = $Target; MinMs = $min; AvgMs = $avg; MaxMs = $max; JitterMs = $jit; LossPct = [math]::Round(100 * $lost / $N) }
}

function Add-Log($row) {
    $row | Export-Csv -Path $logFile -Append -NoTypeInformation
}

function Invoke-Check {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "`n=== Network check  $stamp ===" -ForegroundColor Cyan

    $targets = [ordered]@{}
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
    if ($gw -and $gw -ne '0.0.0.0') { $targets['Router'] = $gw }
    $targets['Cloudflare DNS'] = '1.1.1.1'
    $targets['Google DNS']     = '8.8.8.8'
    $targets['google.com']     = 'google.com'

    $results = foreach ($name in $targets.Keys) {
        $r = Test-Latency $targets[$name] $Count
        $r | Add-Member -NotePropertyName Name -NotePropertyValue $name -PassThru
    }
    $results | Format-Table Name, Target, MinMs, AvgMs, MaxMs, JitterMs, LossPct -AutoSize

    foreach ($r in $results) {
        Add-Log ([pscustomobject]@{ Time = $stamp; Test = 'ping'; Target = $r.Name; AvgMs = $r.AvgMs; MaxMs = $r.MaxMs; JitterMs = $r.JitterMs; LossPct = $r.LossPct; Mbps = ''; DnsMs = '' })
    }

    # DNS lookup time
    $dns = $null
    try { $dns = [math]::Round((Measure-Command { Resolve-DnsName 'www.wikipedia.org' -DnsOnly -NoHostsFile -ErrorAction Stop | Out-Null }).TotalMilliseconds) } catch { }
    if ($dns -ne $null) { Write-Host "DNS lookup: $dns ms" } else { Write-Host 'DNS lookup: failed' -ForegroundColor Yellow }
    Add-Log ([pscustomobject]@{ Time = $stamp; Test = 'dns'; Target = 'www.wikipedia.org'; AvgMs = ''; MaxMs = ''; JitterMs = ''; LossPct = ''; Mbps = ''; DnsMs = $dns })

    # Download speed
    if (-not $SkipSpeedTest) {
        Write-Host 'Download test (25 MB)...'
        $mbps = $null
        try {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $data = (New-Object Net.WebClient).DownloadData('https://speed.cloudflare.com/__down?bytes=25000000')
            $sw.Stop()
            $mbps = [math]::Round(($data.Length * 8 / 1e6) / $sw.Elapsed.TotalSeconds, 1)
        }
        catch { }
        if ($mbps -ne $null) { Write-Host "Download speed: $mbps Mbps" -ForegroundColor Green } else { Write-Host 'Download test failed.' -ForegroundColor Yellow }
        Add-Log ([pscustomobject]@{ Time = $stamp; Test = 'download'; Target = 'speed.cloudflare.com'; AvgMs = ''; MaxMs = ''; JitterMs = ''; LossPct = ''; Mbps = $mbps; DnsMs = '' })
    }
}

do {
    Invoke-Check
    if ($RepeatMinutes -le 0) { break }
    Write-Host "`nNext check in $RepeatMinutes min. Press Q to stop." -ForegroundColor DarkGray
    $until = (Get-Date).AddMinutes($RepeatMinutes)
    $quit = $false
    while ((Get-Date) -lt $until -and -not $quit) {
        try { if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Q') { $quit = $true } } catch { }
        Start-Sleep -Milliseconds 500
    }
} while (-not $quit)

Write-Host "`nLog file: $logFile"
