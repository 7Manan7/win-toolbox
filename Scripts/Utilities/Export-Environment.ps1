<#
.SYNOPSIS
    Saves a snapshot of your setup to Documents\EnvBackup_<date>\ :
      - user and machine environment variables (JSON + readable PATH lists)
      - installed programs (CSV) and a winget export (apps.json) that can reinstall them
        on a fresh Windows with:  winget import -i apps.json
      - basic system info
#>
param([string]$OutDir)

if (-not $OutDir) {
    $OutDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('EnvBackup_{0:yyyyMMdd_HHmm}' -f (Get-Date))
}
New-Item $OutDir -ItemType Directory -Force | Out-Null
Write-Host "Saving to: $OutDir`n" -ForegroundColor Cyan

# --- Environment variables ---
foreach ($scope in 'User', 'Machine') {
    $vars = [Environment]::GetEnvironmentVariables($scope)
    $vars.GetEnumerator() | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = [string]$_.Value } } |
        ConvertTo-Json | Set-Content (Join-Path $OutDir "env_$($scope.ToLower()).json")

    $path = [Environment]::GetEnvironmentVariable('Path', $scope)
    if ($path) { ($path -split ';' | Where-Object { $_ }) | Set-Content (Join-Path $OutDir "path_$($scope.ToLower()).txt") }
    Write-Host "[+] $scope environment variables"
}

# --- Installed programs (from the registry uninstall keys) ---
$keys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
Get-ItemProperty $keys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
    Sort-Object DisplayName -Unique |
    Export-Csv (Join-Path $OutDir 'installed_programs.csv') -NoTypeInformation
Write-Host '[+] Installed programs list'

# --- winget export ---
if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget export -o (Join-Path $OutDir 'apps.json') --accept-source-agreements | Out-Null
    winget list --accept-source-agreements | Out-File (Join-Path $OutDir 'winget_list.txt') -Encoding utf8
    Write-Host '[+] winget export (apps.json) and list'
}
else { Write-Host '[-] winget not found, skipped app export' -ForegroundColor Yellow }

# --- System info ---
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
@(
    "Computer : $env:COMPUTERNAME"
    "OS       : $($os.Caption) $($os.Version)"
    "CPU      : $($cpu.Name)"
    "RAM GB   : $([math]::Round($os.TotalVisibleMemorySize / 1MB, 1))"
    "Exported : $(Get-Date)"
) | Set-Content (Join-Path $OutDir 'system_info.txt')
Write-Host '[+] System info'

Write-Host "`nDone: $OutDir" -ForegroundColor Green
