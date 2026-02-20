param(
    [int]$KeepLatest = 5,
    [switch]$DeleteOld
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PSScriptRoot }

function New-DirIfMissing {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Move-Pattern {
    param(
        [string]$Pattern,
        [string]$DestinationDir
    )
    New-DirIfMissing -Path $DestinationDir
    $items = Get-ChildItem -LiteralPath $scriptDir -File -Filter $Pattern -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        $dest = Join-Path $DestinationDir $item.Name
        Move-Item -LiteralPath $item.FullName -Destination $dest -Force
    }
    return @($items).Count
}

function Remove-OldByPattern {
    param(
        [string]$TargetDir,
        [string]$Pattern,
        [int]$Keep = 5,
        [switch]$ApplyDelete
    )
    if (-not (Test-Path -LiteralPath $TargetDir)) { return [pscustomobject]@{ Pattern = $Pattern; Found = 0; Removed = 0; Candidates = @() } }

    $items = @(Get-ChildItem -LiteralPath $TargetDir -File -Filter $Pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($items.Count -le $Keep) {
        return [pscustomobject]@{ Pattern = $Pattern; Found = $items.Count; Removed = 0; Candidates = @() }
    }

    $toDelete = @($items | Select-Object -Skip $Keep)
    $removed = 0
    if ($ApplyDelete) {
        foreach ($item in $toDelete) {
            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $item.FullName)) { $removed++ }
        }
    }

    return [pscustomobject]@{
        Pattern = $Pattern
        Found = $items.Count
        Removed = $removed
        Candidates = @($toDelete | ForEach-Object { $_.Name })
    }
}

$reportsRoot = Join-Path $scriptDir "reports"
$autoDir = Join-Path $reportsRoot "auto-cover"
$normalizeDir = Join-Path $reportsRoot "normalize"
$manualDir = Join-Path $reportsRoot "manual-cover"
$promoteDir = Join-Path $reportsRoot "promote-nested-covers"
$duplicatesDir = Join-Path $reportsRoot "duplicates"

New-DirIfMissing -Path $reportsRoot

$movedAuto = 0
$movedAuto += Move-Pattern -Pattern "AutoCoverBatch.report.*.csv" -DestinationDir $autoDir
$movedAuto += Move-Pattern -Pattern "AutoCoverBatch.report.*.json" -DestinationDir $autoDir
$movedAuto += Move-Pattern -Pattern "AutoCoverReport.json" -DestinationDir $autoDir

$movedNormalize = 0
$movedNormalize += Move-Pattern -Pattern "NormalizeTrackNames.report.*.csv" -DestinationDir $normalizeDir
$movedNormalize += Move-Pattern -Pattern "NormalizeTrackNames.report.*.json" -DestinationDir $normalizeDir

$movedManual = 0
$movedManual += Move-Pattern -Pattern "CoverManualReview.*.csv" -DestinationDir $manualDir
$movedManual += Move-Pattern -Pattern "CoverManualReview.*.json" -DestinationDir $manualDir
$movedManual += Move-Pattern -Pattern "CoverManualReview.todo.*.txt" -DestinationDir $manualDir

$movedPromote = 0
$movedPromote += Move-Pattern -Pattern "PromoteNestedCovers.*.csv" -DestinationDir $promoteDir
$movedPromote += Move-Pattern -Pattern "PromoteNestedCovers.*.json" -DestinationDir $promoteDir

$movedDuplicates = 0
$movedDuplicates += Move-Pattern -Pattern "Doublons_MusicSelektor_*.csv" -DestinationDir $duplicatesDir
$movedDuplicates += Move-Pattern -Pattern "Doublons_MusicSelektor_*.txt" -DestinationDir $duplicatesDir

$pruneResults = @()
$pruneResults += Remove-OldByPattern -TargetDir $autoDir -Pattern "AutoCoverBatch.report.*.csv" -Keep $KeepLatest -ApplyDelete:$DeleteOld
$pruneResults += Remove-OldByPattern -TargetDir $autoDir -Pattern "AutoCoverBatch.report.*.json" -Keep $KeepLatest -ApplyDelete:$DeleteOld
$pruneResults += Remove-OldByPattern -TargetDir $manualDir -Pattern "CoverManualReview.status.*.csv" -Keep $KeepLatest -ApplyDelete:$DeleteOld
$pruneResults += Remove-OldByPattern -TargetDir $manualDir -Pattern "CoverManualReview.status.*.json" -Keep $KeepLatest -ApplyDelete:$DeleteOld
$pruneResults += Remove-OldByPattern -TargetDir $manualDir -Pattern "CoverManualReview.status.*.summary.json" -Keep $KeepLatest -ApplyDelete:$DeleteOld
$pruneResults += Remove-OldByPattern -TargetDir $manualDir -Pattern "CoverManualReview.todo.*.txt" -Keep $KeepLatest -ApplyDelete:$DeleteOld
$pruneResults += Remove-OldByPattern -TargetDir $normalizeDir -Pattern "NormalizeTrackNames.report.*.csv" -Keep $KeepLatest -ApplyDelete:$DeleteOld
$pruneResults += Remove-OldByPattern -TargetDir $normalizeDir -Pattern "NormalizeTrackNames.report.*.json" -Keep $KeepLatest -ApplyDelete:$DeleteOld
$pruneResults += Remove-OldByPattern -TargetDir $promoteDir -Pattern "PromoteNestedCovers.*.csv" -Keep $KeepLatest -ApplyDelete:$DeleteOld
$pruneResults += Remove-OldByPattern -TargetDir $promoteDir -Pattern "PromoteNestedCovers.*.json" -Keep $KeepLatest -ApplyDelete:$DeleteOld
$pruneResults += Remove-OldByPattern -TargetDir $duplicatesDir -Pattern "Doublons_MusicSelektor_*.csv" -Keep $KeepLatest -ApplyDelete:$DeleteOld
$pruneResults += Remove-OldByPattern -TargetDir $duplicatesDir -Pattern "Doublons_MusicSelektor_*.txt" -Keep $KeepLatest -ApplyDelete:$DeleteOld

Write-Output ("Nettoyage termine.")
Write-Output ("Auto-cover moved: {0}" -f $movedAuto)
Write-Output ("Normalize moved: {0}" -f $movedNormalize)
Write-Output ("Manual cover moved: {0}" -f $movedManual)
Write-Output ("Promote moved: {0}" -f $movedPromote)
Write-Output ("Duplicates moved: {0}" -f $movedDuplicates)
Write-Output ("Reports root: {0}" -f $reportsRoot)
Write-Output ("Retention keep-latest: {0}" -f $KeepLatest)
Write-Output ("Delete old enabled: {0}" -f [bool]$DeleteOld)
Write-Output ("")
Write-Output ("Purge candidates by family:")
foreach ($r in $pruneResults) {
    $extra = if ($DeleteOld) { "deleted=$($r.Removed)" } else { "to-delete=$(@($r.Candidates).Count)" }
    Write-Output ("- {0} | found={1} | {2}" -f $r.Pattern, $r.Found, $extra)
}
