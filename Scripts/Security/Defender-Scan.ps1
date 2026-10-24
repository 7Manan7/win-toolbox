#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Updates Microsoft Defender signatures, runs a Quick or Full scan, then lists recent detections.
.PARAMETER Type
    Quick or Full (asks if omitted). Full scans can take an hour or more.
#>
param([ValidateSet('Quick', 'Full')][string]$Type)

if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
    Write-Host 'Microsoft Defender cmdlets are not available on this system.' -ForegroundColor Red
    return
}

$st = Get-MpComputerStatus
Write-Host "`n--- Defender status ---" -ForegroundColor Cyan
$st | Format-List AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, AntivirusSignatureVersion, AntivirusSignatureLastUpdated
if (-not $st.AntivirusEnabled) {
    Write-Host 'Defender antivirus is not the active antivirus (a third-party AV may be installed). Scan may not run.' -ForegroundColor Yellow
}

Write-Host 'Updating signatures...' -ForegroundColor Cyan
try { Update-MpSignature -ErrorAction Stop; Write-Host 'Signatures updated.' }
catch { Write-Host "Signature update failed (continuing): $($_.Exception.Message)" -ForegroundColor Yellow }

if (-not $Type) {
    $a = (Read-Host 'Scan type [Q]uick / [F]ull (default Quick)').Trim().ToUpper()
    $Type = if ($a -like 'F*') { 'Full' } else { 'Quick' }
}

Write-Host "`nRunning $Type scan (this blocks until it finishes)..." -ForegroundColor Cyan
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    Start-MpScan -ScanType $(if ($Type -eq 'Full') { 'FullScan' } else { 'QuickScan' }) -ErrorAction Stop
    Write-Host ("Scan finished in {0:mm\:ss}." -f $sw.Elapsed) -ForegroundColor Green
}
catch { Write-Host "Scan failed: $($_.Exception.Message)" -ForegroundColor Red }

Write-Host "`n--- Recent threat detections ---" -ForegroundColor Cyan
$det = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Sort-Object InitialDetectionTime -Descending | Select-Object -First 10)
if ($det.Count -eq 0) { Write-Host 'No detections recorded.' -ForegroundColor Green }
else {
    $det | Select-Object InitialDetectionTime, ThreatID, ProcessName, @{n = 'Resources'; e = { $_.Resources -join '; ' }} | Format-Table -AutoSize -Wrap
    Get-MpThreat -ErrorAction SilentlyContinue | Format-Table ThreatName, SeverityID, IsActive -AutoSize
}
