Add-Type -AssemblyName PresentationFramework, System.Windows.Forms, System.Drawing, Microsoft.VisualBasic

$CurrentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $CurrentDir) { $CurrentDir = $PSScriptRoot }
Set-Location $CurrentDir

$LibraryPath = Join-Path $CurrentDir "Library.json"
$XamlPath = Join-Path $CurrentDir "MusicPlayerGUI.xaml"
$CoverCachePath = Join-Path $CurrentDir "CoverSearchCache.json"
$AutoCoverReportPath = Join-Path $CurrentDir "AutoCoverReport.json"
$ConfigPath = Join-Path $CurrentDir "MusicSelektor_config.json"
$AutoCoverBatchLimit = 75
$AutoCoverInterBatchPauseMs = 1200
$LogRoot = if ([string]::IsNullOrWhiteSpace($env:TEMP)) { $CurrentDir } else { $env:TEMP }
$StartupTracePath = Join-Path $LogRoot "MusicPlayer.startup.trace.log"
$StartupErrorPath = Join-Path $LogRoot "MusicPlayer.startup.error.log"
$DebugLogPath = Join-Path $CurrentDir "MusicSelektor.debug.log"
$DebugLogPreviousPath = Join-Path $CurrentDir "MusicSelektor.debug.previous.log"
$NetworkTraceLogPath = Join-Path $CurrentDir "MusicSelektor.network.trace.log"
$NetworkTracePreviousPath = Join-Path $CurrentDir "MusicSelektor.network.trace.previous.log"
$LastAutoCoverTimingPath = Join-Path $CurrentDir "LastAutoCoverTiming.json"
$Script:CoverCache = @{}
$Script:LastApiRequestAt = [datetime]::MinValue
$Script:AlbumCoverStateCache = @{}
$Script:DebugMode = $false
$Script:NetworkTraceEnabled = $false
$Script:LastAutoCoverElapsedText = ""
$Script:SignatureTextControl = $null
$Script:SupportedAudioExtensions = @(".mp3", ".wav", ".m4a", ".wma", ".aac", ".flac", ".ogg")
$Script:AudioPlayer = $null
$Script:InternalPlayerEnabled = $false
$Script:CurrentPlaylist = @()
$Script:CurrentTrackIndex = -1
$Script:CurrentAlbumPath = ""
$Script:IsAudioPlaying = $false
$Script:PlaybackMode = "external"
$Script:InternalFallbackNotified = $false
$Script:LastInternalPlaybackError = ""
$Script:MusicListSortColumn = ""
$Script:MusicListSortDirection = "Ascending"

try {
    "[$(Get-Date -Format s)] START MusicPlayer.ps1" | Out-File -LiteralPath $StartupTracePath -Encoding UTF8 -Append
} catch { }

function Write-DebugLog {
    param([string]$Message)
    if (-not $Script:DebugMode) { return }
    try {
        $humanStamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
        "$humanStamp $Message`r`n" | Out-File -LiteralPath $DebugLogPath -Encoding UTF8 -Append
    } catch { }
}

function Initialize-DebugLog {
    if (-not $Script:DebugMode) { return }
    try {
        if (Test-Path -LiteralPath $DebugLogPath) {
            try {
                Copy-Item -LiteralPath $DebugLogPath -Destination $DebugLogPreviousPath -Force -ErrorAction Stop
            } catch { }
        }
        # Force un fichier neuf a chaque session.
        Set-Content -LiteralPath $DebugLogPath -Value "" -Encoding UTF8 -Force
    } catch {
        # Fallback si le fichier principal est verrouille.
        $fallbackName = "MusicSelektor.debug." + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log"
        $script:DebugLogPath = Join-Path $CurrentDir $fallbackName
        try {
            Set-Content -LiteralPath $script:DebugLogPath -Value "" -Encoding UTF8 -Force
        } catch { }
    }
}

function Write-NetworkTrace {
    param(
        [string]$Action,
        [string]$Provider,
        [string]$Url,
        [string]$Status,
        [string]$Details
    )
    if (-not $Script:NetworkTraceEnabled) { return }
    try {
        $stamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
        "$stamp action=$Action provider=$Provider status=$Status url=`"$Url`" details=`"$Details`"" | Out-File -LiteralPath $NetworkTraceLogPath -Encoding UTF8 -Append
    } catch { }
}

function Initialize-NetworkTraceLog {
    if (-not $Script:NetworkTraceEnabled) { return }
    try {
        if (Test-Path -LiteralPath $NetworkTraceLogPath) {
            try {
                Copy-Item -LiteralPath $NetworkTraceLogPath -Destination $NetworkTracePreviousPath -Force -ErrorAction Stop
            } catch { }
        }
        Set-Content -LiteralPath $NetworkTraceLogPath -Value "" -Encoding UTF8 -Force
    } catch { }
}

function Format-ElapsedText {
    param([double]$Seconds)
    if ($Seconds -lt 1) {
        return ("{0} ms" -f [int][math]::Round($Seconds * 1000.0))
    }
    if ($Seconds -lt 60) {
        return ("{0} s" -f [math]::Round($Seconds, 1))
    }
    $totalSeconds = [int][math]::Round($Seconds)
    $mins = [int][math]::Floor($totalSeconds / 60)
    $secs = $totalSeconds % 60
    return ("{0} min {1}s" -f $mins, $secs)
}

function Save-LastAutoCoverTiming {
    param(
        [double]$ElapsedSeconds,
        [string]$ElapsedText
    )
    try {
        $payload = [ordered]@{
            timestamp = (Get-Date).ToString("o")
            elapsedSeconds = [math]::Round($ElapsedSeconds, 3)
            elapsedText = [string]$ElapsedText
        }
        $payload | ConvertTo-Json -Depth 4 | Out-File -LiteralPath $LastAutoCoverTimingPath -Encoding UTF8 -Force
    } catch { }
}

function Get-LatestAutoCoverElapsedText {
    try {
        if (Test-Path -LiteralPath $LastAutoCoverTimingPath) {
            $rawTiming = Get-Content -LiteralPath $LastAutoCoverTimingPath -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($rawTiming)) {
                $timing = ConvertFrom-Json -InputObject $rawTiming
                if ($timing -and $timing.PSObject.Properties["elapsedText"] -and -not [string]::IsNullOrWhiteSpace([string]$timing.elapsedText)) {
                    return [string]$timing.elapsedText
                }
                if ($timing -and $timing.PSObject.Properties["elapsedSeconds"] -and $null -ne $timing.elapsedSeconds) {
                    return (Format-ElapsedText -Seconds ([double]$timing.elapsedSeconds))
                }
            }
        }
    } catch { }

    try {
        $autoCoverDir = Join-Path $CurrentDir "reports\\auto-cover"
        if (-not (Test-Path -LiteralPath $autoCoverDir)) { return "" }
        $latestSummary = Get-ChildItem -LiteralPath $autoCoverDir -File -Filter "AutoCoverBatch.report.*.summary.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $latestSummary) { return "" }

        $raw = Get-Content -LiteralPath $latestSummary.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return "" }
        $summary = ConvertFrom-Json -InputObject $raw
        if (-not $summary) { return "" }

        if ($summary.PSObject.Properties["elapsedSeconds"] -and $null -ne $summary.elapsedSeconds) {
            return (Format-ElapsedText -Seconds ([double]$summary.elapsedSeconds))
        }

        if ($summary.PSObject.Properties["startedAt"] -and $summary.PSObject.Properties["endedAt"] -and $summary.startedAt -and $summary.endedAt) {
            $startedAt = [datetime]::Parse([string]$summary.startedAt)
            $endedAt = [datetime]::Parse([string]$summary.endedAt)
            $seconds = ($endedAt - $startedAt).TotalSeconds
            if ($seconds -gt 0) {
                return (Format-ElapsedText -Seconds ([double]$seconds))
            }
        }
    } catch { }

    try {
        if (Test-Path -LiteralPath $NetworkTraceLogPath) {
            $lines = Get-Content -LiteralPath $NetworkTraceLogPath -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($lines -and $lines.Count -gt 0) {
                $startIndex = -1
                for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                    if ($lines[$i] -match 'action=session-start provider=AutoCoverBatch') {
                        $startIndex = $i
                        break
                    }
                }
                if ($startIndex -ge 0) {
                    $firstTs = $null
                    $lastTs = $null
                    for ($j = $startIndex; $j -lt $lines.Count; $j++) {
                        $line = $lines[$j]
                        if ($line -match '^(?<d>\d{2}-\d{2}-\d{4})\s+(?<t>\d{2}:\d{2}:\d{2})') {
                            $stampText = "$($matches.d) $($matches.t)"
                            $stamp = [datetime]::ParseExact($stampText, "dd-MM-yyyy HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                            if ($null -eq $firstTs) { $firstTs = $stamp }
                            $lastTs = $stamp
                        }
                    }
                    if ($firstTs -and $lastTs -and $lastTs -ge $firstTs) {
                        $seconds = ($lastTs - $firstTs).TotalSeconds
                        if ($seconds -gt 0) {
                            return (Format-ElapsedText -Seconds $seconds)
                        }
                    }
                }
            }
        }
    } catch { }
    return ""
}

function Update-SignatureText {
    if (-not $Script:SignatureTextControl) { return }
    $Script:SignatureTextControl.Text = "by Joe Kurwa"
}

function Update-PlayButtonState {
    if (-not $OpenFolderBtn) { return }
    $OpenFolderBtn.Content = "LECTURE/PAUSE"
    if ($Script:InternalPlayerEnabled) {
        $OpenFolderBtn.ToolTip = "Lecture/Pause (interne si compatible, fallback externe sinon)"
    } else {
        $OpenFolderBtn.ToolTip = "Lancer la lecture de la piste courante"
    }
}

function Set-PlaybackInfo {
    param([string]$Prefix, [string]$TrackTitle)
    if (-not $CurrentTrackInfo) { return }
    $albumLabel = ""
    if ($FolderTreeView -and $FolderTreeView.SelectedItem -and $FolderTreeView.SelectedItem.Header) {
        $albumLabel = [string]$FolderTreeView.SelectedItem.Header
    }
    if ([string]::IsNullOrWhiteSpace($albumLabel)) { $albumLabel = "Album" }
    if ([string]::IsNullOrWhiteSpace($TrackTitle)) {
        $CurrentTrackInfo.Text = "$albumLabel`n$Prefix"
    } else {
        $CurrentTrackInfo.Text = "$albumLabel`n$Prefix : $TrackTitle"
    }
}

function Set-NowPlayingCoverFromTrackPath {
    param([string]$TrackPath)
    if (-not $AlbumArtImage) { return }
    if ([string]::IsNullOrWhiteSpace($TrackPath) -or -not (Test-Path -LiteralPath $TrackPath)) {
        $AlbumArtImage.Source = $null
        return
    }
    try {
        $albumPath = Split-Path -Path $TrackPath -Parent
        if ([string]::IsNullOrWhiteSpace($albumPath) -or -not (Test-Path -LiteralPath $albumPath)) {
            $AlbumArtImage.Source = $null
            return
        }
        $coverState = Get-AlbumCoverState -AlbumPath $albumPath
        if ($coverState.HasDisplayable -and $coverState.CoverFile) {
            $AlbumArtImage.Source = $null
            $imageBytes = [System.IO.File]::ReadAllBytes($coverState.CoverFile.FullName)
            $stream = New-Object System.IO.MemoryStream(, $imageBytes)
            try {
                $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                $bitmap.BeginInit()
                $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bitmap.StreamSource = $stream
                $bitmap.EndInit()
                $bitmap.Freeze()
                $AlbumArtImage.Source = $bitmap
            } finally {
                $stream.Close()
                $stream.Dispose()
            }
        } else {
            $AlbumArtImage.Source = $null
        }
    } catch {
        Write-DebugLog "NowPlaying cover refresh exception: $($_.Exception.Message)"
        $AlbumArtImage.Source = $null
    }
}

function Set-MusicListSort {
    if (-not $MusicListView -or -not $MusicListView.ItemsSource) { return }
    if ([string]::IsNullOrWhiteSpace($Script:MusicListSortColumn)) { return }
    try {
        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($MusicListView.ItemsSource)
        if (-not $view) { return }
        $dir = if ($Script:MusicListSortDirection -eq "Descending") {
            [System.ComponentModel.ListSortDirection]::Descending
        } else {
            [System.ComponentModel.ListSortDirection]::Ascending
        }
        $view.SortDescriptions.Clear()
        $null = $view.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription($Script:MusicListSortColumn, $dir)))
        $view.Refresh()
    } catch {
        Write-DebugLog "Set-MusicListSort exception: $($_.Exception.Message)"
    }
}

function Get-PlayableTracksForAlbum {
    param([string]$AlbumPath)
    $tracks = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($AlbumPath)) { return @() }

    $albumNorm = $AlbumPath.TrimEnd('\')
    $isExactAlbum = $global:AlbumsIndex -and ($global:AlbumsIndex -contains $AlbumPath)

    if ($global:RawData) {
        $rows = @($global:RawData | Where-Object {
            if ([string]::IsNullOrWhiteSpace($_.Path)) { return $false }
            $dir = [string]$_.FullDir
            if ([string]::IsNullOrWhiteSpace($dir)) { return $false }
            if ($isExactAlbum) { return ($dir -eq $AlbumPath) }
            $dirNorm = $dir.TrimEnd('\')
            return ($dirNorm -eq $albumNorm -or $dirNorm.StartsWith($albumNorm + '\'))
        })
        foreach ($row in $rows) {
            $trackPath = [string]$row.Path
            if (-not (Test-Path -LiteralPath $trackPath)) { continue }
            $ext = [System.IO.Path]::GetExtension($trackPath).ToLowerInvariant()
            if ($Script:SupportedAudioExtensions -notcontains $ext) { continue }
            $title = [string]$row.Title
            if ([string]::IsNullOrWhiteSpace($title)) { $title = [System.IO.Path]::GetFileNameWithoutExtension($trackPath) }
            $tracks.Add([pscustomobject]@{ Path = $trackPath; Title = $title }) | Out-Null
        }
    }

    if ($tracks.Count -eq 0 -and (Test-Path -LiteralPath $AlbumPath)) {
        try {
            $files = Get-ChildItem -LiteralPath $AlbumPath -File -Recurse:(!$isExactAlbum) -ErrorAction SilentlyContinue |
                Where-Object { $Script:SupportedAudioExtensions -contains $_.Extension.ToLowerInvariant() } |
                Sort-Object FullName
            foreach ($f in $files) {
                $tracks.Add([pscustomobject]@{ Path = $f.FullName; Title = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }) | Out-Null
            }
        } catch { }
    }

    return @($tracks.ToArray())
}

function Remove-TrackFiles {
    param(
        [string[]]$TrackPaths,
        [string]$SelectedFolderPath
    )
    if (-not $TrackPaths -or $TrackPaths.Count -eq 0) { return }

    $unique = @($TrackPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($unique.Count -eq 0) { return }

    $msg = if ($unique.Count -eq 1) {
        "Supprimer cette piste ?`n`n$($unique[0])`n`n(Envoi vers la Corbeille)"
    } else {
        "Supprimer $($unique.Count) piste(s) selectionnee(s) ?`n`n(Envoi vers la Corbeille)"
    }
    $confirm = [System.Windows.MessageBox]::Show($msg, "Confirmation suppression", "YesNo", "Warning")
    if ($confirm -ne "Yes") { return }

    $deleted = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[string]
    foreach ($p in $unique) {
        try {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $p,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
            $deleted.Add($p) | Out-Null
            Write-DebugLog "Track deleted to recycle bin: $p"
        } catch {
            $failed.Add($p) | Out-Null
            Write-DebugLog "Track delete failed: $p | $($_.Exception.Message)"
        }
    }

    if ($deleted.Count -gt 0 -and $global:RawData) {
        $deletedSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($d in $deleted) { [void]$deletedSet.Add($d) }

        $global:RawData = @($global:RawData | Where-Object {
            $rp = [string]$_.Path
            -not $deletedSet.Contains($rp)
        })
        $global:AlbumsIndex = @(
            $global:RawData |
            Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace($_.FullDir) } |
            Select-Object -ExpandProperty FullDir -Unique |
            Sort-Object
        )
        try {
            $global:RawData | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $LibraryPath -Encoding UTF8 -Force
        } catch {
            Write-DebugLog "Library save after delete failed: $($_.Exception.Message)"
        }
        Update-WorkList
        if (-not [string]::IsNullOrWhiteSpace($SelectedFolderPath)) {
            Select-AlbumNodeByPath -SelectedPath $SelectedFolderPath
        }
    }

    if ($failed.Count -gt 0) {
        [System.Windows.MessageBox]::Show("Suppression terminee.`nSupprimees: $($deleted.Count)`nEchecs: $($failed.Count)", "Suppression pistes", "OK", "Warning")
    } else {
        [System.Windows.MessageBox]::Show("Suppression terminee.`nSupprimees: $($deleted.Count)", "Suppression pistes", "OK", "Information")
    }
}

function Stop-AlbumPlayback {
    param([bool]$ResetPlaylist = $false)
    try {
        if ($Script:PlaybackMode -eq "internal" -and $Script:AudioPlayer) {
            $Script:AudioPlayer.Stop()
        }
    } catch { }
    $Script:IsAudioPlaying = $false
    if ($ResetPlaylist) {
        $Script:CurrentPlaylist = @()
        $Script:CurrentTrackIndex = -1
        $Script:CurrentAlbumPath = ""
    }
    Update-PlayButtonState
}

function Start-PlaybackAtIndex {
    param([int]$Index)
    if (-not $Script:CurrentPlaylist -or $Script:CurrentPlaylist.Count -eq 0) { return $false }
    if ($Index -lt 0 -or $Index -ge $Script:CurrentPlaylist.Count) { return $false }
    $track = $Script:CurrentPlaylist[$Index]
    if (-not $track -or [string]::IsNullOrWhiteSpace([string]$track.Path)) { return $false }
    if (-not (Test-Path -LiteralPath $track.Path)) { return $false }

    $absolutePath = $null
    try {
        $absolutePath = (Get-Item -LiteralPath $track.Path -ErrorAction Stop).FullName
    } catch {
        Write-DebugLog ("Playback path resolve error: {0}" -f $_.Exception.Message)
        return $false
    }

    if ($Script:InternalPlayerEnabled -and $Script:AudioPlayer) {
        try {
            $uri = [System.Uri]::new($absolutePath)
            $Script:AudioPlayer.Open($uri)
            $Script:AudioPlayer.Play()
            $Script:PlaybackMode = "internal"
            $Script:LastInternalPlaybackError = ""
            $Script:CurrentTrackIndex = $Index
            $Script:IsAudioPlaying = $true
            Set-PlaybackInfo -Prefix "Lecture (interne)" -TrackTitle ([string]$track.Title)
            Set-NowPlayingCoverFromTrackPath -TrackPath ([string]$track.Path)
            Update-PlayButtonState
            Write-DebugLog ("Playback start (internal): index={0} path={1}" -f $Index, $track.Path)
            return $true
        } catch {
            $Script:LastInternalPlaybackError = [string]$_.Exception.Message
            Write-DebugLog ("Playback start error (internal): {0}" -f $Script:LastInternalPlaybackError)
            if (-not $Script:InternalFallbackNotified) {
                $Script:InternalFallbackNotified = $true
                [System.Windows.MessageBox]::Show(
                    "Le lecteur interne n'a pas pu demarrer (fallback externe actif).`n`nDetail: $($Script:LastInternalPlaybackError)",
                    "Lecture",
                    "OK",
                    "Information"
                )
            }
        }
    }

    try {
        Start-Process -FilePath $absolutePath
        $Script:PlaybackMode = "external"
        $Script:CurrentTrackIndex = $Index
        $Script:IsAudioPlaying = $true
        Set-PlaybackInfo -Prefix "Lecture (externe)" -TrackTitle ([string]$track.Title)
        Set-NowPlayingCoverFromTrackPath -TrackPath ([string]$track.Path)
        Update-PlayButtonState
        Write-DebugLog ("Playback start (external): index={0} path={1}" -f $Index, $track.Path)
        return $true
    } catch {
        Write-DebugLog ("Playback start error (external): {0}" -f $_.Exception.Message)
        return $false
    }
}

function Skip-PlaybackTrack {
    param([int]$Delta)
    if (-not $Script:CurrentPlaylist -or $Script:CurrentPlaylist.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Aucune playlist active. Lance d'abord la lecture d'un album.", "Lecture", "OK", "Information")
        return
    }
    $baseIndex = $Script:CurrentTrackIndex
    if ($baseIndex -lt 0) { $baseIndex = 0 }
    $nextIndex = $baseIndex + $Delta
    if ($nextIndex -lt 0) { $nextIndex = 0 }
    if ($nextIndex -ge $Script:CurrentPlaylist.Count) { $nextIndex = $Script:CurrentPlaylist.Count - 1 }
    [void](Start-PlaybackAtIndex -Index $nextIndex)
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

function Get-JsonArraySafe {
    param([string]$RawJson)
    if ([string]::IsNullOrWhiteSpace($RawJson)) { return @() }
    $parsed = ConvertFrom-Json -InputObject $RawJson
    if ($null -eq $parsed) { return @() }
    if ($parsed -is [System.Array]) { return $parsed }
    return @($parsed)
}

try {
    if (Test-Path -LiteralPath $ConfigPath) {
        $cfgRaw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($cfgRaw)) {
            $cfg = ConvertFrom-Json -InputObject $cfgRaw
            if ($cfg -and $cfg.PSObject.Properties["DebugMode"]) {
                $Script:DebugMode = [bool]$cfg.DebugMode
            }
            if ($cfg -and $cfg.PSObject.Properties["NetworkTraceEnabled"]) {
                $Script:NetworkTraceEnabled = [bool]$cfg.NetworkTraceEnabled
            }
            if ($cfg -and $cfg.PSObject.Properties["InternalPlayerEnabled"]) {
                $Script:InternalPlayerEnabled = [bool]$cfg.InternalPlayerEnabled
            }
        }
    }
} catch { }
Initialize-DebugLog
Initialize-NetworkTraceLog
if ($Script:InternalPlayerEnabled) {
    try {
        $Script:AudioPlayer = New-Object System.Windows.Media.MediaPlayer
        Write-DebugLog "InternalPlayerEnabled=True (WPF MediaPlayer active)"
    } catch {
        $Script:InternalPlayerEnabled = $false
        $Script:AudioPlayer = $null
        Write-DebugLog ("Internal player init failed, fallback external only: {0}" -f $_.Exception.Message)
    }
} else {
    Write-DebugLog "InternalPlayerEnabled=False (external player mode)"
}
Write-DebugLog "DebugMode=$Script:DebugMode"
Write-DebugLog "LogPath=$DebugLogPath"
Write-NetworkTrace -Action "session-start" -Provider "MusicPlayer" -Url "" -Status "ok" -Details ("NetworkTraceEnabled={0}; LogPath={1}" -f $Script:NetworkTraceEnabled, $NetworkTraceLogPath)

function Update-LibraryData {
    Write-DebugLog "Update-LibraryData start"
    try {
        if (Test-Path -LiteralPath $LibraryPath) {
            $jsonRaw = Get-Content -LiteralPath $LibraryPath -Raw -Encoding UTF8
            $global:RawData = Get-JsonArraySafe -RawJson $jsonRaw
            $global:AlbumsIndex = @(
                $global:RawData |
                Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace($_.FullDir) } |
                Select-Object -ExpandProperty FullDir -Unique |
                Sort-Object
            )
            $global:ScanRoot = $null
            if ($global:RawData -and $global:RawData.Count -gt 0 -and $global:RawData[0].ScanRoot) {
                $global:ScanRoot = [string]$global:RawData[0].ScanRoot
                if ($global:ScanRoot -notmatch '\\$') { $global:ScanRoot = $global:ScanRoot.TrimEnd('\') }
            }
            Write-DebugLog "Library loaded: entries=$($global:RawData.Count) albums=$($global:AlbumsIndex.Count)"
        } else {
            $global:RawData = $null
            $global:AlbumsIndex = @()
            $global:ScanRoot = $null
            Write-DebugLog "Library missing: $LibraryPath"
        }
    } catch {
        $global:RawData = $null
        $global:AlbumsIndex = @()
        $global:ScanRoot = $null
        Write-DebugLog "Update-LibraryData exception: $($_.Exception.Message)"
    }
    # Invalide le cache local quand la bibliotheque est rechargee
    $Script:AlbumCoverStateCache = @{}
    Write-DebugLog "Update-LibraryData end"
}

try {
    Write-DebugLog "UI load start"
    if (-not (Test-Path -LiteralPath $XamlPath)) {
        [System.Windows.MessageBox]::Show("Erreur: MusicPlayerGUI.xaml introuvable.`nChemin: $XamlPath", "Erreur fichier", "OK", "Error")
        exit 1
    }

    $inputString = Get-Content -LiteralPath $XamlPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($inputString)) {
        [System.Windows.MessageBox]::Show("Erreur: MusicPlayerGUI.xaml est vide.", "Erreur fichier", "OK", "Error")
        exit 1
    }

    $Window = [Windows.Markup.XamlReader]::Load([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($inputString)))
    if ($null -eq $Window) {
        [System.Windows.MessageBox]::Show("Erreur: impossible de charger l'interface XAML.", "Erreur XAML", "OK", "Error")
        exit 1
    }

    Update-LibraryData
    Write-DebugLog "UI load success"
} catch {
    try { "[$(Get-Date -Format s)] CRITICAL_INIT: $($_.Exception.Message)" | Out-File -LiteralPath $StartupErrorPath -Encoding UTF8 -Append } catch { }
    [System.Windows.MessageBox]::Show("Erreur critique: $($_.Exception.Message)", "Erreur", "OK", "Error")
    exit 1
}

$FolderTreeView = $Window.FindName("FolderTreeView")
$MusicListView = $Window.FindName("MusicListView")
$AlbumArtImage = $Window.FindName("AlbumArtImage")
$AlbumCounter = $Window.FindName("AlbumCounter")
$CurrentTrackInfo = $Window.FindName("CurrentTrackInfo")
$OpenFolderBtn = $Window.FindName("OpenFolderBtn")
$PrevTrackBtn = $Window.FindName("PrevTrackBtn")
$NextTrackBtn = $Window.FindName("NextTrackBtn")
$AutoCoverBtn = $Window.FindName("AutoCoverBtn")
$SearchOnlineBtn = $Window.FindName("SearchOnlineBtn")
$ApplyCoverClipboardBtn = $Window.FindName("ApplyCoverClipboardBtn")
$FindDuplicatesBtn = $Window.FindName("FindDuplicatesBtn")
$RefreshLibraryBtn = $Window.FindName("RefreshLibraryBtn")
$AlbumFilterBox = $Window.FindName("AlbumFilterBox")
$ClearFilterBtn = $Window.FindName("ClearFilterBtn")
$ShowAllAlbumsToggle = $Window.FindName("ShowAllAlbumsToggle")
$AlbumsPanelTitle = $Window.FindName("AlbumsPanelTitle")
$Script:SignatureTextControl = $Window.FindName("SignatureText")

if ([string]::IsNullOrWhiteSpace($Script:LastAutoCoverElapsedText)) {
    $Script:LastAutoCoverElapsedText = Get-LatestAutoCoverElapsedText
}
Update-SignatureText
Update-PlayButtonState

if ($null -eq $FolderTreeView) {
    [System.Windows.MessageBox]::Show("Erreur: FolderTreeView introuvable.", "Erreur interface", "OK", "Error")
    exit 1
}

if ($Script:AudioPlayer) {
    try {
        $Script:AudioPlayer.add_MediaEnded({
            try {
                if ($Script:PlaybackMode -ne "internal") { return }
                $nextIndex = $Script:CurrentTrackIndex + 1
                if ($Script:CurrentPlaylist -and $nextIndex -lt $Script:CurrentPlaylist.Count) {
                    [void](Start-PlaybackAtIndex -Index $nextIndex)
                } else {
                    $Script:IsAudioPlaying = $false
                    Update-PlayButtonState
                    Set-PlaybackInfo -Prefix "Lecture terminee" -TrackTitle ""
                }
            } catch { }
        })
        $Script:AudioPlayer.add_MediaFailed({
            param($mediaSender, $e)
            try {
                if ($Script:PlaybackMode -ne "internal") { return }
                $err = if ($e -and $e.ErrorException) { $e.ErrorException.Message } else { "Erreur media inconnue" }
                Write-DebugLog ("Playback failed (internal): {0}" -f $err)
                $Script:PlaybackMode = "external"
                $Script:IsAudioPlaying = $false
                if ($Script:CurrentTrackIndex -ge 0) {
                    [void](Start-PlaybackAtIndex -Index $Script:CurrentTrackIndex)
                }
            } catch { }
        })
    } catch { }
}

if ($MusicListView) {
    $MusicListView.Focusable = $true
    $MusicListView.AddHandler(
        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        [System.Windows.RoutedEventHandler]{
            param($src, $e)
            try {
                $header = $e.OriginalSource -as [System.Windows.Controls.GridViewColumnHeader]
                if (-not $header -or -not $header.Column) { return }
                $binding = $header.Column.DisplayMemberBinding
                if (-not $binding -or -not $binding.Path -or [string]::IsNullOrWhiteSpace($binding.Path.Path)) { return }
                $sortBy = [string]$binding.Path.Path

                if ($Script:MusicListSortColumn -eq $sortBy) {
                    if ($Script:MusicListSortDirection -eq "Ascending") {
                        $Script:MusicListSortDirection = "Descending"
                    } else {
                        $Script:MusicListSortDirection = "Ascending"
                    }
                } else {
                    $Script:MusicListSortColumn = $sortBy
                    $Script:MusicListSortDirection = "Ascending"
                }
                Set-MusicListSort
                Write-DebugLog ("MusicList sort: {0} {1}" -f $Script:MusicListSortColumn, $Script:MusicListSortDirection)
            } catch {
                Write-DebugLog "MusicList header sort exception: $($_.Exception.Message)"
            }
        }
    )

    $trackMenu = New-Object System.Windows.Controls.ContextMenu
    $deleteTrackMenuItem = New-Object System.Windows.Controls.MenuItem
    $deleteTrackMenuItem.Header = "Supprimer la/les piste(s) selectionnee(s)"
    $deleteTrackMenuItem.Add_Click({
        try {
            $selectedPath = ""
            if ($FolderTreeView -and $FolderTreeView.SelectedItem) { $selectedPath = [string]$FolderTreeView.SelectedItem.Tag }
            $selectedRows = @()
            if ($MusicListView.SelectedItems -and $MusicListView.SelectedItems.Count -gt 0) {
                $selectedRows = @($MusicListView.SelectedItems)
            } elseif ($MusicListView.SelectedItem) {
                $selectedRows = @($MusicListView.SelectedItem)
            }
            $trackPaths = @(
                $selectedRows |
                ForEach-Object { [string]$_.TrackPath } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
            )
            if ($trackPaths.Count -eq 0) {
                [System.Windows.MessageBox]::Show("Selectionnez d'abord une ou plusieurs pistes dans la liste du milieu.", "Suppression pistes", "OK", "Information")
                return
            }
            Remove-TrackFiles -TrackPaths $trackPaths -SelectedFolderPath $selectedPath
        } catch {
            Write-DebugLog "Track context delete exception: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show("Erreur lors de la suppression :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
        }
    })
    $null = $trackMenu.Items.Add($deleteTrackMenuItem)
    $MusicListView.ContextMenu = $trackMenu
}

$Script:CoverNames = @(
    "cover.jpg", "cover.png", "cover.jpeg",
    "folder.jpg", "folder.png", "folder.jpeg",
    "album.jpg", "album.png", "album.jpeg",
    "artwork.jpg", "artwork.png", "artwork.jpeg",
    "front.jpg", "front.png", "front.jpeg",
    "Front.jpg", "Front.png", "Front.jpeg"
)

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

function Get-AlbumCoverFile {
    param([string]$AlbumPath)
    if (-not (Test-Path -LiteralPath $AlbumPath)) { return $null }

    $AlbumName = Split-Path $AlbumPath -Leaf
    $PriorityNames = @(
        "cover.jpg", "cover.png", "cover.jpeg",
        "folder.jpg", "folder.png", "folder.jpeg",
        "album.jpg", "album.png", "album.jpeg",
        "artwork.jpg", "artwork.png", "artwork.jpeg",
        "front.jpg", "front.png", "front.jpeg",
        "Front.jpg", "Front.png", "Front.jpeg",
        "$AlbumName.jpg", "$AlbumName.png", "$AlbumName.jpeg"
    )

    $searchDirs = Get-CoverSearchDirectories -AlbumPath $AlbumPath
    Write-DebugLog ("CoverSearch dirs for '{0}': {1}" -f $AlbumPath, ($searchDirs -join " | "))

    foreach ($dir in $searchDirs) {
        foreach ($name in $PriorityNames) {
            $candidate = Join-Path $dir $name
            if (Test-Path -LiteralPath $candidate) {
                try {
                    Write-DebugLog "Cover found: $candidate"
                    return Get-Item -LiteralPath $candidate -ErrorAction Stop
                } catch {
                    continue
                }
            }
        }
    }

    # Fallback tolerant: certains dumps corrompus stockent une image de cover
    # dans un sous-dossier technique (hash, export, etc.) avec un nom non standard.
    foreach ($dir in $searchDirs) {
        try {
            $images = @(
                Get-ChildItem -LiteralPath $dir -File -Recurse -Depth 1 -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '^(?i)\.(jpg|jpeg|png)$' }
            )
            if ($images.Count -gt 0) {
                $best = $images | Sort-Object Length -Descending | Select-Object -First 1
                if ($best) {
                    Write-DebugLog "Cover fallback found: $($best.FullName)"
                    return $best
                }
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

            # Validation legere des signatures, pour eviter de charger l'image complete
            if ($ext -eq ".png") {
                return (
                    $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and
                    $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47
                )
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

function Get-AlbumCoverState {
    param([string]$AlbumPath)

    if ([string]::IsNullOrWhiteSpace($AlbumPath)) {
        return [pscustomobject]@{
            CoverFile = $null
            HasCover = $false
            HasDisplayable = $false
        }
    }

    if ($Script:AlbumCoverStateCache.ContainsKey($AlbumPath)) {
        return $Script:AlbumCoverStateCache[$AlbumPath]
    }

    $coverFile = Get-AlbumCoverFile -AlbumPath $AlbumPath
    $hasCover = $false
    $hasDisplayable = $false
    if ($coverFile) {
        $hasCover = $true
        $hasDisplayable = Test-CoverDisplayable -CoverPath $coverFile.FullName
    }

    $state = [pscustomobject]@{
        CoverFile = $coverFile
        HasCover = $hasCover
        HasDisplayable = $hasDisplayable
    }
    $Script:AlbumCoverStateCache[$AlbumPath] = $state
    return $state
}

function Clear-AlbumCoverStateCacheForPath {
    param([string]$AlbumPath)
    try {
        if (-not [string]::IsNullOrWhiteSpace($AlbumPath) -and $Script:AlbumCoverStateCache.ContainsKey($AlbumPath)) {
            [void]$Script:AlbumCoverStateCache.Remove($AlbumPath)
            Write-DebugLog "Cover cache invalidated: $AlbumPath"
        }
    } catch { }
}

function Test-AlbumHasAnyCoverFile {
    param([string]$AlbumPath)
    $cover = Get-AlbumCoverFile -AlbumPath $AlbumPath
    return ($null -ne $cover)
}

function Wait-ApiThrottle {
    $minDelayMs = 250
    $elapsed = (Get-Date) - $Script:LastApiRequestAt
    if ($elapsed.TotalMilliseconds -lt $minDelayMs) {
        Start-Sleep -Milliseconds ([int]($minDelayMs - $elapsed.TotalMilliseconds))
    }
    $Script:LastApiRequestAt = Get-Date
}

function Import-CoverCache {
    $Script:CoverCache = @{}
    if (-not (Test-Path -LiteralPath $CoverCachePath)) { return }
    try {
        $raw = Get-Content -LiteralPath $CoverCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($raw) {
            foreach ($p in $raw.PSObject.Properties) {
                $Script:CoverCache[$p.Name] = $p.Value
            }
        }
    } catch {
        $Script:CoverCache = @{}
    }
}

function Save-CoverCache {
    try {
        $obj = [ordered]@{}
        foreach ($k in $Script:CoverCache.Keys) {
            $obj[$k] = $Script:CoverCache[$k]
        }
        $obj | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $CoverCachePath -Encoding UTF8 -Force
    } catch { }
}

function Get-CoverCacheKey {
    param(
        [string]$Artist,
        [string]$Album
    )
    $a = if ($Artist) { $Artist.Trim().ToLowerInvariant() } else { "" }
    $b = if ($Album) { $Album.Trim().ToLowerInvariant() } else { "" }
    return "$a|$b"
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

function Get-ItunesCoverUrl {
    param(
        [string]$Artist,
        [string]$Album
    )
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
        # Garde-fou qualite: evite les pochettes "hors sujet" quand le matching est trop faible.
        # Exemples de bons scores:
        # - album exact (3) + artiste partiel (1) => 4
        # - artiste exact (3) + album partiel (1) => 4
        if (-not $best -or -not $best.artworkUrl100 -or $bestScore -lt 4) {
            Write-NetworkTrace -Action "request" -Provider "iTunes" -Url $url -Status "low-score" -Details ("bestScore={0}" -f $bestScore)
            return $null
        }

        # Upgrade quality when possible
        $coverUrl = $best.artworkUrl100
        $coverUrl = $coverUrl -replace "100x100bb", "1200x1200bb"
        Write-NetworkTrace -Action "request" -Provider "iTunes" -Url $url -Status "ok" -Details ("bestScore={0}; cover={1}" -f $bestScore, $coverUrl)
        return $coverUrl
    } catch {
        Write-NetworkTrace -Action "request" -Provider "iTunes" -Url $url -Status "error" -Details $_.Exception.Message
        return $null
    }
}

function Get-MusicBrainzCoverUrl {
    param(
        [string]$Artist,
        [string]$Album
    )
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
                continue
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
    param(
        [string]$Url,
        [string]$AlbumPath
    )
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

    $albumName = Split-Path -Path $AlbumPath -Leaf
    $artistName = Get-AlbumArtistGuess -AlbumPath $AlbumPath
    if ([string]::IsNullOrWhiteSpace($albumName)) { return "no-metadata" }
    $cacheKey = Get-CoverCacheKey -Artist $artistName -Album $albumName

    if ($Script:CoverCache.ContainsKey($cacheKey)) {
        $entry = $Script:CoverCache[$cacheKey]
        if ($entry.status -eq "not-found" -and $entry.lastTry) {
            try {
                $lastTry = [datetime]::Parse($entry.lastTry)
                if (((Get-Date) - $lastTry).TotalDays -lt 14) {
                    return "not-found"
                }
            } catch { }
        }
        if ($entry.url) {
            if (Save-CoverFromUrl -Url $entry.url -AlbumPath $AlbumPath) {
                return "downloaded"
            }
        }
    }

    $coverUrl = Get-ItunesCoverUrl -Artist $artistName -Album $albumName
    if (-not $coverUrl) {
        $coverUrl = Get-MusicBrainzCoverUrl -Artist $artistName -Album $albumName
    }
    if (-not $coverUrl) {
        $Script:CoverCache[$cacheKey] = [pscustomobject]@{
            status = "not-found"
            url = ""
            lastTry = (Get-Date).ToString("o")
        }
        return "not-found"
    }

    if (Save-CoverFromUrl -Url $coverUrl -AlbumPath $AlbumPath) {
        $Script:CoverCache[$cacheKey] = [pscustomobject]@{
            status = "downloaded"
            url = $coverUrl
            lastTry = (Get-Date).ToString("o")
        }
        return "downloaded"
    }
    $Script:CoverCache[$cacheKey] = [pscustomobject]@{
        status = "download-failed"
        url = $coverUrl
        lastTry = (Get-Date).ToString("o")
    }
    return "download-failed"
}

# Le cache est charge ici, une fois la fonction definie
Import-CoverCache

function Get-FirstLevelFoldersUnderRoot {
    param([string]$RootPath, [string[]]$AlbumPaths)
    $rootNorm = $RootPath.TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($rootNorm)) { return @() }
    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in $AlbumPaths) {
        $pn = $p.TrimEnd('\')
        if ($pn.StartsWith($rootNorm + '\')) {
            $rel = $pn.Substring($rootNorm.Length + 1)
            $firstSeg = $rel.Split('\')[0]
            if (-not [string]::IsNullOrWhiteSpace($firstSeg)) {
                $firstPath = Join-Path $rootNorm $firstSeg
                [void]$seen.Add($firstPath)
            }
        }
    }
    @($seen) | Sort-Object
}

function Get-AlbumsUnderFolder {
    param([string]$FolderPath, [string[]]$AlbumPaths)
    $folderNorm = $FolderPath.TrimEnd('\')
    @($AlbumPaths | Where-Object {
        $a = $_.TrimEnd('\')
        $a -eq $folderNorm -or $a.StartsWith($folderNorm + '\')
    })
}

function Update-WorkList {
    if ($null -eq $FolderTreeView) { return }

    $FolderTreeView.Items.Clear()
    if ($MusicListView) { $MusicListView.ItemsSource = $null }
    if ($AlbumArtImage) { $AlbumArtImage.Source = $null }
    if ($CurrentTrackInfo) { $CurrentTrackInfo.Text = "" }

    if (-not $global:RawData) {
        if ($AlbumCounter) { $AlbumCounter.Text = "Aucun album - Lancez le scan d'abord" }
        if ($AlbumsPanelTitle) { $AlbumsPanelTitle.Text = "ALBUMS A CORRIGER" }
        return
    }

    $albums = if ($global:AlbumsIndex) { @($global:AlbumsIndex) } else { @() }
    $visibleCount = 0
    $visibleTrackCount = 0
    $missingCoverCount = 0
    $invalidCoverCount = 0
    $filteredCoveredCount = 0
    $pathMissingCount = 0
    $rootSkippedCount = 0
    $displayableSkippedCount = 0
    $filterSkippedCount = 0
    $exceptionCount = 0
    $filterText = ""
    if ($AlbumFilterBox -and $AlbumFilterBox.Text) {
        $filterText = $AlbumFilterBox.Text.Trim().ToLowerInvariant()
    }
    $onlyToFixMode = $true
    if ($ShowAllAlbumsToggle) {
        if ($null -eq $ShowAllAlbumsToggle.IsChecked) { $ShowAllAlbumsToggle.IsChecked = $false }
        $onlyToFixMode = ($ShowAllAlbumsToggle.IsChecked -eq $true)
    }

    $tracksPerAlbum = @{}
    if ($global:RawData) {
        foreach ($row in $global:RawData) {
            if (-not $row) { continue }
            $dir = [string]$row.FullDir
            if ([string]::IsNullOrWhiteSpace($dir)) { continue }
            $path = [string]$row.Path
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
            if ($Script:SupportedAudioExtensions -notcontains $ext) { continue }
            if (-not $tracksPerAlbum.ContainsKey($dir)) { $tracksPerAlbum[$dir] = 0 }
            $tracksPerAlbum[$dir]++
        }
    }

    $useTree = $false
    if ($global:ScanRoot -and (Test-Path -LiteralPath $global:ScanRoot)) {
        $effectiveRootPath = $global:ScanRoot
        $scanRootNorm = $effectiveRootPath.TrimEnd('\')
        if ($scanRootNorm -match "^[A-Za-z]:$") {
            # Si le scan est lance depuis la racine du disque (ex: E:\),
            # on derive une racine visuelle a partir du dossier de niveau 1 le plus frequent.
            # Exemple reel: E:\MUSIQUES\... devient la racine de l'arborescence.
            $firstLevelRoots = @(
                $albums |
                ForEach-Object {
                    $a = $_.TrimEnd('\')
                    if ($a -match '^[A-Za-z]:\\[^\\]+') {
                        ($a -replace '^([A-Za-z]:\\[^\\]+).*$','$1')
                    }
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
            if ($firstLevelRoots.Count -gt 0) {
                $top = $firstLevelRoots | Group-Object | Sort-Object Count -Descending | Select-Object -First 1
                if ($top -and $top.Name) {
                    $minMajority = [Math]::Max(5, [Math]::Floor($albums.Count * 0.5))
                    if ($top.Count -ge $minMajority -and (Test-Path -LiteralPath $top.Name)) {
                        $effectiveRootPath = $top.Name
                    }
                }
            }
        }
        $rootName = Split-Path $effectiveRootPath -Leaf
        if ([string]::IsNullOrWhiteSpace($rootName) -or $rootName -match "^[A-Za-z]:$") { $rootName = "MUSIQUES" }
        $firstLevelFolders = Get-FirstLevelFoldersUnderRoot -RootPath $effectiveRootPath -AlbumPaths $albums
        $firstLevelFolders = @($firstLevelFolders | Sort-Object { (Split-Path $_ -Leaf).ToLowerInvariant() })

        if ($firstLevelFolders.Count -gt 0) {
            $rootNode = New-Object System.Windows.Controls.TreeViewItem
            $rootNode.Header = $rootName
            $rootNode.Tag = $effectiveRootPath
            $rootNode.Foreground = "White"
            $rootNode.IsExpanded = $true
            foreach ($folderPath in $firstLevelFolders) {
                if (-not (Test-Path -LiteralPath $folderPath)) { $pathMissingCount++; continue }
                $folderName = Split-Path $folderPath -Leaf
                if ([string]::IsNullOrWhiteSpace($folderName) -or $folderName -match "^[A-Za-z]:\\?$") { $rootSkippedCount++; continue }
                if ($folderName.Equals($rootName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    # Evite tout doublon visuel "Parent > Parent" (ex: MUSIQUES > MUSIQUES)
                    continue
                }
                $folderNode = New-Object System.Windows.Controls.TreeViewItem
                $folderNode.Header = $folderName
                $folderNode.Tag = $folderPath
                $folderNode.Foreground = "White"
                $folderNode.IsExpanded = $false
                $albumsUnderFolder = Get-AlbumsUnderFolder -FolderPath $folderPath -AlbumPaths $albums
                $albumsUnderFolder = @($albumsUnderFolder | Sort-Object { (Split-Path $_ -Leaf).ToLowerInvariant() })
                foreach ($path in $albumsUnderFolder) {
                    try {
                        if (-not (Test-Path -LiteralPath $path)) { $pathMissingCount++; continue }
                        $albumName = Split-Path $path -Leaf
                        if ([string]::IsNullOrWhiteSpace($albumName) -or $albumName -match "^[A-Za-z]:\\?$") { continue }
                        $coverState = Get-AlbumCoverState -AlbumPath $path
                        $matchesFilter = $true
                        if ($filterText) {
                            $pathNorm = $path.ToLowerInvariant()
                            $albumNorm = $albumName.ToLowerInvariant()
                            if ($albumNorm -notlike "*$filterText*" -and $pathNorm -notlike "*$filterText*") { $filterSkippedCount++; $matchesFilter = $false }
                        }
                        if (-not $matchesFilter) { continue }
                        if ($coverState.HasDisplayable -and -not $filterText -and $onlyToFixMode) { $displayableSkippedCount++; continue }
                        $node = New-Object System.Windows.Controls.TreeViewItem
                        $node.Header = $albumName
                        $node.Tag = $path
                        if ($coverState.HasDisplayable) { $node.Foreground = "#7FB069"; $filteredCoveredCount++ }
                        elseif ($coverState.HasCover) { $node.Foreground = "#FFD166"; $invalidCoverCount++ }
                        else { $node.Foreground = "White"; $missingCoverCount++ }
                        $null = $folderNode.Items.Add($node)
                        $visibleCount++
                        if ($tracksPerAlbum.ContainsKey($path)) { $visibleTrackCount += [int]$tracksPerAlbum[$path] }
                    } catch { $exceptionCount++ }
                }
                if ($folderNode.Items.Count -eq 0) {
                    # Avec le filtre / mode "a corriger", on masque les dossiers sans album visible.
                    continue
                }
                $null = $rootNode.Items.Add($folderNode)
            }
            if ($rootNode.Items.Count -gt 0) {
                $useTree = $true
                $null = $FolderTreeView.Items.Add($rootNode)
            } elseif ($onlyToFixMode) {
                # UX: garder la racine visible meme si aucun album n'est a corriger.
                $placeholder = New-Object System.Windows.Controls.TreeViewItem
                if ($filterText) {
                    $placeholder.Header = "Aucun resultat pour ce filtre"
                } else {
                    $placeholder.Header = "Aucun album a corriger"
                }
                $placeholder.Tag = "__placeholder__"
                $placeholder.Foreground = "#9AA0A6"
                $placeholder.IsEnabled = $false
                $null = $rootNode.Items.Add($placeholder)
                $useTree = $true
                $null = $FolderTreeView.Items.Add($rootNode)
            }
        }
    }

    if (-not $useTree) {
        $flatAlbums = @($albums | Sort-Object { (Split-Path $_ -Leaf).ToLowerInvariant() })
        foreach ($path in $flatAlbums) {
            try {
                if (-not (Test-Path -LiteralPath $path)) {
                    $pathMissingCount++
                    continue
                }
                $albumName = Split-Path $path -Leaf
                if ([string]::IsNullOrWhiteSpace($albumName) -or $albumName -match "^[A-Za-z]:\\?$") {
                    $rootSkippedCount++
                    continue
                }
                $coverState = Get-AlbumCoverState -AlbumPath $path

                $matchesFilter = $true
                if ($filterText) {
                    $pathNorm = $path.ToLowerInvariant()
                    $albumNorm = $albumName.ToLowerInvariant()
                    if ($albumNorm -notlike "*$filterText*" -and $pathNorm -notlike "*$filterText*") {
                        $matchesFilter = $false
                        $filterSkippedCount++
                    }
                }
                if (-not $matchesFilter) { continue }

                if ($coverState.HasDisplayable -and -not $filterText -and $onlyToFixMode) {
                    $displayableSkippedCount++
                    continue
                }

                $node = New-Object System.Windows.Controls.TreeViewItem
                $node.Header = $albumName
                $node.Tag = $path
                if ($coverState.HasDisplayable) {
                    $node.Foreground = "#7FB069"
                    $filteredCoveredCount++
                } elseif ($coverState.HasCover) {
                    $node.Foreground = "#FFD166"
                    $invalidCoverCount++
                } else {
                    $node.Foreground = "White"
                    $missingCoverCount++
                }
                $null = $FolderTreeView.Items.Add($node)
                $visibleCount++
                if ($tracksPerAlbum.ContainsKey($path)) {
                    $visibleTrackCount += [int]$tracksPerAlbum[$path]
                }
            } catch {
                $exceptionCount++
                try {
                    if (-not (Test-Path -LiteralPath $path)) { continue }
                    $albumName = Split-Path $path -Leaf
                    if ([string]::IsNullOrWhiteSpace($albumName) -or $albumName -match "^[A-Za-z]:\\?$") { continue }
                    if ($filterText) {
                        $pathNorm = $path.ToLowerInvariant()
                        $albumNorm = $albumName.ToLowerInvariant()
                        if ($albumNorm -notlike "*$filterText*" -and $pathNorm -notlike "*$filterText*") {
                            $filterSkippedCount++
                            continue
                        }
                    }
                    $node = New-Object System.Windows.Controls.TreeViewItem
                    $node.Header = $albumName
                    $node.Tag = $path
                    $node.Foreground = "White"
                    $null = $FolderTreeView.Items.Add($node)
                    $visibleCount++
                    $missingCoverCount++
                    if ($tracksPerAlbum.ContainsKey($path)) {
                        $visibleTrackCount += [int]$tracksPerAlbum[$path]
                    }
                } catch { }
            }
        }
    }

    # Mode de secours anti-regression:
    # si la liste est vide mais la bibliotheque contient des albums,
    # on applique un filtre simple (presence d'un fichier de pochette).
    if (-not $useTree -and $visibleCount -eq 0 -and $albums.Count -gt 0) {
        foreach ($path in $albums) {
            try {
                if (-not (Test-Path -LiteralPath $path)) { continue }
                $albumName = Split-Path $path -Leaf
                if ([string]::IsNullOrWhiteSpace($albumName) -or $albumName -match "^[A-Za-z]:\\?$") { continue }
                if ($filterText) {
                    $pathNorm = $path.ToLowerInvariant()
                    $albumNorm = $albumName.ToLowerInvariant()
                    if ($albumNorm -notlike "*$filterText*" -and $pathNorm -notlike "*$filterText*") {
                        $filterSkippedCount++
                        continue
                    }
                }
                if (Test-AlbumHasAnyCoverFile -AlbumPath $path) { continue }

                $node = New-Object System.Windows.Controls.TreeViewItem
                $node.Header = $albumName
                $node.Tag = $path
                $node.Foreground = "White"
                $null = $FolderTreeView.Items.Add($node)
                $visibleCount++
                $missingCoverCount++
                if ($tracksPerAlbum.ContainsKey($path)) {
                    $visibleTrackCount += [int]$tracksPerAlbum[$path]
                }
            } catch { }
        }
        Write-DebugLog "Fallback used: no visible albums in primary pass."
    }

    if ($AlbumCounter) {
        $headline = "$visibleCount album(s) affiche(s) - $visibleTrackCount pistes audio"
        $counterText = ""
        if (-not $onlyToFixMode) {
            $counterText = "$headline`n$filteredCoveredCount deja OK - $missingCoverCount sans pochette - $invalidCoverCount invalide(s)"
        } elseif ($filterText) {
            if ($visibleCount -eq 0) {
                $counterText = "Aucun resultat`nFiltre: '$filterText'"
            } elseif ($filteredCoveredCount -gt 0) {
                $counterText = "$headline`n$filteredCoveredCount deja OK - $missingCoverCount sans pochette - $invalidCoverCount invalide(s)"
            } else {
                $counterText = "$headline`n$missingCoverCount sans pochette - $invalidCoverCount invalide(s)"
            }
        } elseif ($visibleCount -eq 0) {
            $counterText = "Aucun album a corriger`nTout est OK"
        } elseif ($invalidCoverCount -eq 0) {
            $counterText = "$headline`n$missingCoverCount sans pochette"
        } elseif ($missingCoverCount -eq 0) {
            $counterText = "$headline`n$invalidCoverCount pochette(s) invalide(s)"
        } else {
            $counterText = "$headline`n$missingCoverCount sans pochette - $invalidCoverCount pochette(s) invalide(s)"
        }
        if (-not [string]::IsNullOrWhiteSpace($Script:LastAutoCoverElapsedText)) {
            $counterText += "`nDerniere recherche auto: $Script:LastAutoCoverElapsedText"
        }
        $AlbumCounter.Text = $counterText
    }

    if ($AlbumsPanelTitle) {
        if (-not $onlyToFixMode) {
            $AlbumsPanelTitle.Text = "TOUS LES ALBUMS"
        } elseif ($filterText) {
            $AlbumsPanelTitle.Text = "ALBUMS A CORRIGER (FILTRE)"
        } else {
            $AlbumsPanelTitle.Text = "ALBUMS A CORRIGER"
        }
    }

    Write-DebugLog ("Update-WorkList: albums={0} visible={1} filteredCovered={2} missingCover={3} invalidCover={4} pathMissing={5} rootSkipped={6} displayableSkipped={7} filterSkipped={8} exceptions={9} onlyToFix={10}" -f `
        $albums.Count, $visibleCount, $filteredCoveredCount, $missingCoverCount, $invalidCoverCount, $pathMissingCount, $rootSkippedCount, $displayableSkippedCount, $filterSkippedCount, $exceptionCount, $onlyToFixMode)
}

function Get-FriendlyAlbumLabel {
    param([string]$PathOrAlbum)
    if ([string]::IsNullOrWhiteSpace($PathOrAlbum)) { return "" }
    $value = $PathOrAlbum.Trim()
    if ($value -match "^[A-Za-z]:\\?$") {
        $drive = $value.TrimEnd("\")
        return "[RACINE $drive]"
    }
    return $value
}

function Find-TreeViewItemByTag {
    param([object]$Parent, [string]$Tag)
    if (-not $Parent) { return $null }
    if ($Parent.Tag -eq $Tag) { return $Parent }
    $items = $null
    if ($Parent -is [System.Windows.Controls.TreeView]) { $items = $Parent.Items }
    elseif ($Parent -is [System.Windows.Controls.TreeViewItem]) { $items = $Parent.Items }
    if ($items) {
        foreach ($child in $items) {
            $found = Find-TreeViewItemByTag -Parent $child -Tag $Tag
            if ($found) { return $found }
        }
    }
    return $null
}

function Select-AlbumNodeByPath {
    param([string]$SelectedPath)
    if (-not $FolderTreeView) { return }
    if ([string]::IsNullOrWhiteSpace($SelectedPath)) {
        if ($FolderTreeView.Items.Count -gt 0) {
            $first = $FolderTreeView.Items[0]
            if ($first) {
                $first.IsSelected = $true
                $first.BringIntoView()
            }
        }
        return
    }

    $node = Find-TreeViewItemByTag -Parent $FolderTreeView -Tag $SelectedPath
    if ($node) {
        $node.IsSelected = $true
        $node.BringIntoView()
        $parent = $node.Parent
        while ($parent -and ($parent -is [System.Windows.Controls.TreeViewItem])) {
            $parent.IsExpanded = $true
            $parent = $parent.Parent
        }
        return
    }

    if ($FolderTreeView.Items.Count -gt 0) {
        $first = $FolderTreeView.Items[0]
        if ($first) {
            $first.IsSelected = $true
            $first.BringIntoView()
        }
    }
}

function Copy-SelectedAlbumPathToClipboard {
    if (-not $FolderTreeView -or -not $FolderTreeView.SelectedItem) { return $false }
    $path = [string]$FolderTreeView.SelectedItem.Tag
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    try {
        [System.Windows.Forms.Clipboard]::SetText($path)
        Write-DebugLog "Clipboard copy OK: $path"
        return $true
    } catch {
        Write-DebugLog "Clipboard copy FAILED: $path"
        return $false
    }
}

function Get-NormalizedDisplayTitle {
    param(
        [object]$Track,
        [string]$AlbumPath
    )

    $rawTitle = ""
    try {
        if ($Track -and $Track.PSObject.Properties["FileName"] -and $Track.FileName) {
            $rawTitle = [System.IO.Path]::GetFileNameWithoutExtension([string]$Track.FileName)
        } elseif ($Track -and $Track.PSObject.Properties["Title"] -and $Track.Title) {
            $rawTitle = [string]$Track.Title
        }
    } catch {
        $rawTitle = if ($Track -and $Track.Title) { [string]$Track.Title } else { "" }
    }

    if ([string]::IsNullOrWhiteSpace($rawTitle)) { return "" }

    $title = $rawTitle
    $albumLeaf = ""
    try { $albumLeaf = Split-Path -Path $AlbumPath -Leaf } catch { $albumLeaf = "" }
    $isDiscFolder = ($albumLeaf -match '^(cd|disc|disk)\s*0*\d+$')
    $artistGuess = Get-AlbumArtistGuess -AlbumPath $AlbumPath

    function Get-NormalizedKey {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
        $k = $Value.ToLowerInvariant()
        $k = $k -replace '[^a-z0-9]+', ''
        return $k
    }

    if ($isDiscFolder) {
        if ($title -match '^(?<disc>\d)(?<track>\d{2})[-_\s\.]+(?<rest>.+)$') {
            $title = "$($matches.track) $($matches.rest)"
        } elseif ($title -match '^(?<track>\d{2})[-_\s\.]+(?<rest>.+)$') {
            $title = "$($matches.track) $($matches.rest)"
        }
    }

    # Retirer un prefixe artiste redondant (ex: akhenaton-...)
    if ($title -match '^(?<track>\d{2})\s+(?<artist>[^\s-]+)\s+(?<song>.+)$') {
        $artistToken = Get-NormalizedKey -Value $matches.artist
        $artistRef = Get-NormalizedKey -Value $artistGuess
        if (-not [string]::IsNullOrWhiteSpace($artistRef) -and ($artistRef.StartsWith($artistToken) -or $artistToken.StartsWith($artistRef))) {
            $title = "$($matches.track) $($matches.song)"
        }
    }

    # Uniformiser les separateurs pour une lecture propre.
    $title = $title -replace '[_]+', ' '
    $title = $title -replace '\s*-\s*', ' '
    $title = $title -replace '(?i)\s*\[\s*official.*?\]\s*', ' '
    $title = $title -replace '(?i)\s*\(\s*official.*?\)\s*', ' '
    $title = $title -replace '(?i)\s*youtube\s*$', ' '
    $title = $title -replace '\s+', ' '
    return $title.Trim()
}

function Update-SelectedAlbumView {
    param([bool]$ForceCoverRescan = $false)
    try {
        if (-not $FolderTreeView -or -not $FolderTreeView.SelectedItem) { return }
        $selectedPath = [string]$FolderTreeView.SelectedItem.Tag
        if ([string]::IsNullOrWhiteSpace($selectedPath)) { return }

        if ($ForceCoverRescan) {
            Clear-AlbumCoverStateCacheForPath -AlbumPath $selectedPath
        }

        # Recalcule la liste gauche + recharge la preview de l'album courant
        Update-WorkList
        Select-AlbumNodeByPath -SelectedPath $selectedPath
        Write-DebugLog "Update-SelectedAlbumView done: $selectedPath (force=$ForceCoverRescan)"
    } catch {
        Write-DebugLog "Update-SelectedAlbumView exception: $($_.Exception.Message)"
    }
}

$FolderTreeView.Add_SelectedItemChanged({
    try {
        if (-not $FolderTreeView.SelectedItem) { return }
        if (-not $global:RawData) { return }

        $selectedPath = $FolderTreeView.SelectedItem.Tag
        if ([string]::IsNullOrWhiteSpace([string]$selectedPath) -or [string]$selectedPath -eq "__placeholder__") {
            if ($MusicListView) { $MusicListView.ItemsSource = $null }
            if ($AlbumArtImage) { $AlbumArtImage.Source = $null }
            if ($CurrentTrackInfo) { $CurrentTrackInfo.Text = "" }
            return
        }
        Write-DebugLog "Album selected: $selectedPath"
        if (-not (Test-Path -LiteralPath $selectedPath)) {
            Write-DebugLog "Album selected path missing: $selectedPath"
            [System.Windows.MessageBox]::Show("Le dossier selectionne n'existe plus.`n`n$selectedPath", "Dossier introuvable", "OK", "Warning")
            return
        }

        if (-not [string]::IsNullOrWhiteSpace($Script:CurrentAlbumPath) -and $Script:CurrentAlbumPath -ne [string]$selectedPath) {
            Stop-AlbumPlayback -ResetPlaylist $true
        }

        $selectedNorm = $selectedPath.TrimEnd('\')
        $isAlbum = $global:AlbumsIndex -and ($global:AlbumsIndex -contains $selectedPath)
        if ($isAlbum) {
            $tracks = @($global:RawData | Where-Object { $_.FullDir -eq $selectedPath })
        } else {
            $tracks = @($global:RawData | Where-Object {
                $d = [string]$_.FullDir
                if ([string]::IsNullOrWhiteSpace($d)) { return $false }
                $dn = $d.TrimEnd('\')
                $dn -eq $selectedNorm -or $dn.StartsWith($selectedNorm + '\')
            })
        }
        $friendlySelected = Get-FriendlyAlbumLabel -PathOrAlbum $selectedPath
        $albumCanonical = Get-AlbumCanonicalName -AlbumPath $selectedPath
        $artistGuess = Get-AlbumArtistGuess -AlbumPath $selectedPath
        $displayTracks = @(
            $tracks | ForEach-Object {
                $albumDisplay = Get-FriendlyAlbumLabel -PathOrAlbum $albumCanonical
                if ($albumDisplay -match "^\[RACINE [A-Za-z]:\]$") { $albumDisplay = "" }
                $normalizedTitle = Get-NormalizedDisplayTitle -Track $_ -AlbumPath $selectedPath
                Write-DebugLog ("Track normalize: '{0}' => '{1}'" -f $_.Title, $normalizedTitle)
                $fmt = ""
                try {
                    $trackPath = [string]$_.Path
                    if (-not [string]::IsNullOrWhiteSpace($trackPath)) {
                        $fmt = [System.IO.Path]::GetExtension($trackPath).TrimStart(".").ToLowerInvariant()
                    }
                } catch { }
                [pscustomobject]@{
                    TrackDisplay = if ([string]::IsNullOrWhiteSpace($normalizedTitle)) { $_.Title } else { $normalizedTitle }
                    ArtistDisplay = $artistGuess
                    AlbumDisplay = $albumDisplay
                    FormatDisplay = $fmt
                    TrackPath = [string]$_.Path
                }
            }
        )
        if ($MusicListView) {
            $MusicListView.ItemsSource = $displayTracks
            Set-MusicListSort
        }

        if ($AlbumArtImage) {
            try {
                $coverState = Get-AlbumCoverState -AlbumPath $selectedPath
                if ($coverState.HasDisplayable -and $coverState.CoverFile) {
                    Write-DebugLog "Preview cover loaded: $($coverState.CoverFile.FullName)"
                    # Force un vrai rechargement meme si le chemin reste "cover.jpg".
                    # StreamSource + OnLoad suffit ici; IgnoreImageCache peut provoquer une exception avec stream-only.
                    $AlbumArtImage.Source = $null
                    $imageBytes = [System.IO.File]::ReadAllBytes($coverState.CoverFile.FullName)
                    $stream = New-Object System.IO.MemoryStream(, $imageBytes)
                    try {
                        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                        $bitmap.BeginInit()
                        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                        $bitmap.StreamSource = $stream
                        $bitmap.EndInit()
                        $bitmap.Freeze()
                        $AlbumArtImage.Source = $bitmap
                    } finally {
                        $stream.Close()
                        $stream.Dispose()
                    }
                } else {
                    Write-DebugLog "Preview cover missing for: $selectedPath"
                    $AlbumArtImage.Source = $null
                }
            } catch {
                Write-DebugLog "Preview cover load exception: $($_.Exception.Message)"
                $AlbumArtImage.Source = $null
            }
        }

        if ($CurrentTrackInfo) {
            $albumName = $albumCanonical
            if ([string]::IsNullOrWhiteSpace($albumName)) {
                $albumName = $friendlySelected
            } else {
                $albumName = Get-FriendlyAlbumLabel -PathOrAlbum $albumName
            }
            if ([string]::IsNullOrWhiteSpace($albumName)) { $albumName = "Album" }
            $line2 = "$($tracks.Count) piste(s)"
            $selectedNorm = $selectedPath.TrimEnd('\')
            if ($global:ScanRoot -and ($selectedNorm -eq $global:ScanRoot.TrimEnd('\'))) {
                $line2 += "`n(Pochette : placez cover.jpg dans ce dossier)"
            }
            $CurrentTrackInfo.Text = "$albumName`n$line2"
        }
    } catch {
        Write-DebugLog "SelectedItemChanged exception: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Erreur lors de la selection de l'album :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
    }
})

if ($RefreshLibraryBtn) {
    $RefreshLibraryBtn.Add_Click({
        try {
            Write-DebugLog "RefreshLibrary click"
            if (-not (Test-Path -LiteralPath $LibraryPath)) {
                [System.Windows.MessageBox]::Show("Library.json introuvable. Lancez d'abord un scan (SCANNER.bat ou RESCAN_SAME.bat).", "Actualisation", "OK", "Warning")
                return
            }
            Update-LibraryData
            Update-WorkList
            [System.Windows.MessageBox]::Show("Bibliotheque rechargee depuis Library.json.`nLes nouveaux dossiers (ex: divers) sont maintenant visibles.", "Bibliotheque actualisee", "OK", "Information")
        } catch {
            Write-DebugLog "RefreshLibrary exception: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show("Erreur lors de l'actualisation :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
        }
    })
}

if ($AutoCoverBtn) {
    $AutoCoverBtn.Add_Click({
        try {
            Write-DebugLog "AutoCover click"
            $autoCoverStartedAt = Get-Date
            $selectedBefore = $null
            if ($FolderTreeView.SelectedItem) { $selectedBefore = [string]$FolderTreeView.SelectedItem.Tag }
            $targets = @()
            foreach ($item in $FolderTreeView.Items) {
                if ($item -and $item.Tag) { $targets += [string]$item.Tag }
            }

            if ($targets.Count -eq 0) {
                Write-DebugLog "AutoCover: no targets"
                [System.Windows.MessageBox]::Show("Aucun album a traiter dans la liste.", "Info", "OK", "Information")
                return
            }

            $totalCandidates = $targets.Count
            $totalBatches = [math]::Ceiling($totalCandidates / [double]$AutoCoverBatchLimit)
            Write-DebugLog "AutoCover start: candidates=$totalCandidates batches=$totalBatches"

            $progressForm = New-Object System.Windows.Forms.Form
            $progressForm.Text = "MusicSelektor by Joe Kurwa - Recherche auto de pochettes"
            $progressForm.Size = New-Object System.Drawing.Size(620, 190)
            $progressForm.StartPosition = "CenterScreen"
            $progressForm.FormBorderStyle = "FixedDialog"
            $progressForm.MaximizeBox = $false
            $progressForm.MinimizeBox = $false
            $progressForm.TopMost = $true

            $statusLabel = New-Object System.Windows.Forms.Label
            $statusLabel.Location = New-Object System.Drawing.Point(20, 20)
            $statusLabel.Size = New-Object System.Drawing.Size(560, 22)
            $statusLabel.Text = "Initialisation..."
            $progressForm.Controls.Add($statusLabel)

            $detailLabel = New-Object System.Windows.Forms.Label
            $detailLabel.Location = New-Object System.Drawing.Point(20, 45)
            $detailLabel.Size = New-Object System.Drawing.Size(560, 22)
            $detailLabel.Text = ""
            $progressForm.Controls.Add($detailLabel)

            $bar = New-Object System.Windows.Forms.ProgressBar
            $bar.Location = New-Object System.Drawing.Point(20, 80)
            $bar.Size = New-Object System.Drawing.Size(560, 28)
            $bar.Minimum = 0
            $bar.Maximum = $totalCandidates
            $bar.Value = 0
            $progressForm.Controls.Add($bar)

            $progressForm.Show()
            [System.Windows.Forms.Application]::DoEvents()

            $downloaded = 0
            $notFound = 0
            $failed = 0
            $alreadyOk = 0
            $reportRows = New-Object System.Collections.Generic.List[object]

            for ($i = 0; $i -lt $totalCandidates; $i++) {
                $albumPath = $targets[$i]
                $albumName = Split-Path -Path $albumPath -Leaf
                $processed = $i + 1
                $batchIndex = [math]::Floor($i / $AutoCoverBatchLimit) + 1
                $inBatchIndex = ($i % $AutoCoverBatchLimit) + 1
                $statusLabel.Text = "Recherche des pochettes... $processed/$totalCandidates (lot $batchIndex/$totalBatches)"
                $detailLabel.Text = "$albumName - lot $inBatchIndex/$AutoCoverBatchLimit"
                $bar.Value = $processed
                [System.Windows.Forms.Application]::DoEvents()

                $result = Find-And-SaveCoverForAlbum -AlbumPath $albumPath
                Write-DebugLog "AutoCover album result: [$processed/$totalCandidates] $albumPath => $result"
                switch ($result) {
                    "downloaded" { $downloaded++ }
                    "already-ok" { $alreadyOk++ }
                    "not-found" { $notFound++ }
                    default { $failed++ }
                }

                $reportRows.Add([pscustomobject]@{
                    Timestamp = (Get-Date).ToString("s")
                    AlbumPath = $albumPath
                    AlbumName = $albumName
                    Result = $result
                }) | Out-Null

                # Rafraichissement automatique par lot pour garder la colonne gauche coherente
                if (($processed % $AutoCoverBatchLimit) -eq 0 -or $processed -eq $totalCandidates) {
                    Write-DebugLog "AutoCover batch refresh: processed=$processed"
                    if ($processed -lt $totalCandidates -and $AutoCoverInterBatchPauseMs -gt 0) {
                        $detailLabel.Text = "Stabilisation reseau... reprise dans $([math]::Round($AutoCoverInterBatchPauseMs / 1000.0, 1))s"
                        [System.Windows.Forms.Application]::DoEvents()
                        Start-Sleep -Milliseconds $AutoCoverInterBatchPauseMs
                    }
                    Save-CoverCache
                    Update-LibraryData
                    Update-WorkList
                    Select-AlbumNodeByPath -SelectedPath $selectedBefore
                    $detailLabel.Text = "Rafraichissement de la liste..."
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }

            Save-CoverCache
            try {
                $reportRows | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $AutoCoverReportPath -Encoding UTF8 -Force
            } catch { }
            $progressForm.Close()
            Update-LibraryData
            Update-WorkList
            Select-AlbumNodeByPath -SelectedPath $selectedBefore
            $remainingToFix = if ($FolderTreeView) { $FolderTreeView.Items.Count } else { 0 }
            $elapsedSeconds = [math]::Round(((Get-Date) - $autoCoverStartedAt).TotalSeconds, 3)
            $elapsedText = Format-ElapsedText -Seconds $elapsedSeconds
            $Script:LastAutoCoverElapsedText = $elapsedText
            Write-DebugLog "AutoCover elapsed: $elapsedText"
            Save-LastAutoCoverTiming -ElapsedSeconds $elapsedSeconds -ElapsedText $elapsedText
            Update-SignatureText
            if ($AlbumCounter -and -not [string]::IsNullOrWhiteSpace($AlbumCounter.Text) -and ($AlbumCounter.Text -notmatch 'Derniere recherche auto:')) {
                $AlbumCounter.Text += "`nDerniere recherche auto: $elapsedText"
            }
            if ($AutoCoverBtn) {
                $AutoCoverBtn.Content = "🤖 TROUVER LES POCHETTES (AUTO - LOT)"
                $AutoCoverBtn.ToolTip = "Recherche automatique en masse pour toute la liste d'albums. Dernier temps: $elapsedText"
            }
            Write-DebugLog "AutoCover done: downloaded=$downloaded alreadyOk=$alreadyOk notFound=$notFound failed=$failed remaining=$remainingToFix"

            $msg = @(
                "Traitement termine.",
                "",
                "Temps total: $elapsedText",
                "Albums traites: $totalCandidates",
                "Traitement fiable active (lots: $AutoCoverBatchLimit, pause inter-lot: $([math]::Round($AutoCoverInterBatchPauseMs / 1000.0, 1))s)",
                "Pochettes telechargees: $downloaded",
                "Deja OK: $alreadyOk",
                "Introuvables: $notFound",
                "Echecs: $failed",
                "Restent a corriger (liste actuelle): $remainingToFix",
                "",
                "Rapport: $AutoCoverReportPath"
            ) -join "`n"
            [System.Windows.MessageBox]::Show($msg, "Recherche auto", "OK", "Information")
        } catch {
            Write-DebugLog "AutoCover exception: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show("Erreur pendant la recherche auto:`n$($_.Exception.Message)", "Erreur", "OK", "Error")
        }
    })
}

if ($AlbumFilterBox) {
    $AlbumFilterBox.Add_TextChanged({
        Write-DebugLog "Filter changed: '$($AlbumFilterBox.Text)'"
        Update-WorkList
        Select-AlbumNodeByPath -SelectedPath $null
    })
}

if ($ClearFilterBtn) {
    $ClearFilterBtn.Add_Click({
        Write-DebugLog "Filter clear click"
        if ($AlbumFilterBox) { $AlbumFilterBox.Text = "" }
        Update-WorkList
        Select-AlbumNodeByPath -SelectedPath $null
    })
}

if ($ShowAllAlbumsToggle) {
    $ShowAllAlbumsToggle.Add_Click({
        Write-DebugLog "OnlyToFix toggle: $($ShowAllAlbumsToggle.IsChecked)"
        Update-WorkList
        Select-AlbumNodeByPath -SelectedPath $null
    })
}

if ($OpenFolderBtn) {
    $OpenFolderBtn.Add_Click({
        try {
            Write-DebugLog "Playback button click"
            if (-not $FolderTreeView.SelectedItem) {
                Write-DebugLog "Playback ignored: no selection"
                [System.Windows.MessageBox]::Show("Veuillez d'abord selectionner un dossier ou un album.", "Information", "OK", "Information")
                return
            }
            $path = [string]$FolderTreeView.SelectedItem.Tag
            if (-not (Test-Path -LiteralPath $path)) {
                Write-DebugLog "Playback path missing: $path"
                [System.Windows.MessageBox]::Show("Le dossier selectionne n'existe plus :`n$path", "Dossier introuvable", "OK", "Warning")
                return
            }

            if ($Script:CurrentAlbumPath -ne $path -or -not $Script:CurrentPlaylist -or $Script:CurrentPlaylist.Count -eq 0) {
                Stop-AlbumPlayback -ResetPlaylist $true
                $Script:CurrentAlbumPath = $path
                $Script:CurrentPlaylist = Get-PlayableTracksForAlbum -AlbumPath $path
                $Script:CurrentTrackIndex = -1
            }

            if (-not $Script:CurrentPlaylist -or $Script:CurrentPlaylist.Count -eq 0) {
                Write-DebugLog "Playback no supported audio files"
                [System.Windows.MessageBox]::Show("Aucun fichier audio lisible trouve dans cette selection.`nFormats testes: mp3, wav, m4a, wma, aac, flac, ogg.", "Lecture", "OK", "Information")
                Update-PlayButtonState
                return
            }

            if ($Script:InternalPlayerEnabled -and $Script:PlaybackMode -eq "internal" -and $Script:AudioPlayer) {
                if ($Script:IsAudioPlaying) {
                    $Script:AudioPlayer.Pause()
                    $Script:IsAudioPlaying = $false
                    if ($Script:CurrentTrackIndex -ge 0 -and $Script:CurrentTrackIndex -lt $Script:CurrentPlaylist.Count) {
                        $pausedTitle = [string]$Script:CurrentPlaylist[$Script:CurrentTrackIndex].Title
                        Set-PlaybackInfo -Prefix "Pause (interne)" -TrackTitle $pausedTitle
                    }
                    Update-PlayButtonState
                } elseif ($Script:CurrentTrackIndex -ge 0) {
                    $Script:AudioPlayer.Play()
                    $Script:IsAudioPlaying = $true
                    if ($Script:CurrentTrackIndex -ge 0 -and $Script:CurrentTrackIndex -lt $Script:CurrentPlaylist.Count) {
                        $trackTitle = [string]$Script:CurrentPlaylist[$Script:CurrentTrackIndex].Title
                        Set-PlaybackInfo -Prefix "Lecture (interne)" -TrackTitle $trackTitle
                    }
                    Update-PlayButtonState
                } else {
                    $started = Start-PlaybackAtIndex -Index 0
                    if (-not $started) {
                        [System.Windows.MessageBox]::Show("Impossible de demarrer la lecture pour cet album.", "Lecture", "OK", "Warning")
                        return
                    }
                }
            } else {
                if ($Script:CurrentTrackIndex -lt 0) {
                    $started = Start-PlaybackAtIndex -Index 0
                    if (-not $started) {
                        [System.Windows.MessageBox]::Show("Impossible de demarrer la lecture pour cet album.", "Lecture", "OK", "Warning")
                        return
                    }
                } else {
                    $started = Start-PlaybackAtIndex -Index $Script:CurrentTrackIndex
                    if (-not $started) {
                        [System.Windows.MessageBox]::Show("Impossible de relancer la lecture pour cette piste.", "Lecture", "OK", "Warning")
                        return
                    }
                }
            }
        } catch {
            Write-DebugLog "Playback button exception: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show("Erreur lors de la lecture :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
        }
    })
}

if ($PrevTrackBtn) {
    $PrevTrackBtn.Add_Click({
        try {
            Write-DebugLog "PrevTrack click"
            Skip-PlaybackTrack -Delta -1
        } catch {
            Write-DebugLog "PrevTrack exception: $($_.Exception.Message)"
        }
    })
}

if ($NextTrackBtn) {
    $NextTrackBtn.Add_Click({
        try {
            Write-DebugLog "NextTrack click"
            Skip-PlaybackTrack -Delta 1
        } catch {
            Write-DebugLog "NextTrack exception: $($_.Exception.Message)"
        }
    })
}

if ($SearchOnlineBtn) {
    $SearchOnlineBtn.Add_Click({
        if ($FolderTreeView.SelectedItem) {
            $selectedPath = [string]$FolderTreeView.SelectedItem.Tag
            $artist = Get-AlbumArtistGuess -AlbumPath $selectedPath
            $album = Get-AlbumCanonicalName -AlbumPath $selectedPath
            $term = "$artist $album album cover"
            Write-DebugLog "SearchOnline click: term='$term'"
            [void](Copy-SelectedAlbumPathToClipboard)
            $browserUrl = "https://www.google.com/search?q=$([uri]::EscapeDataString($term))&tbm=isch"
            Write-NetworkTrace -Action "browser-open" -Provider "GoogleImages" -Url $browserUrl -Status "start" -Details ("term={0}" -f $term)
            Start-Process $browserUrl
        }
    })
}

if ($ApplyCoverClipboardBtn) {
    $ApplyCoverClipboardBtn.Add_Click({
        try {
            if (-not $FolderTreeView.SelectedItem) {
                [System.Windows.MessageBox]::Show("Selectionne d'abord un album.", "Information", "OK", "Information")
                return
            }
            $selectedPath = [string]$FolderTreeView.SelectedItem.Tag
            if ([string]::IsNullOrWhiteSpace($selectedPath) -or -not (Test-Path -LiteralPath $selectedPath)) {
                [System.Windows.MessageBox]::Show("Le dossier selectionne est introuvable.", "Dossier introuvable", "OK", "Warning")
                return
            }

            $clipboardValue = ""
            try { $clipboardValue = [string](Get-Clipboard) } catch { $clipboardValue = "" }
            if ([string]::IsNullOrWhiteSpace($clipboardValue)) {
                [System.Windows.MessageBox]::Show(
                    "Le presse-papiers est vide.`n`nCopie d'abord l'adresse directe de l'image (ou une data URL), puis reessaie.",
                    "Cover manuelle",
                    "OK",
                    "Information"
                )
                return
            }

            $saveCoverScript = Join-Path $CurrentDir "SaveCoverFromClipboardUrl.ps1"
            if (-not (Test-Path -LiteralPath $saveCoverScript)) {
                [System.Windows.MessageBox]::Show("SaveCoverFromClipboardUrl.ps1 introuvable.", "Erreur", "OK", "Error")
                return
            }

            & $saveCoverScript -AlbumPath $selectedPath -Url $clipboardValue | Out-Null
            Update-SelectedAlbumView -ForceCoverRescan $true
            [System.Windows.MessageBox]::Show("Cover appliquee avec succes.", "Cover manuelle", "OK", "Information")
        } catch {
            [System.Windows.MessageBox]::Show("Impossible d'appliquer la cover :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
        }
    })
}

if ($Window) {
    $Window.Add_Activated({
        try {
            # Quand on revient du navigateur/explorateur, on force un refresh cover
            Update-SelectedAlbumView -ForceCoverRescan $true
        } catch { }
    })
    $Window.Add_Closing({
        try {
            if ($Script:AudioPlayer) {
                $Script:AudioPlayer.Stop()
                $Script:AudioPlayer.Close()
            }
        } catch { }
    })
}

if ($Window) {
    $Window.Add_PreviewKeyDown({
        param($src, $e)
        try {
            if (($e.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -and $e.Key -eq [System.Windows.Input.Key]::C) {
                if (Copy-SelectedAlbumPathToClipboard) {
                    Write-DebugLog "Shortcut Ctrl+C handled"
                    $e.Handled = $true
                }
            }
        } catch { }
    })
}

if ($FindDuplicatesBtn) {
    $FindDuplicatesBtn.Add_Click({
        try {
            Write-DebugLog "FindDuplicates click"
            $findDuplicatesScript = Join-Path $CurrentDir "FindDuplicates.ps1"
            if (Test-Path -LiteralPath $findDuplicatesScript) {
                Write-DebugLog "FindDuplicates start: $findDuplicatesScript"
                Start-Process "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$findDuplicatesScript`""
            } else {
                Write-DebugLog "FindDuplicates script missing: $findDuplicatesScript"
                [System.Windows.MessageBox]::Show("Le script FindDuplicates.ps1 est introuvable.`nChemin attendu : $findDuplicatesScript", "Erreur", "OK", "Error")
            }
        } catch {
            Write-DebugLog "FindDuplicates exception: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show("Erreur lors du lancement de la detection de doublons :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
        }
    })
}

try {
    Write-DebugLog "Window show start"
    Update-WorkList
    Select-AlbumNodeByPath -SelectedPath $null
    $Window.ShowDialog() | Out-Null
    Write-DebugLog "Window closed"
} catch {
    try { "[$(Get-Date -Format s)] DISPLAY: $($_.Exception.Message)" | Out-File -LiteralPath $StartupErrorPath -Encoding UTF8 -Append } catch { }
    [System.Windows.MessageBox]::Show("Erreur lors de l'affichage :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
    exit 1
}
