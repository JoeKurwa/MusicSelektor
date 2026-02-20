param(
    [string]$ReportJsonPath = "",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PSScriptRoot }

if ([string]::IsNullOrWhiteSpace($ReportJsonPath)) {
    $latest = Get-ChildItem -LiteralPath $scriptDir -File -Filter "AutoCoverBatch.report.*.json" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { throw "Aucun rapport AutoCoverBatch.report.*.json trouve." }
    $ReportJsonPath = $latest.FullName
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $scriptDir "CoverManualReview.$stamp.csv"
}

if (-not (Test-Path -LiteralPath $ReportJsonPath)) {
    throw "Rapport introuvable: $ReportJsonPath"
}

$items = Get-Content -LiteralPath $ReportJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not ($items -is [System.Array])) { $items = @($items) }

$rows = foreach ($it in $items) {
    if (-not $it) { continue }
    if ([string]$it.Result -ne "not-found") { continue }

    $artist = [string]$it.Artist
    $album = [string]$it.Album
    $query = "$artist $album album cover"
    $query = $query -replace '\s+', ' '
    $query = $query.Trim()
    $url = "https://www.google.com/search?q=$([uri]::EscapeDataString($query))&tbm=isch"

    [pscustomobject]@{
        AlbumPath = [string]$it.AlbumPath
        Artist = $artist
        Album = $album
        Query = $query
        ImageSearchUrl = $url
        SuggestedFileName = "cover.jpg"
        Status = "todo-manual"
    }
}

$rows | Export-Csv -LiteralPath $OutputPath -Delimiter ';' -NoTypeInformation -Encoding UTF8
Write-Output "Manual review file: $OutputPath"
Write-Output "Rows: $(@($rows).Count)"
