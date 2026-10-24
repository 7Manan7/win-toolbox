<#
.SYNOPSIS
    Sorts your Downloads folder into category subfolders (Images, Documents, Installers, ...)
    and moves files older than N days into _Archive\<Category>.
.PARAMETER Path
    Folder to organize (default: your Downloads folder).
.PARAMETER ArchiveDays
    Files older than this go to _Archive (default 90, 0 = never archive).
.EXAMPLE
    .\Organize-Downloads.ps1 -WhatIf     # preview only
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Path = (Join-Path $env:USERPROFILE 'Downloads'),
    [int]$ArchiveDays = 90
)

if (-not (Test-Path $Path)) { Write-Host "Folder not found: $Path" -ForegroundColor Red; return }

$map = [ordered]@{
    'Images'     = '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg', '.ico', '.heic', '.tiff'
    'Documents'  = '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.rtf', '.csv', '.odt', '.md', '.epub'
    'Installers' = '.exe', '.msi', '.msix', '.appx', '.iso'
    'Archives'   = '.zip', '.rar', '.7z', '.tar', '.gz', '.tgz'
    'Videos'     = '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.webm'
    'Audio'      = '.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a'
    'Code'       = '.java', '.jar', '.json', '.xml', '.yml', '.yaml', '.ps1', '.bat', '.cmd', '.py', '.sql', '.js', '.html'
}
$skipExt = '.crdownload', '.part', '.partial', '.tmp', '.download', '.opdownload'
$categories = @($map.Keys) + 'Other'

function Get-Category([IO.FileInfo]$f) {
    $ext = $f.Extension.ToLower()
    foreach ($k in $map.Keys) { if ($map[$k] -contains $ext) { return $k } }
    'Other'
}

# Candidates: loose files in the root + files already sitting in category folders
$candidates = @(Get-ChildItem $Path -File -Force)
foreach ($cat in $categories) {
    $d = Join-Path $Path $cat
    if (Test-Path $d) { $candidates += Get-ChildItem $d -File -Force }
}

$cutoffRecent  = (Get-Date).AddHours(-1)
$cutoffArchive = (Get-Date).AddDays(-$ArchiveDays)
$moved = 0

foreach ($f in $candidates) {
    if ($f.Name -eq 'desktop.ini' -or $skipExt -contains $f.Extension.ToLower()) { continue }
    if ($f.LastWriteTime -gt $cutoffRecent) { continue }   # probably still downloading / in use

    $inRoot = ($f.DirectoryName.TrimEnd('\') -ieq $Path.TrimEnd('\'))
    $cat = if ($inRoot) { Get-Category $f } else { $f.Directory.Name }
    $isOld = ($ArchiveDays -gt 0) -and ($f.LastWriteTime -lt $cutoffArchive)

    if ($isOld)      { $destDir = Join-Path (Join-Path $Path '_Archive') $cat }
    elseif ($inRoot) { $destDir = Join-Path $Path $cat }
    else             { continue }   # already in the right category folder

    $target = Join-Path $destDir $f.Name
    $i = 1
    while (Test-Path $target) {
        $target = Join-Path $destDir ('{0} ({1}){2}' -f $f.BaseName, $i, $f.Extension)
        $i++
    }

    if ($PSCmdlet.ShouldProcess($f.FullName, "Move to $destDir")) {
        New-Item $destDir -ItemType Directory -Force | Out-Null
        Move-Item -LiteralPath $f.FullName -Destination $target
        $moved++
    }
}
Write-Host "`nMoved $moved file(s)." -ForegroundColor Green
