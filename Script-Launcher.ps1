<#
.SYNOPSIS
    Self-elevating interactive launcher for the Windows Toolbox.
    Discovers and categorizes all .ps1 scripts in the toolbox.
#>

# ---------- Self-elevate if not running as admin ----------
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -WorkingDirectory "$PSScriptRoot" -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`""
    )
    exit
}

$Host.UI.RawUI.WindowTitle = 'Windows Toolbox Launcher (Admin)'

# Locate scripts folder dynamically relative to repo root
$ScriptsFolder = Join-Path $PSScriptRoot 'Scripts'
if (-not (Test-Path $ScriptsFolder)) {
    if (Test-Path 'D:\Scripts') {
        $ScriptsFolder = 'D:\Scripts'
    } else {
        $ScriptsFolder = $PSScriptRoot
    }
}

function Get-ToolboxScripts {
    if (-not (Test-Path $ScriptsFolder)) { return @() }
    @(Get-ChildItem -Path $ScriptsFolder -Filter *.ps1 -File -Recurse |
        Where-Object { $_.FullName -ne $PSCommandPath -and $_.Name -notmatch '^(launch|Script-Launcher)\.ps1$' } |
        Sort-Object FullName)
}

while ($true) {
    Clear-Host
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "             Windows Toolbox Launcher (Admin)         " -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "Path: $ScriptsFolder`n" -ForegroundColor DarkGray

    if (-not (Test-Path $ScriptsFolder)) {
        Write-Host "Error: Scripts folder not found: $ScriptsFolder" -ForegroundColor Red
        Read-Host "`nPress Enter to exit"
        break
    }

    $scripts = Get-ToolboxScripts
    if ($scripts.Count -eq 0) {
        Write-Host "No PowerShell scripts found in $ScriptsFolder." -ForegroundColor Yellow
    }
    else {
        $lastCategory = $null
        for ($i = 0; $i -lt $scripts.Count; $i++) {
            $rel = $scripts[$i].FullName.Substring($ScriptsFolder.Length).TrimStart('\')
            $parts = $rel -split '\\'
            $category = if ($parts.Length -gt 1) { $parts[0] } else { 'General' }

            if ($category -ne $lastCategory) {
                Write-Host "`n[$category]" -ForegroundColor Yellow
                $lastCategory = $category
            }

            $scriptName = if ($parts.Length -gt 1) { $parts[1..($parts.Length - 1)] -join '\' } else { $parts[0] }
            Write-Host ("  [{0,2}] {1}" -f ($i + 1), $scriptName)
        }
    }

    Write-Host "`n------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[R] Refresh   [Q] Quit" -ForegroundColor DarkGray
    $choice = (Read-Host "Enter script number to run").Trim()

    switch -Regex ($choice) {
        '^[Qq]$' { return }
        '^[Rr]$' { continue }
        '^\d+$' {
            $n = [int]$choice
            if ($n -lt 1 -or $n -gt $scripts.Count) {
                Write-Host "Invalid selection. Please choose a number between 1 and $($scripts.Count)." -ForegroundColor Red
                Start-Sleep -Seconds 1
                continue
            }
            $target = $scripts[$n - 1]
            $extra = (Read-Host "Arguments for $($target.Name) (optional, e.g. -WhatIf, Enter to skip)").Trim()

            Write-Host "`n>>> Running $($target.FullName)...`n" -ForegroundColor Green
            $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($target.FullName)`"")
            if ($extra) {
                $parsedArgs = [System.Management.Automation.PSParser]::Tokenize($extra, [ref]$null) |
                    Where-Object { $_.Type -in 'CommandArgument', 'CommandParameter', 'String', 'Number' } |
                    ForEach-Object { $_.Content }
                if ($parsedArgs) {
                    $argList += $parsedArgs
                } else {
                    $argList += ($extra -split '\s+')
                }
            }

            Push-Location $target.DirectoryName
            $proc = Start-Process powershell.exe -ArgumentList $argList -Wait -NoNewWindow -PassThru
            Pop-Location

            Write-Host "`n>>> Finished (exit code: $($proc.ExitCode))" -ForegroundColor $(if ($proc.ExitCode -eq 0) { 'Green' } else { 'Yellow' })
            Read-Host "Press Enter to return to the menu"
        }
        default {
            Write-Host "Invalid input." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
