param(
    [string]$LibraryPath = (Join-Path $PSScriptRoot "Library.json"),
    [string]$CoverCachePath = (Join-Path $PSScriptRoot "CoverSearchCache.json"),
    [string]$ReportPrefix = "reports\\auto-cover\\AutoCoverBatch.report",
    [int]$BatchLimit = 75,
    [int]$PauseBetweenBatchesMs = 1200,
    [int]$NotFoundCooldownDays = 14,
    [bool]$NetworkTraceEnabled = $false,
    [switch]$ForceRetryNotFound,
    [switch]$Aggressive
)

$ErrorActionPreference = "Stop"
$script:RunStartedAt = Get-Date
$script:CurrentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($script:CurrentDir)) { $script:CurrentDir = $PSScriptRoot }
$script:NetworkTraceLogPath = Join-Path $script:CurrentDir "MusicSelektor.network.trace.log"
$script:NetworkTracePreviousPath = Join-Path $script:CurrentDir "MusicSelektor.network.trace.previous.log"
$script:CoverCache = @{}
$script:LastApiRequestAt = [datetime]::MinValue
$script:ItunesMinScore = if ($Aggressive) { 2 } else { 4 }
$reportPrefixDir = Split-Path -Path (Join-Path $PSScriptRoot $ReportPrefix) -Parent
if (-not [string]::IsNullOrWhiteSpace($reportPrefixDir) -and -not (Test-Path -LiteralPath $reportPrefixDir)) {
    New-Item -ItemType Directory -Path $reportPrefixDir -Force | Out-Null
}

function Write-NetworkTrace {
    param(
        [string]$Action,
        [string]$Provider,
        [string]$Url,
        [string]$Status,
        [string]$Details
    )
    if (-not $NetworkTraceEnabled) { return }
    try {
        $stamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
        "$stamp action=$Action provider=$Provider status=$Status url=`"$Url`" details=`"$Details`"" | Out-File -LiteralPath $script:NetworkTraceLogPath -Encoding UTF8 -Append
    } catch { }
}

function Initialize-NetworkTraceLog {
    if (-not $NetworkTraceEnabled) { return }
    try {
        if (Test-Path -LiteralPath $script:NetworkTraceLogPath) {
            try {
                Copy-Item -LiteralPath $script:NetworkTraceLogPath -Destination $script:NetworkTracePreviousPath -Force -ErrorAction Stop
            } catch { }
        }
        Set-Content -LiteralPath $script:NetworkTraceLogPath -Value "" -Encoding UTF8 -Force
    } catch { }
}

function Get-JsonArraySafe {
    param([string]$RawJson)
    if ([string]::IsNullOrWhiteSpace($RawJson)) { return @() }
    $parsed = ConvertFrom-Json -InputObject $RawJson
    if ($null -eq $parsed) { return @() }
    if ($parsed -is [System.Array]) { return $parsed }
    return @($parsed)
}

function Test-IsDiscFolderName {
    param([string]$FolderName)
    if ([string]::IsNullOrWhiteSpace($FolderName)) { return $false }
    return ($FolderName -match '^(cd|disc|disk)\s*0*\d+$')
}

function Get-AlbumCanonicalName {
    param([string]$AlbumPath)
    try {
        $leaf = Split-Path -Path $AlbumPath -Leaf
        if (Test-IsDiscFolderName -FolderName $leaf) {
            $parent = Split-Path -Path $AlbumPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($parent)) {
                return (Split-Path -Path $parent -Leaf)
            }
        }
        return $leaf
    } catch {
        return ""
    }
}

function Get-NormalizedSearchText {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $v = $Value
    $v = $v -replace '&amp;', '&'
    $v = $v -replace '[_]+', ' '
    $v = $v -replace '\s+', ' '
    $v = $v.Trim(" .-_`t")
    return $v
}

function Test-IsTechnicalFolderName {
    param([string]$FolderName)
    if ([string]::IsNullOrWhiteSpace($FolderName)) { return $true }
    $n = $FolderName.Trim()
    if ($n -match '^[A-Za-z]:$') { return $true }
    if (Test-IsDiscFolderName -FolderName $n) { return $true }
    if ($n -match '^(?i)(audio|tracks?|files?|cover(s)?|artwork|jaquette|bonus(\s*tracks?)?|unknown album|freestyle(s)?|mp3|wav|flac)$') { return $true }
    if ($n -match '^(?i).+\.itlp$') { return $true }
    if ($n -match '^(?i).*(bootleg|fr3sh|web).*$') { return $true }
    return $false
}

function Get-CleanAlbumQuery {
    param([string]$Album)
    if ([string]::IsNullOrWhiteSpace($Album)) { return "" }
    $a = $Album
    $a = $a -replace '[_]+', ' '
    $a = $a -replace '\s+', ' '
    # Coupe les suffixes techniques ou incomplets
    $a = $a -replace '(?i)\s*\(mixed\s*.*$', ''
    $a = $a -replace '(?i)\s*-\s*(bootleg|fr3sh|web).*$',''
    $a = $a -replace '(?i)\s*\b(mp3|wav|flac)\b\s*$',''
    $a = $a.Trim(" -_`t")
    return $a
}

function Split-ArtistAlbumFromCombined {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [pscustomobject]@{ Artist = ""; Album = "" }
    }
    $v = Get-NormalizedSearchText -Value $Value
    if ($v -match '^\s*(?<artist>[^-]+?)\s*-\s*(?<album>.+?)\s*$') {
        return [pscustomobject]@{
            Artist = (Get-NormalizedSearchText -Value $matches.artist)
            Album = (Get-NormalizedSearchText -Value $matches.album)
        }
    }
    return [pscustomobject]@{ Artist = ""; Album = "" }
}

function Get-SearchMetadataFromPath {
    param([string]$AlbumPath)
    $artist = ""
    $album = ""
    $albumWasUnknown = $false
    try {
        $parts = @($AlbumPath -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($parts.Count -eq 0) {
            return [pscustomobject]@{ Artist = ""; Album = "" }
        }

        $albumIdx = -1
        for ($i = $parts.Count - 1; $i -ge 0; $i--) {
            if (-not (Test-IsTechnicalFolderName -FolderName $parts[$i])) {
                $albumIdx = $i
                break
            }
        }
        if ($albumIdx -ge 0) {
            $album = $parts[$albumIdx]
            for ($j = $albumIdx - 1; $j -ge 0; $j--) {
                if (-not (Test-IsTechnicalFolderName -FolderName $parts[$j])) {
                    $artist = $parts[$j]
                    break
                }
            }
        }
    } catch { }

    $artist = Get-NormalizedSearchText -Value $artist
    $album = Get-NormalizedSearchText -Value $album

    if ([string]::IsNullOrWhiteSpace($artist)) {
        $artist = Get-NormalizedSearchText -Value (Get-AlbumArtistGuess -AlbumPath $AlbumPath)
    }
    if ([string]::IsNullOrWhiteSpace($album) -and -not $albumWasUnknown) {
        $album = Get-NormalizedSearchText -Value (Get-AlbumCanonicalName -AlbumPath $AlbumPath)
    }

    # Evite les requetes trop faibles de type "Unknown Album"
    if ($album -match '^(?i)unknown album$') {
        $album = ""
        $albumWasUnknown = $true
    }
    if ($artist -match '^[A-Za-z]:$') {
        $artist = ""
    }
    if ($artist -match '^(?i)freestyle(s)?$') {
        $artist = ""
    }
    if (-not [string]::IsNullOrWhiteSpace($artist) -and -not [string]::IsNullOrWhiteSpace($album) -and $artist.ToLowerInvariant() -eq $album.ToLowerInvariant()) {
        # Cas ambigu (ex: "Bouba\Unknown Album" => artiste=album), on force une recherche plus prudente.
        $album = ""
    }

    # Si un dossier combine "Artiste - Album", on extrait proprement.
    if ([string]::IsNullOrWhiteSpace($artist) -or [string]::IsNullOrWhiteSpace($album)) {
        $parts = @($AlbumPath -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        foreach ($p in $parts) {
            $split = Split-ArtistAlbumFromCombined -Value $p
            if ([string]::IsNullOrWhiteSpace($artist) -and -not [string]::IsNullOrWhiteSpace($split.Artist)) {
                $artist = $split.Artist
            }
            if ([string]::IsNullOrWhiteSpace($album) -and -not [string]::IsNullOrWhiteSpace($split.Album)) {
                $album = $split.Album
            }
        }
    }

    $album = Get-CleanAlbumQuery -Album $album

    return [pscustomobject]@{
        Artist = $artist
        Album = $album
    }
}

function Get-AlbumArtistGuess {
    param([string]$AlbumPath)
    try {
        $leaf = Split-Path -Path $AlbumPath -Leaf
        $parent = Split-Path -Path $AlbumPath -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) { return "" }
        if (Test-IsDiscFolderName -FolderName $leaf) {
            $grandParent = Split-Path -Path $parent -Parent
            if (-not [string]::IsNullOrWhiteSpace($grandParent)) {
                return (Split-Path -Path $grandParent -Leaf)
            }
        }
        return (Split-Path -Path $parent -Leaf)
    } catch {
        return ""
    }
}

function Get-CoverSearchDirectories {
    param([string]$AlbumPath)
    $dirs = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($AlbumPath)) { return @() }
    if (-not (Test-Path -LiteralPath $AlbumPath)) { return @() }

    $dirs.Add($AlbumPath) | Out-Null

    $parent = $null
    try { $parent = Split-Path -Path $AlbumPath -Parent } catch { $parent = $null }
    if (-not [string]::IsNullOrWhiteSpace($parent) -and (Test-Path -LiteralPath $parent)) {
        $dirs.Add($parent) | Out-Null
        foreach ($sub in @("Jaquette", "jaquette", "Covers", "covers", "Artwork", "artwork")) {
            $candidate = Join-Path $parent $sub
            if (Test-Path -LiteralPath $candidate) {
                $dirs.Add($candidate) | Out-Null
            }
        }
    }

    return @($dirs | Select-Object -Unique)
}

function Get-AlbumCoverFile {
    param([string]$AlbumPath)
    if (-not (Test-Path -LiteralPath $AlbumPath)) { return $null }

    $albumName = Split-Path -Path $AlbumPath -Leaf
    $priorityNames = @(
        "cover.jpg", "cover.png", "cover.jpeg",
        "folder.jpg", "folder.png", "folder.jpeg",
        "album.jpg", "album.png", "album.jpeg",
        "artwork.jpg", "artwork.png", "artwork.jpeg",
        "front.jpg", "front.png", "front.jpeg",
        "Front.jpg", "Front.png", "Front.jpeg",
        "$albumName.jpg", "$albumName.png", "$albumName.jpeg"
    )

    $searchDirs = Get-CoverSearchDirectories -AlbumPath $AlbumPath
    foreach ($dir in $searchDirs) {
        foreach ($name in $priorityNames) {
            $candidate = Join-Path $dir $name
            if (Test-Path -LiteralPath $candidate) {
                try { return (Get-Item -LiteralPath $candidate -ErrorAction Stop) } catch { }
            }
        }
    }

    foreach ($dir in $searchDirs) {
        try {
            $images = @(
                Get-ChildItem -LiteralPath $dir -File -Recurse -Depth 1 -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '^(?i)\.(jpg|jpeg|png)$' }
            )
            if ($images.Count -gt 0) {
                $best = $images | Sort-Object Length -Descending | Select-Object -First 1
                if ($best) { return $best }
            }
        } catch { }
    }

    return $null
}

function Test-CoverDisplayable {
    param([string]$CoverPath)
    if (-not (Test-Path -LiteralPath $CoverPath)) { return $false }
    try {
        $file = Get-Item -LiteralPath $CoverPath -ErrorAction Stop
        if ($file.Length -lt 8) { return $false }

        $stream = [System.IO.File]::Open($CoverPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $bytes = New-Object byte[] 8
            $null = $stream.Read($bytes, 0, 8)
            $ext = [System.IO.Path]::GetExtension($CoverPath).ToLowerInvariant()
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

function Wait-ApiThrottle {
    $minDelayMs = 250
    $elapsed = (Get-Date) - $script:LastApiRequestAt
    if ($elapsed.TotalMilliseconds -lt $minDelayMs) {
        Start-Sleep -Milliseconds ([int]($minDelayMs - $elapsed.TotalMilliseconds))
    }
    $script:LastApiRequestAt = Get-Date
}

function Import-CoverCache {
    $script:CoverCache = @{}
    if (-not (Test-Path -LiteralPath $CoverCachePath)) { return }
    try {
        $raw = Get-Content -LiteralPath $CoverCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($raw) {
            foreach ($p in $raw.PSObject.Properties) {
                $script:CoverCache[$p.Name] = $p.Value
            }
        }
    } catch {
        $script:CoverCache = @{}
    }
}

function Save-CoverCache {
    try {
        $obj = [ordered]@{}
        foreach ($k in $script:CoverCache.Keys) {
            $obj[$k] = $script:CoverCache[$k]
        }
        $obj | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $CoverCachePath -Encoding UTF8 -Force
    } catch { }
}

function Get-CoverCacheKey {
    param([string]$Artist, [string]$Album)
    $a = if ($Artist) { $Artist.Trim().ToLowerInvariant() } else { "" }
    $b = if ($Album) { $Album.Trim().ToLowerInvariant() } else { "" }
    return "$a|$b"
}

function Get-ItunesCoverUrl {
    param([string]$Artist, [string]$Album)
    try {
        Wait-ApiThrottle
        $term = [uri]::EscapeDataString("$Artist $Album")
        $url = "https://itunes.apple.com/search?term=$term&entity=album&limit=20"
        Write-NetworkTrace -Action "request" -Provider "iTunes" -Url $url -Status "start" -Details ("artist={0}; album={1}" -f $Artist, $Album)
        $result = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 15 -ErrorAction Stop
        if (-not $result -or -not $result.results) {
            Write-NetworkTrace -Action "request" -Provider "iTunes" -Url $url -Status "not-found" -Details "No results"
            return $null
        }

        $albumNorm = $Album.ToLowerInvariant()
        $artistNorm = $Artist.ToLowerInvariant()
        $best = $null
        $bestScore = -1
        foreach ($r in $result.results) {
            $score = 0
            if ($r.collectionName) {
                $nameNorm = $r.collectionName.ToLowerInvariant()
                if ($nameNorm -eq $albumNorm) { $score += 3 }
                elseif ($nameNorm -like "*$albumNorm*") { $score += 1 }
            }
            if ($r.artistName) {
                $artistNameNorm = $r.artistName.ToLowerInvariant()
                if ($artistNameNorm -eq $artistNorm) { $score += 3 }
                elseif ($artistNameNorm -like "*$artistNorm*") { $score += 1 }
            }
            if ($score -gt $bestScore) {
                $bestScore = $score
                $best = $r
            }
        }
        # Qualite minimale (mode normal strict, mode agressif plus permissif).
        if (-not $best -or -not $best.artworkUrl100 -or $bestScore -lt $script:ItunesMinScore) {
            Write-NetworkTrace -Action "request" -Provider "iTunes" -Url $url -Status "low-score" -Details ("bestScore={0}; minScore={1}; aggressive={2}" -f $bestScore, $script:ItunesMinScore, [bool]$Aggressive)
            return $null
        }
        $coverUrl = ($best.artworkUrl100 -replace "100x100bb", "1200x1200bb")
        Write-NetworkTrace -Action "request" -Provider "iTunes" -Url $url -Status "ok" -Details ("bestScore={0}; minScore={1}; aggressive={2}; cover={3}" -f $bestScore, $script:ItunesMinScore, [bool]$Aggressive, $coverUrl)
        return $coverUrl
    } catch {
        Write-NetworkTrace -Action "request" -Provider "iTunes" -Url $url -Status "error" -Details $_.Exception.Message
        return $null
    }
}

function Get-MusicBrainzCoverUrl {
    param([string]$Artist, [string]$Album)
    try {
        Wait-ApiThrottle
        $query = "release:`"$Album`" AND artist:`"$Artist`""
        $url = "https://musicbrainz.org/ws/2/release/?query=$([uri]::EscapeDataString($query))&fmt=json&limit=5"
        $headers = @{ "User-Agent" = "MusicSelektor/1.0 (cover-fetch)" }
        Write-NetworkTrace -Action "request" -Provider "MusicBrainz" -Url $url -Status "start" -Details ("artist={0}; album={1}" -f $Artist, $Album)
        $result = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 20 -ErrorAction Stop
        if (-not $result -or -not $result.releases) {
            Write-NetworkTrace -Action "request" -Provider "MusicBrainz" -Url $url -Status "not-found" -Details "No releases"
            return $null
        }

        foreach ($release in $result.releases) {
            if (-not $release.id) { continue }
            $candidate = "https://coverartarchive.org/release/$($release.id)/front-500"
            try {
                Wait-ApiThrottle
                Write-NetworkTrace -Action "probe" -Provider "CoverArtArchive" -Url $candidate -Status "start" -Details "HEAD"
                $probe = Invoke-WebRequest -Uri $candidate -Method Head -TimeoutSec 10 -ErrorAction Stop
                if ($probe.StatusCode -ge 200 -and $probe.StatusCode -lt 300) {
                    Write-NetworkTrace -Action "probe" -Provider "CoverArtArchive" -Url $candidate -Status "ok" -Details ("statusCode={0}" -f $probe.StatusCode)
                    return $candidate
                }
            } catch {
                Write-NetworkTrace -Action "probe" -Provider "CoverArtArchive" -Url $candidate -Status "error" -Details $_.Exception.Message
            }
        }
        Write-NetworkTrace -Action "request" -Provider "MusicBrainz" -Url $url -Status "not-found" -Details "No release with accessible cover"
        return $null
    } catch {
        Write-NetworkTrace -Action "request" -Provider "MusicBrainz" -Url $url -Status "error" -Details $_.Exception.Message
        return $null
    }
}

function Save-CoverFromUrl {
    param([string]$Url, [string]$AlbumPath)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    if (-not (Test-Path -LiteralPath $AlbumPath)) { return $false }

    $tempFile = Join-Path $env:TEMP ("MusicSelektor_cover_" + [guid]::NewGuid().ToString() + ".jpg")
    $targetFile = Join-Path $AlbumPath "cover.jpg"
    try {
        Wait-ApiThrottle
        Write-NetworkTrace -Action "download" -Provider "CoverDownload" -Url $Url -Status "start" -Details ("target={0}" -f $targetFile)
        Invoke-WebRequest -Uri $Url -OutFile $tempFile -TimeoutSec 25 -ErrorAction Stop
        if (-not (Test-CoverDisplayable -CoverPath $tempFile)) {
            Write-NetworkTrace -Action "download" -Provider "CoverDownload" -Url $Url -Status "invalid-image" -Details ("temp={0}" -f $tempFile)
            return $false
        }
        Move-Item -LiteralPath $tempFile -Destination $targetFile -Force
        Write-NetworkTrace -Action "download" -Provider "CoverDownload" -Url $Url -Status "saved" -Details ("target={0}" -f $targetFile)
        return $true
    } catch {
        Write-NetworkTrace -Action "download" -Provider "CoverDownload" -Url $Url -Status "error" -Details $_.Exception.Message
        return $false
    } finally {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Find-And-SaveCoverForAlbum {
    param([string]$AlbumPath)
    if (-not (Test-Path -LiteralPath $AlbumPath)) { return "missing-folder" }

    $existing = Get-AlbumCoverFile -AlbumPath $AlbumPath
    if ($existing -and (Test-CoverDisplayable -CoverPath $existing.FullName)) {
        return "already-ok"
    }

    $meta = Get-SearchMetadataFromPath -AlbumPath $AlbumPath
    $albumName = [string]$meta.Album
    $artistName = [string]$meta.Artist
    if ([string]::IsNullOrWhiteSpace($albumName)) { return "no-metadata" }
    $cacheKey = Get-CoverCacheKey -Artist $artistName -Album $albumName

    if ($script:CoverCache.ContainsKey($cacheKey)) {
        $entry = $script:CoverCache[$cacheKey]
        if (-not $ForceRetryNotFound -and $entry.status -eq "not-found" -and $entry.lastTry) {
            try {
                $lastTry = [datetime]::Parse($entry.lastTry)
                if (((Get-Date) - $lastTry).TotalDays -lt $NotFoundCooldownDays) {
                    return "not-found-cache"
                }
            } catch { }
        }
        if ($entry.url) {
            if (Save-CoverFromUrl -Url $entry.url -AlbumPath $AlbumPath) {
                return "downloaded-cache"
            }
        }
    }

    $coverUrl = Get-ItunesCoverUrl -Artist $artistName -Album $albumName
    if (-not $coverUrl) {
        $coverUrl = Get-MusicBrainzCoverUrl -Artist $artistName -Album $albumName
    }
    if (-not $coverUrl) {
        $script:CoverCache[$cacheKey] = [pscustomobject]@{
            status = "not-found"
            url = ""
            lastTry = (Get-Date).ToString("o")
        }
        return "not-found"
    }

    if (Save-CoverFromUrl -Url $coverUrl -AlbumPath $AlbumPath) {
        $script:CoverCache[$cacheKey] = [pscustomobject]@{
            status = "downloaded"
            url = $coverUrl
            lastTry = (Get-Date).ToString("o")
        }
        return "downloaded"
    }

    $script:CoverCache[$cacheKey] = [pscustomobject]@{
        status = "download-failed"
        url = $coverUrl
        lastTry = (Get-Date).ToString("o")
    }
    return "download-failed"
}

function Get-AlbumState {
    param([string]$AlbumPath)
    if (-not (Test-Path -LiteralPath $AlbumPath)) { return "missing-folder" }
    $cover = Get-AlbumCoverFile -AlbumPath $AlbumPath
    if (-not $cover) { return "missing-cover" }
    if (Test-CoverDisplayable -CoverPath $cover.FullName) { return "ok" }
    return "invalid-cover"
}

if (-not (Test-Path -LiteralPath $LibraryPath)) {
    throw "Library introuvable: $LibraryPath"
}

Initialize-NetworkTraceLog
Write-NetworkTrace -Action "session-start" -Provider "AutoCoverBatch" -Url "" -Status "ok" -Details ("NetworkTraceEnabled={0}; LogPath={1}" -f $NetworkTraceEnabled, $script:NetworkTraceLogPath)
Import-CoverCache

$rawJson = Get-Content -LiteralPath $LibraryPath -Raw -Encoding UTF8
$rows = Get-JsonArraySafe -RawJson $rawJson
$albums = @(
    $rows |
    Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace($_.FullDir) } |
    Select-Object -ExpandProperty FullDir -Unique |
    Where-Object { $_ -and ($_ -notmatch '^[A-Za-z]:\\?$') } |
    Sort-Object
)

$targets = New-Object System.Collections.Generic.List[string]
$beforeStats = @{
    total = 0
    ok = 0
    missing = 0
    invalid = 0
}

foreach ($albumPath in $albums) {
    $beforeStats.total++
    $state = Get-AlbumState -AlbumPath $albumPath
    switch ($state) {
        "ok" { $beforeStats.ok++ }
        "missing-cover" { $beforeStats.missing++; $targets.Add($albumPath) | Out-Null }
        "invalid-cover" { $beforeStats.invalid++; $targets.Add($albumPath) | Out-Null }
    }
}

$reportRows = New-Object System.Collections.Generic.List[object]
$processed = 0
$downloaded = 0
$downloadedCache = 0
$alreadyOk = 0
$notFound = 0
$notFoundCache = 0
$failed = 0

foreach ($albumPath in $targets) {
    $processed++
    $meta = Get-SearchMetadataFromPath -AlbumPath $albumPath
    $albumCanonical = [string]$meta.Album
    $artistGuess = [string]$meta.Artist
    $result = Find-And-SaveCoverForAlbum -AlbumPath $albumPath

    switch ($result) {
        "downloaded" { $downloaded++ }
        "downloaded-cache" { $downloadedCache++ }
        "already-ok" { $alreadyOk++ }
        "not-found" { $notFound++ }
        "not-found-cache" { $notFoundCache++ }
        default { $failed++ }
    }

    $reportRows.Add([pscustomobject]@{
        Timestamp = (Get-Date).ToString("s")
        AlbumPath = $albumPath
        Artist = $artistGuess
        Album = $albumCanonical
        Result = $result
    }) | Out-Null

    if (($processed % $BatchLimit) -eq 0 -or $processed -eq $targets.Count) {
        Save-CoverCache
        if ($processed -lt $targets.Count -and $PauseBetweenBatchesMs -gt 0) {
            Start-Sleep -Milliseconds $PauseBetweenBatchesMs
        }
    }
}

$afterStats = @{
    total = 0
    ok = 0
    missing = 0
    invalid = 0
}
foreach ($albumPath in $albums) {
    $afterStats.total++
    $state = Get-AlbumState -AlbumPath $albumPath
    switch ($state) {
        "ok" { $afterStats.ok++ }
        "missing-cover" { $afterStats.missing++ }
        "invalid-cover" { $afterStats.invalid++ }
    }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$jsonPath = Join-Path $PSScriptRoot "$ReportPrefix.$stamp.json"
$csvPath = Join-Path $PSScriptRoot "$ReportPrefix.$stamp.csv"
$summaryPath = Join-Path $PSScriptRoot "$ReportPrefix.$stamp.summary.json"

$reportRows | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $jsonPath -Encoding UTF8 -Force
$reportRows | Export-Csv -LiteralPath $csvPath -Delimiter ';' -Encoding UTF8 -NoTypeInformation

$endedAt = Get-Date
$summary = [pscustomobject]@{
    startedAt = $script:RunStartedAt.ToString("o")
    endedAt = $endedAt.ToString("o")
    elapsedSeconds = [math]::Round(($endedAt - $script:RunStartedAt).TotalSeconds, 3)
    timestamp = (Get-Date).ToString("o")
    library = $LibraryPath
    targets = $targets.Count
    processed = $processed
    downloaded = $downloaded
    downloadedCache = $downloadedCache
    alreadyOk = $alreadyOk
    notFound = $notFound
    notFoundCache = $notFoundCache
    failed = $failed
    aggressive = [bool]$Aggressive
    itunesMinScore = $script:ItunesMinScore
    before = $beforeStats
    after = $afterStats
    reportJson = $jsonPath
    reportCsv = $csvPath
}
$summary | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $summaryPath -Encoding UTF8 -Force

Write-Output ("AutoCoverBatch fini. Cibles={0}, Downloaded={1}, DownloadedCache={2}, NotFound={3}, NotFoundCache={4}, Failed={5}" -f `
    $targets.Count, $downloaded, $downloadedCache, $notFound, $notFoundCache, $failed)
Write-Output ("Avant: OK={0} Missing={1} Invalid={2}" -f $beforeStats.ok, $beforeStats.missing, $beforeStats.invalid)
Write-Output ("Apres: OK={0} Missing={1} Invalid={2}" -f $afterStats.ok, $afterStats.missing, $afterStats.invalid)
Write-Output ("Rapports: {0} | {1} | {2}" -f $csvPath, $jsonPath, $summaryPath)
