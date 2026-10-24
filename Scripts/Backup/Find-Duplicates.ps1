<#
.SYNOPSIS
    Finds duplicate files (same content, compared by SHA-256) under a folder, reports wasted space,
    saves a CSV report, and can optionally send the extra copies to the Recycle Bin
    (the oldest copy in each group is always kept). Nothing is deleted unless you confirm.
.PARAMETER Path
    Folder to scan.
.PARAMETER MinSizeMB
    Ignore files smaller than this (default 1 MB).
#>
param([string]$Path, [double]$MinSizeMB = 1)

if (-not $Path) { $Path = Read-Host 'Folder to scan' }
if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { Write-Host 'Folder not found.' -ForegroundColor Red; return }

Write-Host 'Scanning files...' -ForegroundColor Cyan
$minBytes = $MinSizeMB * 1MB
$files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -ge $minBytes })

# Only files that share a size with another file can be duplicates
$candidates = @($files | Group-Object Length | Where-Object Count -gt 1 | ForEach-Object { $_.Group })
Write-Host "$($files.Count) files scanned, $($candidates.Count) need hashing."

$i = 0
$hashed = foreach ($f in $candidates) {
    $i++
    Write-Progress -Activity 'Hashing files' -Status $f.Name -PercentComplete (100 * $i / [math]::Max(1, $candidates.Count))
    try { [pscustomobject]@{ Hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash; File = $f } }
    catch { }
}
Write-Progress -Activity 'Hashing files' -Completed

$groups = @($hashed | Group-Object Hash | Where-Object Count -gt 1)
if ($groups.Count -eq 0) { Write-Host "`nNo duplicates found." -ForegroundColor Green; return }

$report = @()
$wasted = 0
$n = 0
foreach ($g in $groups) {
    $n++
    $sorted = @($g.Group | Sort-Object { $_.File.LastWriteTime })
    $size = $sorted[0].File.Length
    $wasted += $size * ($sorted.Count - 1)
    Write-Host ("`nGroup {0}  ({1:N1} MB each, {2} copies)" -f $n, ($size / 1MB), $sorted.Count) -ForegroundColor Cyan
    for ($k = 0; $k -lt $sorted.Count; $k++) {
        $tag = if ($k -eq 0) { 'KEEP  ' } else { 'dupe  ' }
        Write-Host ("  {0} {1}   [{2:yyyy-MM-dd}]" -f $tag, $sorted[$k].File.FullName, $sorted[$k].File.LastWriteTime) -ForegroundColor $(if ($k -eq 0) { 'Green' } else { 'Gray' })
        $report += [pscustomobject]@{ Group = $n; Action = $tag.Trim(); SizeMB = [math]::Round($size / 1MB, 2); Modified = $sorted[$k].File.LastWriteTime; Path = $sorted[$k].File.FullName }
    }
}

$csv = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('Duplicates_{0:yyyyMMdd_HHmmss}.csv' -f (Get-Date))
$report | Export-Csv $csv -NoTypeInformation
Write-Host ("`n{0} duplicate groups, {1:N2} GB reclaimable. Report: {2}" -f $groups.Count, ($wasted / 1GB), $csv) -ForegroundColor Green

$ans = Read-Host "`nSend the extra copies to the Recycle Bin (oldest copy kept)? Type DELETE to confirm, Enter to skip"
if ($ans -ceq 'DELETE') {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $count = 0
    foreach ($row in ($report | Where-Object Action -eq 'dupe')) {
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($row.Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
            $count++
        }
        catch { Write-Host "Could not delete: $($row.Path)" -ForegroundColor Yellow }
    }
    Write-Host "Moved $count file(s) to the Recycle Bin." -ForegroundColor Green
}
else { Write-Host 'No files were deleted.' }
