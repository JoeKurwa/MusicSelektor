param(
    [string]$ReviewCsvPath = "",
    [switch]$Apply,
    [switch]$IUnderstand
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PSScriptRoot }
$writeLogPath = Join-Path $scriptDir "MusicSelektor.write-actions.log"
$promoteReportsDir = Join-Path $scriptDir "reports\\promote-nested-covers"
if (-not (Test-Path -LiteralPath $promoteReportsDir)) {
    New-Item -ItemType Directory -Path $promoteReportsDir -Force | Out-Null
}
$effectiveApply = ($Apply -and $IUnderstand)

function Get-LatestReviewCsv {
    $latest = Get-ChildItem -LiteralPath $scriptDir -File -Filter "CoverManualReview.status.*.csv" -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return ""
}

function Write-WriteActionLog {
    param(
        [string]$Action,
        [string]$Status,
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$Details
    )
    try {
        $stamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
        "$stamp script=PromoteNestedCovers action=$Action status=$Status source=`"$SourcePath`" target=`"$TargetPath`" details=`"$Details`"" | Out-File -LiteralPath $writeLogPath -Encoding UTF8 -Append
    } catch { }
}

function Test-ImageFileDisplayable {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $file = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($file.Length -lt 8) { return $false }
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $bytes = New-Object byte[] 8
            $null = $stream.Read($bytes, 0, 8)
            $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
            if ($ext -eq ".png") {
                return ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47)
            }
            if ($ext -eq ".jpg" -or $ext -eq ".jpeg") {
                return ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8)
            }
            return $false
        } finally {
            $stream.Close()
        }
    } catch {
        return $false
    }
}

function Get-BestNestedImage {
    param([string]$AlbumPath)
    if ([string]::IsNullOrWhiteSpace($AlbumPath)) { return $null }
    if (-not (Test-Path -LiteralPath $AlbumPath)) { return $null }
    try {
        $images = @(
            Get-ChildItem -LiteralPath $AlbumPath -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^(?i)\.(jpg|jpeg|png)$' } |
            Where-Object { $_.Name -notmatch '^(?i)(cover|folder|front|album|artwork)\.(jpg|jpeg|png)$' }
        )
        if ($images.Count -eq 0) { return $null }
        $validImages = @($images | Where-Object { Test-ImageFileDisplayable -Path $_.FullName })
        if ($validImages.Count -eq 0) { return $null }
        return ($validImages | Sort-Object Length -Descending | Select-Object -First 1)
    } catch {
        return $null
    }
}

if ([string]::IsNullOrWhiteSpace($ReviewCsvPath)) {
    $ReviewCsvPath = Get-LatestReviewCsv
}
if ([string]::IsNullOrWhiteSpace($ReviewCsvPath)) {
    throw "Aucun fichier CoverManualReview.status.*.csv trouve."
}
if (-not (Test-Path -LiteralPath $ReviewCsvPath)) {
    throw "Fichier introuvable: $ReviewCsvPath"
}

$rows = Import-Csv -LiteralPath $ReviewCsvPath -Delimiter ';'
$reportRows = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    $albumPath = [string]$row.AlbumPath
    $targetCover = Join-Path $albumPath "cover.jpg"
    $status = ""
    $details = ""
    $source = ""

    if ([string]::IsNullOrWhiteSpace($albumPath) -or -not (Test-Path -LiteralPath $albumPath)) {
        $status = "missing-folder"
        $details = "Album path missing"
    } elseif (Test-Path -LiteralPath $targetCover) {
        if (Test-ImageFileDisplayable -Path $targetCover) {
            $status = "already-ok"
            $details = "cover.jpg already valid"
        } else {
            $status = "invalid-existing-cover"
            $details = "cover.jpg exists but invalid"
        }
    } else {
        $candidate = Get-BestNestedImage -AlbumPath $albumPath
        if (-not $candidate) {
            $status = "no-candidate"
            $details = "No valid nested image found"
        } else {
            $source = $candidate.FullName
            if ($effectiveApply) {
                try {
                    Copy-Item -LiteralPath $source -Destination $targetCover -Force -ErrorAction Stop
                    $status = "copied"
                    $details = "Nested image promoted to cover.jpg"
                    Write-WriteActionLog -Action "copy-cover" -Status "applied" -SourcePath $source -TargetPath $targetCover -Details "Apply+IUnderstand"
                } catch {
                    $status = "error"
                    $details = $_.Exception.Message
                    Write-WriteActionLog -Action "copy-cover" -Status "error" -SourcePath $source -TargetPath $targetCover -Details $_.Exception.Message
                }
            } elseif ($Apply -and -not $IUnderstand) {
                $status = "blocked-safety"
                $details = "Blocked: use -Apply -IUnderstand"
                Write-WriteActionLog -Action "copy-cover" -Status "blocked-safety" -SourcePath $source -TargetPath $targetCover -Details "Missing -IUnderstand"
            } else {
                $status = "preview-candidate"
                $details = "Candidate found (preview only)"
            }
        }
    }

    $reportRows.Add([pscustomobject]@{
        AlbumPath = $albumPath
        Artist = [string]$row.Artist
        Album = [string]$row.Album
        CurrentVerifyStatus = [string]$row.VerifyStatus
        CandidateSource = $source
        TargetCover = $targetCover
        Result = $status
        Details = $details
    }) | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$mode = if ($effectiveApply) { "apply" } elseif ($Apply) { "apply-blocked-safety" } else { "preview" }
$csvOut = Join-Path $promoteReportsDir "PromoteNestedCovers.$mode.$stamp.csv"
$jsonOut = Join-Path $promoteReportsDir "PromoteNestedCovers.$mode.$stamp.json"

$reportRows | Export-Csv -LiteralPath $csvOut -Delimiter ';' -NoTypeInformation -Encoding UTF8
$reportRows | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $jsonOut -Encoding UTF8 -Force

$copied = @($reportRows | Where-Object { $_.Result -eq "copied" }).Count
$alreadyOk = @($reportRows | Where-Object { $_.Result -eq "already-ok" }).Count
$previewCandidate = @($reportRows | Where-Object { $_.Result -eq "preview-candidate" }).Count
$noCandidate = @($reportRows | Where-Object { $_.Result -eq "no-candidate" }).Count
$blocked = @($reportRows | Where-Object { $_.Result -eq "blocked-safety" }).Count
$errors = @($reportRows | Where-Object { $_.Result -eq "error" }).Count

Write-Output ("PromoteNestedCovers mode={0} total={1} copied={2} already-ok={3} preview-candidate={4} no-candidate={5} blocked-safety={6} error={7}" -f `
    $mode, $reportRows.Count, $copied, $alreadyOk, $previewCandidate, $noCandidate, $blocked, $errors)
Write-Output ("Reports: {0} | {1}" -f $csvOut, $jsonOut)
