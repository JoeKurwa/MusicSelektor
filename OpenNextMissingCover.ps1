param(
    [switch]$Open,
    [switch]$OpenFolder,
    [switch]$OpenBrowser
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PSScriptRoot }
$manualDir = Join-Path $scriptDir "reports\\manual-cover"
$autoDir = Join-Path $scriptDir "reports\\auto-cover"
$stateFile = Join-Path $scriptDir ".next-cover-target.txt"

function Get-LatestFileByRegex {
    param([string]$RegexName)
    $item = Get-ChildItem -LiteralPath $manualDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $RegexName } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($item) { return $item.FullName }
    return ""
}

if (-not (Test-Path -LiteralPath $manualDir)) {
    throw "Dossier introuvable: $manualDir"
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

$statusCsv = Get-LatestFileByRegex -RegexName '^CoverManualReview\.status\..+\.csv$'
# Review source uniquement (sans ".status.") - accepte aussi les suffixes custom (ex: latest).
$reviewCsv = Get-LatestFileByRegex -RegexName '^CoverManualReview\.(?!status\.).+\.csv$'

if ([string]::IsNullOrWhiteSpace($statusCsv)) {
    throw "Aucun status CSV trouve dans $manualDir"
}
if ([string]::IsNullOrWhiteSpace($reviewCsv)) {
    throw "Aucun review CSV trouve dans $manualDir"
}

$reviewRows = Import-Csv -LiteralPath $reviewCsv -Delimiter ';'
$candidates = New-Object System.Collections.Generic.List[object]
$missingFolderCount = 0
foreach ($r in $reviewRows) {
    if (-not $r) { continue }
    $albumPath = [string]$r.AlbumPath
    if ([string]::IsNullOrWhiteSpace($albumPath)) { continue }
    if (-not (Test-Path -LiteralPath $albumPath)) {
        $missingFolderCount++
        continue
    }
    $targetCover = Join-Path $albumPath "cover.jpg"
    $isValidCover = Test-ImageFileDisplayable -Path $targetCover
    if (-not $isValidCover) {
        $candidates.Add($r) | Out-Null
    }
}

# Fallback: si le review CSV est obsolete (paths disparus), on reconstruit depuis le dernier AutoCoverBatch not-found.
if ($candidates.Count -eq 0 -and (Test-Path -LiteralPath $autoDir)) {
    $latestAutoJson = Get-ChildItem -LiteralPath $autoDir -File -Filter "AutoCoverBatch.report.*.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '\.summary\.json$' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latestAutoJson) {
        try {
            $autoRows = Get-Content -LiteralPath $latestAutoJson.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not ($autoRows -is [System.Array])) { $autoRows = @($autoRows) }
            foreach ($a in $autoRows) {
                if (-not $a) { continue }
                if ([string]$a.Result -ne "not-found") { continue }
                $albumPath = [string]$a.AlbumPath
                if ([string]::IsNullOrWhiteSpace($albumPath)) { continue }
                if (-not (Test-Path -LiteralPath $albumPath)) { continue }
                $targetCover = Join-Path $albumPath "cover.jpg"
                if (Test-ImageFileDisplayable -Path $targetCover) { continue }
                $artist = [string]$a.Artist
                $album = [string]$a.Album
                $query = "$artist $album album cover" -replace '\s+', ' '
                $url = "https://www.google.com/search?q=$([uri]::EscapeDataString($query.Trim()))&tbm=isch"
                $candidates.Add([pscustomobject]@{
                    AlbumPath = $albumPath
                    Artist = $artist
                    Album = $album
                    Query = $query.Trim()
                    ImageSearchUrl = $url
                }) | Out-Null
            }
        } catch { }
    }
}

if ($candidates.Count -eq 0) {
    try { "" | Out-File -LiteralPath $stateFile -Encoding UTF8 -Force } catch { }
    Write-Output "Aucun album manquant exploitable. Soit tout est OK, soit la liste pointe vers des chemins obsoletes."
    if ($missingFolderCount -gt 0) {
        Write-Output ("Chemins obsoletes ignores: {0}" -f $missingFolderCount)
    }
    exit 0
}

$next = $candidates[0]
$albumPath = [string]$next.AlbumPath
$query = [string]$next.Query
$url = [string]$next.ImageSearchUrl
if ([string]::IsNullOrWhiteSpace($url) -and -not [string]::IsNullOrWhiteSpace($query)) {
    $url = "https://www.google.com/search?q=$([uri]::EscapeDataString($query))&tbm=isch"
}

Write-Output ("Next album path: {0}" -f $albumPath)
Write-Output ("Query: {0}" -f $query)
Write-Output ("URL: {0}" -f $url)
Write-Output ("Target file: {0}" -f (Join-Path $albumPath "cover.jpg"))
Write-Output ("Remaining missing: {0}" -f $candidates.Count)
if ($missingFolderCount -gt 0) {
    Write-Output ("Ignored missing folders from review list: {0}" -f $missingFolderCount)
}

# Facilite ton workflow "Enregistrer sous" :
# - le dossier cible est copie dans le presse-papiers pour Ctrl+V dans la barre de chemin.
try {
    if (-not [string]::IsNullOrWhiteSpace($albumPath)) {
        Set-Clipboard -Value $albumPath
        Write-Output ("Clipboard path: {0}" -f $albumPath)
    }
} catch { }

# Compat backward: -Open active folder+browser.
if ($Open) {
    $OpenFolder = $true
    $OpenBrowser = $true
}

try { $albumPath | Out-File -LiteralPath $stateFile -Encoding UTF8 -Force } catch { }

if ($OpenFolder) {
    if (-not [string]::IsNullOrWhiteSpace($albumPath) -and (Test-Path -LiteralPath $albumPath)) {
        Start-Process "explorer.exe" -ArgumentList "`"$albumPath`""
        Write-Output "Opened folder for next missing item."
    }
}
if ($OpenBrowser) {
    if (-not [string]::IsNullOrWhiteSpace($url)) {
        Start-Process $url
        Write-Output "Opened browser for next missing item."
    }
}
