<#
.SYNOPSIS
    Runs git status / fetch / pull across every repository under a folder.
    Pull uses --ff-only, so it never creates merge commits or touches diverged branches.
.EXAMPLE
    .\Git-BulkUpdate.ps1 -Root C:\Projects -Action pull
#>
param(
    [string]$Root,
    [ValidateSet('status', 'fetch', 'pull')][string]$Action,
    [int]$Depth = 3
)

if (-not $Root) {
    $defaultRoot = if (Test-Path (Join-Path $HOME 'Projects')) { Join-Path $HOME 'Projects' }
                   elseif (Test-Path (Join-Path $HOME 'Documents\Projects')) { Join-Path $HOME 'Documents\Projects' }
                   else { (Get-Location).Path }
    $r = Read-Host "Projects root folder [$defaultRoot]"
    $Root = if ($r) { $r } else { $defaultRoot }
}
if (-not $Action) {
    $a = (Read-Host 'Action [status/fetch/pull] (default: status)').Trim().ToLower()
    $Action = if ($a -in 'fetch', 'pull') { $a } else { 'status' }
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host 'git not found in PATH.' -ForegroundColor Red; return }
if (-not (Test-Path $Root)) { Write-Host "Folder not found: $Root" -ForegroundColor Red; return }

function Invoke-Git([string]$Repo, [string[]]$GitArgs) {
    (& git -c 'safe.directory=*' -C $Repo @GitArgs 2>&1 | Out-String).Trim()
}

$repos = @()
if (Test-Path (Join-Path $Root '.git')) { $repos += (Resolve-Path $Root).Path }
$repos += Get-ChildItem -Path $Root -Directory -Recurse -Depth $Depth -Force -Filter '.git' -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Parent.FullName }
$repos = @($repos | Sort-Object -Unique)

if ($repos.Count -eq 0) { Write-Host 'No git repositories found.' -ForegroundColor Yellow; return }
Write-Host "Found $($repos.Count) repositories. Action: $Action`n" -ForegroundColor Cyan

$issues = 0
foreach ($repo in $repos) {
    $name = $repo.Substring([math]::Min($repo.Length, $Root.TrimEnd('\').Length)).TrimStart('\')
    if (-not $name) { $name = Split-Path $repo -Leaf }

    switch ($Action) {
        'fetch' { $out = Invoke-Git $repo @('fetch', '--all', '--prune', '--quiet') }
        'pull'  { $out = Invoke-Git $repo @('pull', '--ff-only') }
        default { $out = '' }
    }
    $branchLine = (Invoke-Git $repo @('status', '-sb')).Split("`n") | Select-Object -First 1
    $dirty = @((Invoke-Git $repo @('status', '--porcelain')) -split "`n" | Where-Object { $_.Trim() }).Count

    $color = 'Green'
    $note = ''
    if ($dirty -gt 0) { $color = 'Yellow'; $note += " [$dirty uncommitted]" }
    if ($branchLine -match 'behind') { $color = 'Yellow'; $note += ' [behind remote]' }
    if ($Action -eq 'pull' -and $out -match 'fatal|error|Aborting|not possible') { $color = 'Red'; $issues++; $note += " [pull failed: $(($out -split "`n")[0])]" }

    Write-Host ("{0,-40} {1}{2}" -f $name, $branchLine.Replace('## ', ''), $note) -ForegroundColor $color
}
Write-Host "`nDone. $issues problem(s)." -ForegroundColor $(if ($issues) { 'Red' } else { 'Green' })
