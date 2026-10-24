#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Lists installed JDKs and switches JAVA_HOME (and PATH) to the one you pick.
    Open a NEW terminal / restart IntelliJ afterwards to pick up the change.
.PARAMETER Index
    Pick a JDK by its number in the list (skips the prompt).
#>
param([int]$Index = 0)

$roots = @(
    "$env:ProgramFiles\Java", "$env:ProgramFiles\Eclipse Adoptium", "$env:ProgramFiles\Microsoft",
    "$env:ProgramFiles\Amazon Corretto", "$env:ProgramFiles\Zulu", "$env:ProgramFiles\BellSoft",
    "$env:ProgramFiles\Semeru", "$env:ProgramFiles\RedHat", "${env:ProgramFiles(x86)}\Java",
    "$env:USERPROFILE\.jdks"
)
$jdks = @(foreach ($r in $roots) {
    if (Test-Path $r) {
        Get-ChildItem $r -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'bin\javac.exe') }
    }
}) | Sort-Object FullName -Unique

if ($jdks.Count -eq 0) {
    Write-Host 'No JDKs found in the usual install folders.' -ForegroundColor Red
    Write-Host 'Edit $roots at the top of this script to add your JDK location.'
    return
}

$envKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$current = (Get-ItemProperty $envKey -Name JAVA_HOME -ErrorAction SilentlyContinue).JAVA_HOME

function Get-JdkVersion($dir) {
    $rel = Join-Path $dir 'release'
    if (Test-Path $rel) {
        $line = Get-Content $rel | Where-Object { $_ -like 'JAVA_VERSION=*' } | Select-Object -First 1
        if ($line) { return ($line -replace 'JAVA_VERSION=|"', '') }
    }
    '?'
}

Write-Host "`nInstalled JDKs:" -ForegroundColor Cyan
for ($i = 0; $i -lt $jdks.Count; $i++) {
    $mark = if ($current -and ($jdks[$i].FullName.TrimEnd('\') -ieq $current.TrimEnd('\'))) { '  <-- current JAVA_HOME' } else { '' }
    Write-Host ('[{0}] {1,-10} {2}{3}' -f ($i + 1), (Get-JdkVersion $jdks[$i].FullName), $jdks[$i].FullName, $mark)
}
if (-not $current) { Write-Host '(JAVA_HOME is not currently set system-wide)' -ForegroundColor DarkGray }

if ($Index -eq 0) { $Index = [int](Read-Host "`nSwitch to which JDK? [number, Enter to cancel]" ) }
if ($Index -lt 1 -or $Index -gt $jdks.Count) { Write-Host 'Cancelled.'; return }
$target = $jdks[$Index - 1].FullName

# --- JAVA_HOME (machine, plus user level if one exists, since user overrides machine) ---
Set-ItemProperty $envKey -Name JAVA_HOME -Value $target -Type String
$userKey = 'HKCU:\Environment'
if (Get-ItemProperty $userKey -Name JAVA_HOME -ErrorAction SilentlyContinue) {
    Set-ItemProperty $userKey -Name JAVA_HOME -Value $target -Type String
}

# --- PATH: put %JAVA_HOME%\bin first, drop other JDK bin folders (keeps other %VARS% unexpanded) ---
$jdkBins = $jdks | ForEach-Object { Join-Path $_.FullName 'bin' }
function Update-PathValue($regPath, [bool]$addJavaHome) {
    $item = Get-Item $regPath
    $raw = $item.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $parts = @($raw -split ';' | Where-Object { $_ -and ($jdkBins -notcontains $_.TrimEnd('\')) -and ($_ -ne '%JAVA_HOME%\bin') })
    if ($addJavaHome) { $parts = @('%JAVA_HOME%\bin') + $parts }
    Set-ItemProperty $regPath -Name Path -Value ($parts -join ';') -Type ExpandString
}
Update-PathValue $envKey $true
if (Get-ItemProperty $userKey -Name Path -ErrorAction SilentlyContinue) { Update-PathValue $userKey $false }

# --- Notify Windows and update this session ---
Add-Type -Namespace Win32 -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
$res = [UIntPtr]::Zero
[Win32.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$res) | Out-Null
$env:JAVA_HOME = $target
$env:Path = "$target\bin;" + $env:Path

Write-Host "`nJAVA_HOME set to: $target" -ForegroundColor Green
cmd.exe /c "`"$target\bin\java.exe`" -version 2>&1"
Write-Host "`nOpen a NEW terminal (and restart IntelliJ/Docker tools) to use it." -ForegroundColor Yellow
