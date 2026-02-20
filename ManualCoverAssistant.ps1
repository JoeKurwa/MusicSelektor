param(
    [string]$ReviewCsvPath = "",
    [int]$OpenIndex = 0
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

    return $candidates[0].FullName
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
$items = @($rows | Where-Object { $_.Status -eq "todo-manual" -or [string]::IsNullOrWhiteSpace($_.Status) })

$todoPath = Join-Path $manualReportsDir ("CoverManualReview.todo." + (Get-Date -Format "yyyyMMdd-HHmmss") + ".txt")
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Cover Manual Review") | Out-Null
$lines.Add("Source CSV: $ReviewCsvPath") | Out-Null
$lines.Add("Generated: $(Get-Date -Format 'dd-MM-yyyy HH:mm:ss')") | Out-Null
$lines.Add("") | Out-Null

$idx = 1
foreach ($it in $items) {
    $lines.Add("[$idx] AlbumPath: $($it.AlbumPath)") | Out-Null
    $lines.Add("    Artist: $($it.Artist)") | Out-Null
    $lines.Add("    Album: $($it.Album)") | Out-Null
    $lines.Add("    Query: $($it.Query)") | Out-Null
    $lines.Add("    Url: $($it.ImageSearchUrl)") | Out-Null
    $lines.Add("    Target: $($it.AlbumPath)\cover.jpg") | Out-Null
    $lines.Add("") | Out-Null
    $idx++
}

$lines | Out-File -LiteralPath $todoPath -Encoding UTF8 -Force

if ($OpenIndex -gt 0) {
    if ($OpenIndex -gt $items.Count) {
        throw "OpenIndex invalide: $OpenIndex (max: $($items.Count))."
    }
    $target = $items[$OpenIndex - 1]
    $albumPath = [string]$target.AlbumPath
    $url = [string]$target.ImageSearchUrl

    if (-not [string]::IsNullOrWhiteSpace($albumPath) -and (Test-Path -LiteralPath $albumPath)) {
        Start-Process "explorer.exe" -ArgumentList "`"$albumPath`""
    }
    if (-not [string]::IsNullOrWhiteSpace($url)) {
        Start-Process $url
    }
    Write-Output ("Opened item #{0}: {1}" -f $OpenIndex, $albumPath)
}

Write-Output ("Manual cover items: {0}" -f $items.Count)
Write-Output ("Todo file: {0}" -f $todoPath)
Write-Output "Use: powershell -ExecutionPolicy Bypass -File .\ManualCoverAssistant.ps1 -OpenIndex 1"
