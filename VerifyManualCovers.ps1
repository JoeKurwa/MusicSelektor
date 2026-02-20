param(
    [string]$ReviewCsvPath = "",
    [string]$OutputPrefix = "CoverManualReview.status"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PSScriptRoot }
$manualReportsDir = Join-Path $scriptDir "reports\\manual-cover"
if (-not (Test-Path -LiteralPath $manualReportsDir)) {
    New-Item -ItemType Directory -Path $manualReportsDir -Force | Out-Null
}

function Get-ReviewCsvCandidates {
    $manualCandidates = @()
    if (Test-Path -LiteralPath $manualReportsDir) {
        $manualCandidates = Get-ChildItem -LiteralPath $manualReportsDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^CoverManualReview\.(?!status\.).+\.csv$' }
    }
    $rootCandidates = Get-ChildItem -LiteralPath $scriptDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^CoverManualReview\.(?!status\.).+\.csv$' }
    @($manualCandidates + $rootCandidates) |
        Sort-Object LastWriteTime -Descending
}

function Get-ExistingAlbumPathCount {
    param([string]$CsvPath)
    try {
        $rows = Import-Csv -LiteralPath $CsvPath -Delimiter ';'
        if (-not $rows) { return 0 }
        $count = 0
        foreach ($r in $rows) {
            $p = [string]$r.AlbumPath
            if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p)) {
                $count++
            }
        }
        return $count
    } catch {
        return 0
    }
}

function Get-LatestReviewCsv {
    $candidates = Get-ReviewCsvCandidates
    if (-not $candidates -or $candidates.Count -eq 0) { return "" }

    foreach ($candidate in $candidates) {
        $existingCount = Get-ExistingAlbumPathCount -CsvPath $candidate.FullName
        if ($existingCount -gt 0) {
            return $candidate.FullName
        }
    }

    # Fallback: si tout est obsolete, on garde quand meme le plus recent.
    return $candidates[0].FullName
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

if ([string]::IsNullOrWhiteSpace($ReviewCsvPath)) {
    $ReviewCsvPath = Get-LatestReviewCsv
}
if ([string]::IsNullOrWhiteSpace($ReviewCsvPath)) {
    throw "Aucun fichier CoverManualReview.*.csv trouve."
}
if (-not (Test-Path -LiteralPath $ReviewCsvPath)) {
    throw "Fichier introuvable: $ReviewCsvPath"
}

$rows = Import-Csv -LiteralPath $ReviewCsvPath -Delimiter ';'
$statusRows = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    $albumPath = [string]$row.AlbumPath
    $coverPath = Join-Path $albumPath "cover.jpg"
    $status = ""
    $details = ""

    if ([string]::IsNullOrWhiteSpace($albumPath) -or -not (Test-Path -LiteralPath $albumPath)) {
        $status = "missing-folder"
        $details = "Album path missing"
    } elseif (-not (Test-Path -LiteralPath $coverPath)) {
        $status = "missing-cover-jpg"
        $details = "cover.jpg absent"
    } elseif (-not (Test-ImageFileDisplayable -Path $coverPath)) {
        $status = "invalid-cover-jpg"
        $details = "cover.jpg present but invalid/corrupt"
    } else {
        $status = "ok"
        $details = "cover.jpg valid"
    }

    $statusRows.Add([pscustomobject]@{
        AlbumPath = $albumPath
        Artist = [string]$row.Artist
        Album = [string]$row.Album
        Query = [string]$row.Query
        ImageSearchUrl = [string]$row.ImageSearchUrl
        SuggestedFileName = [string]$row.SuggestedFileName
        ManualStatus = [string]$row.Status
        VerifyStatus = $status
        VerifyDetails = $details
        CoverPath = $coverPath
    }) | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$csvOut = Join-Path $manualReportsDir "$OutputPrefix.$stamp.csv"
$jsonOut = Join-Path $manualReportsDir "$OutputPrefix.$stamp.json"
$summaryOut = Join-Path $manualReportsDir "$OutputPrefix.$stamp.summary.json"

$statusRows | Export-Csv -LiteralPath $csvOut -Delimiter ';' -NoTypeInformation -Encoding UTF8
$statusRows | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $jsonOut -Encoding UTF8 -Force

$ok = @($statusRows | Where-Object { $_.VerifyStatus -eq "ok" }).Count
$missingCover = @($statusRows | Where-Object { $_.VerifyStatus -eq "missing-cover-jpg" }).Count
$invalidCover = @($statusRows | Where-Object { $_.VerifyStatus -eq "invalid-cover-jpg" }).Count
$missingFolder = @($statusRows | Where-Object { $_.VerifyStatus -eq "missing-folder" }).Count

$total = $statusRows.Count
$totalActif = $total - $missingFolder
if ($totalActif -lt 0) { $totalActif = 0 }
$summary = [ordered]@{
    timestamp = (Get-Date).ToString("o")
    sourceCsv = $ReviewCsvPath
    total = $total
    totalActif = $totalActif
    ok = $ok
    missingCoverJpg = $missingCover
    invalidCoverJpg = $invalidCover
    missingFolderIgnored = $missingFolder
    csvReport = $csvOut
    jsonReport = $jsonOut
}
$summary | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $summaryOut -Encoding UTF8 -Force

Write-Output ("Verification manuel covers: total-actif={0} ok={1} pochettes-manquantes={2} pochettes-invalides={3} dossiers-supprimes-ignores={4}" -f `
    $totalActif, $ok, $missingCover, $invalidCover, $missingFolder)
