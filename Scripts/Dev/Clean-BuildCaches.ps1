<#
.SYNOPSIS
    Cleans Maven (.m2) and Gradle caches to reclaim space or fix stale/corrupt dependency problems.
.PARAMETER Mode
    1 = Maven SNAPSHOT artifacts
    2 = Maven failed-download markers (*.lastUpdated)
    3 = Maven: wipe the ENTIRE local repository
    4 = Gradle: wipe caches (stops Gradle daemons first)
    5 = Run 1 + 2 + 4
    Leave empty for a menu.
#>
param([ValidateSet('', '1', '2', '3', '4', '5')][string]$Mode = '')

$m2Repo = Join-Path $env:USERPROFILE '.m2\repository'
$gradleHome = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path $env:USERPROFILE '.gradle' }

function Get-DirSize([string]$Path) {
    $s = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
          Measure-Object Length -Sum).Sum
    if ($s) { $s } else { 0 }
}
function Format-Size([double]$B) {
    if ($B -ge 1GB) { '{0:N2} GB' -f ($B / 1GB) } elseif ($B -ge 1MB) { '{0:N1} MB' -f ($B / 1MB) } else { '{0:N0} KB' -f ($B / 1KB) }
}

function Clear-MavenSnapshots {
    if (-not (Test-Path $m2Repo)) { Write-Host 'No Maven repository found.'; return }
    Write-Host 'Removing SNAPSHOT artifacts from Maven repo...' -ForegroundColor Cyan
    $dirs = @(Get-ChildItem $m2Repo -Directory -Recurse -Filter '*-SNAPSHOT' -ErrorAction SilentlyContinue)
    $freed = 0
    foreach ($d in $dirs) {
        if (Test-Path $d.FullName) {
            $freed += Get-DirSize $d.FullName
            Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host ("  Removed {0} SNAPSHOT folders, ~{1}" -f $dirs.Count, (Format-Size $freed))
    Write-Host '  (Locally installed snapshot modules will need a fresh "mvn install".)' -ForegroundColor DarkGray
}

function Clear-MavenFailedMarkers {
    if (-not (Test-Path $m2Repo)) { return }
    Write-Host 'Removing failed-download markers (*.lastUpdated)...' -ForegroundColor Cyan
    $files = @(Get-ChildItem $m2Repo -Recurse -Force -File -Filter '*.lastUpdated' -ErrorAction SilentlyContinue)
    $files | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed $($files.Count) files"
}

function Clear-MavenAll {
    if (-not (Test-Path $m2Repo)) { Write-Host 'No Maven repository found.'; return }
    $size = Get-DirSize $m2Repo
    $a = Read-Host ("Delete the ENTIRE Maven repo ({0}). Everything re-downloads next build. Type YES" -f (Format-Size $size))
    if ($a -ceq 'YES') {
        Remove-Item -LiteralPath $m2Repo -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Freed ~$(Format-Size $size)" -ForegroundColor Green
    }
    else { Write-Host '  Skipped.' }
}

function Clear-GradleCaches {
    if (-not (Test-Path $gradleHome)) { Write-Host 'No Gradle home found.'; return }
    Write-Host 'Clearing Gradle caches...' -ForegroundColor Cyan
    if (Get-Command gradle -ErrorAction SilentlyContinue) { gradle --stop | Out-Null }
    $freed = 0
    foreach ($sub in 'caches', 'daemon') {
        $p = Join-Path $gradleHome $sub
        if (Test-Path $p) {
            $freed += Get-DirSize $p
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "  Freed ~$(Format-Size $freed)  (wrapper distributions kept)" -ForegroundColor Green
}

if (-not $Mode) {
    Write-Host 'Build cache cleaner' -ForegroundColor Cyan
    if (Test-Path $m2Repo)     { Write-Host ("  Maven repo : {0}" -f (Format-Size (Get-DirSize $m2Repo))) }
    if (Test-Path $gradleHome) { Write-Host ("  Gradle home: {0}" -f (Format-Size (Get-DirSize $gradleHome))) }
    Write-Host @'

  1) Maven: remove SNAPSHOT artifacts
  2) Maven: remove failed-download markers (*.lastUpdated)
  3) Maven: wipe entire local repository
  4) Gradle: wipe caches
  5) Quick clean (1 + 2 + 4)
'@
    $Mode = Read-Host 'Choose [1-5]'
}

switch ($Mode) {
    '1' { Clear-MavenSnapshots }
    '2' { Clear-MavenFailedMarkers }
    '3' { Clear-MavenAll }
    '4' { Clear-GradleCaches }
    '5' { Clear-MavenSnapshots; Clear-MavenFailedMarkers; Clear-GradleCaches }
    default { Write-Host 'Nothing selected.' }
}
