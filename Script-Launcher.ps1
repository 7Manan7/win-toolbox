<#
.SYNOPSIS
    Self-elevating interactive launcher for the Windows Toolbox.
    Discovers and categorizes all .ps1 scripts in the toolbox.
#>
param(
    [switch]$Elevated
)

# Determine the repository root dynamically
$RepoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RepoRoot) { $RepoRoot = (Get-Location).Path }

# ---------- Self-elevate if not running as admin ----------
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process powershell.exe -Verb RunAs -WorkingDirectory "$RepoRoot" -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated'
        )
        exit 0
    }
    catch {
        Write-Host "`nAdministrator privileges are required to run the Windows Toolbox." -ForegroundColor Red
        Write-Host "Elevation request was cancelled or denied." -ForegroundColor Yellow
        Read-Host "`nPress Enter to exit"
        exit 1
    }
}

try { $Host.UI.RawUI.WindowTitle = 'Windows Toolbox Launcher (Admin)' } catch { }

# Locate scripts folder dynamically relative to repo root
$ScriptsFolder = Join-Path $RepoRoot 'Scripts'
if (-not (Test-Path $ScriptsFolder)) {
    $ScriptsFolder = $RepoRoot
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
        '^[Qq]$' {
            if ($Elevated) { exit 0 }
            return
        }
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
                    ForEach-Object {
                        if ($_.Content -match '\s') { "`"$($_.Content)`"" } else { $_.Content }
                    }
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
