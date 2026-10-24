<#
.SYNOPSIS
    Logs CPU / RAM / GPU stats every few seconds to a CSV while you play, and prints a summary
    (peak temps, throttling) when you stop. Press Q to stop.
.PARAMETER IntervalSeconds
    Seconds between samples (default 2).
.PARAMETER DurationMinutes
    Stop automatically after this many minutes (0 = run until you press Q).
.NOTES
    GPU data comes from nvidia-smi (NVIDIA drivers). Windows has no reliable built-in CPU temperature
    sensor; the "CpuAcpiTemp" column is often a fixed/fake value. Use HWiNFO or LibreHardwareMonitor
    for true CPU temps.
#>
param([int]$IntervalSeconds = 2, [int]$DurationMinutes = 0)

$logFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('HardwareLog_{0:yyyyMMdd_HHmmss}.csv' -f (Get-Date))

$nv = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source
if (-not $nv) {
    $c = "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    if (Test-Path $c) { $nv = $c }
}
if (-not $nv) { Write-Host 'nvidia-smi not found - GPU columns will be empty.' -ForegroundColor Yellow }

$baseMHz = (Get-CimInstance Win32_Processor | Select-Object -First 1).MaxClockSpeed

function Get-ThrottleText($hex) {
    try {
        $v = [Convert]::ToInt64(($hex.Trim() -replace '^0x', ''), 16)
        $names = @()
        if ($v -band 0x04) { $names += 'PowerCap' }
        if ($v -band 0x08) { $names += 'HW-Slowdown' }
        if ($v -band 0x20) { $names += 'SW-Thermal' }
        if ($v -band 0x40) { $names += 'HW-Thermal' }
        if ($v -band 0x80) { $names += 'PowerBrake' }
        if ($names.Count) { $names -join '+' } else { 'None' }
    }
    catch { $hex }
}

function Get-AcpiTemp {
    try {
        $t = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | Select-Object -First 1
        [math]::Round($t.CurrentTemperature / 10 - 273.15, 1)
    }
    catch { $null }
}

$header = 'Time,CpuPct,CpuMHz,CpuAcpiTemp,RamPct,GpuTemp,GpuPct,GpuMHz,GpuMaxMHz,GpuWatts,VramMB,Throttle'
Set-Content -Path $logFile -Value $header
Write-Host "Logging to: $logFile" -ForegroundColor Cyan
Write-Host "Press Q to stop.`n"
Write-Host ('{0,-9} {1,6} {2,7} {3,6} {4,7} {5,6} {6,7} {7}' -f 'Time', 'CPU%', 'CPUMHz', 'RAM%', 'GPU C', 'GPU%', 'GPU W', 'Throttle')

$samples = New-Object System.Collections.Generic.List[object]
$end = if ($DurationMinutes -gt 0) { (Get-Date).AddMinutes($DurationMinutes) } else { [datetime]::MaxValue }
$stop = $false

try {
    while (-not $stop -and (Get-Date) -lt $end) {
        try { if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Q') { break } } catch { }

        $cpu = $null; $mhz = $null
        try {
            $c = (Get-Counter '\Processor Information(_Total)\% Processor Utility', '\Processor Information(_Total)\% Processor Performance' -ErrorAction Stop).CounterSamples
            $cpu = [math]::Round([math]::Min(100, $c[0].CookedValue), 1)
            $mhz = [math]::Round($baseMHz * $c[1].CookedValue / 100)
        }
        catch { }

        $os = Get-CimInstance Win32_OperatingSystem
        $ram = [math]::Round(100 * ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize, 1)

        $g = @{ Temp = $null; Pct = $null; Clk = $null; Max = $null; W = $null; Vram = $null; Thr = '' }
        if ($nv) {
            $raw = & $nv '--query-gpu=temperature.gpu,utilization.gpu,clocks.gr,clocks.max.gr,power.draw,memory.used,clocks_throttle_reasons.active' '--format=csv,noheader,nounits' 2>$null
            if ($raw) {
                $f = ($raw | Select-Object -First 1) -split ','
                if ($f.Count -ge 7) {
                    $g.Temp = $f[0].Trim(); $g.Pct = $f[1].Trim(); $g.Clk = $f[2].Trim(); $g.Max = $f[3].Trim()
                    $g.W = $f[4].Trim(); $g.Vram = $f[5].Trim(); $g.Thr = Get-ThrottleText $f[6]
                }
            }
        }
        $acpi = Get-AcpiTemp
        $t = Get-Date -Format 'HH:mm:ss'

        Add-Content -Path $logFile -Value ('{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11}' -f $t, $cpu, $mhz, $acpi, $ram, $g.Temp, $g.Pct, $g.Clk, $g.Max, $g.W, $g.Vram, $g.Thr)
        $samples.Add([pscustomobject]@{ Cpu = $cpu; Ram = $ram; GpuTemp = $g.Temp; GpuPct = $g.Pct; Thr = $g.Thr })

        $color = if ($g.Thr -and $g.Thr -ne 'None') { 'Yellow' } else { 'Gray' }
        Write-Host ('{0,-9} {1,6} {2,7} {3,6} {4,7} {5,6} {6,7} {7}' -f $t, $cpu, $mhz, $ram, $g.Temp, $g.Pct, $g.W, $g.Thr) -ForegroundColor $color
        Start-Sleep -Seconds $IntervalSeconds
    }
}
finally {
    Write-Host "`n=== Summary ($($samples.Count) samples) ===" -ForegroundColor Cyan
    if ($samples.Count) {
        $num = { param($p) @($samples | ForEach-Object { $_.$p } | Where-Object { $_ -match '^[\d.]+$' } | ForEach-Object { [double]$_ }) }
        foreach ($m in @(@('Cpu', 'CPU %'), @('Ram', 'RAM %'), @('GpuTemp', 'GPU temp C'), @('GpuPct', 'GPU %'))) {
            $v = & $num $m[0]
            if ($v.Count) { $s = $v | Measure-Object -Average -Maximum; Write-Host ('{0,-12} avg {1,6:N1}   max {2,6:N1}' -f $m[1], $s.Average, $s.Maximum) }
        }
        $thr = @($samples | Where-Object { $_.Thr -and $_.Thr -ne 'None' }).Count
        Write-Host "GPU throttling samples: $thr of $($samples.Count)" -ForegroundColor $(if ($thr) { 'Yellow' } else { 'Green' })
    }
    Write-Host "CSV saved: $logFile"
}
