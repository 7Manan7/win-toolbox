<#
.SYNOPSIS
    Clears GPU shader / DirectX caches (NVIDIA, AMD, Windows D3D). Useful after a driver update
    or when games stutter or crash. The first launch of each game afterwards rebuilds shaders
    (slightly longer loading / brief stutter), then it's normal.
.NOTES
    Close your games and launchers first. Use -WhatIf to preview.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'SilentlyContinue'

$paths = [ordered]@{
    'NVIDIA DirectX cache'    = "$env:LOCALAPPDATA\NVIDIA\DXCache"
    'NVIDIA OpenGL cache'     = "$env:LOCALAPPDATA\NVIDIA\GLCache"
    'NVIDIA compute cache'    = "$env:LOCALAPPDATA\NVIDIA\ComputeCache"
    'NVIDIA NV_Cache (user)'  = "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache"
    'NVIDIA NV_Cache (system)'= "$env:ProgramData\NVIDIA Corporation\NV_Cache"
    'AMD DirectX cache'       = "$env:LOCALAPPDATA\AMD\DxCache"
    'AMD OpenGL cache'        = "$env:LOCALAPPDATA\AMD\GLCache"
    'Windows D3D shader cache'= "$env:LOCALAPPDATA\D3DSCache"
}

function Format-Size([double]$B) {
    if ($B -ge 1GB) { '{0:N2} GB' -f ($B / 1GB) } elseif ($B -ge 1MB) { '{0:N1} MB' -f ($B / 1MB) } else { '{0:N0} KB' -f ($B / 1KB) }
}

$total = 0
foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path $entry.Value)) { continue }
    $size = (Get-ChildItem $entry.Value -Recurse -Force -File | Measure-Object Length -Sum).Sum
    if (-not $size) { $size = 0 }
    if ($PSCmdlet.ShouldProcess($entry.Value, 'Delete contents')) {
        Get-ChildItem $entry.Value -Force | Remove-Item -Recurse -Force
    }
    $total += $size
    Write-Host ('  {0,-28} {1,10}' -f $entry.Key, (Format-Size $size))
}
Write-Host ("`nTotal cleared: {0}" -f (Format-Size $total)) -ForegroundColor Green
Write-Host 'Tip: first launch of each game will be a bit slower while shaders rebuild.'
