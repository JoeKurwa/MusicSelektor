param(
    [string]$LibraryPath = "",
    [switch]$Apply,
    [switch]$IncludeGeneralCleanup,
    [switch]$IUnderstand
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($ScriptDir)) { $ScriptDir = $PSScriptRoot }

if ([string]::IsNullOrWhiteSpace($LibraryPath)) {
    $LibraryPath = Join-Path $ScriptDir "Library.json"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportCsv = Join-Path $ScriptDir "NormalizeTrackNames.report.$timestamp.csv"
$reportJson = Join-Path $ScriptDir "NormalizeTrackNames.report.$timestamp.json"
$writeActionsLogPath = Join-Path $ScriptDir "MusicSelektor.write-actions.log"
$effectiveApply = ($Apply -and $IUnderstand)

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
        "$stamp script=NormalizeTrackNames action=$Action status=$Status source=`"$SourcePath`" target=`"$TargetPath`" details=`"$Details`"" | Out-File -LiteralPath $writeActionsLogPath -Encoding UTF8 -Append
    } catch { }
}

function Test-FileAccessibleSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        if (Test-Path -LiteralPath $Path -ErrorAction Stop) { return $true }
    } catch { }
    try {
        if ([System.IO.File]::Exists($Path)) { return $true }
    } catch { }
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return ($null -ne $item -and -not $item.PSIsContainer)
    } catch { }
    return $false
}

function Get-ArtistGuessFromAlbumPath {
    param([string]$AlbumPath)
    try {
        $parent = Split-Path -Path $AlbumPath -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) { return "" }
        $grandParent = Split-Path -Path $parent -Parent
        if (-not [string]::IsNullOrWhiteSpace($grandParent)) {
            return (Split-Path -Path $grandParent -Leaf)
        }
        return (Split-Path -Path $parent -Leaf)
    } catch {
        return ""
    }
}

function Get-NormalizedKey {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $k = $Value.ToLowerInvariant()
    $k = $k -replace '[^a-z0-9]+', ''
    return $k
}

function ConvertFrom-RecoveryEscapes {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    $decoded = $Value

    # Converts tokens like u00e9, u0027, etc.
    $decoded = [regex]::Replace($decoded, '(?i)u([0-9a-f]{4})', {
        param($m)
        try {
            $code = [Convert]::ToInt32($m.Groups[1].Value, 16)
            return [char]$code
        } catch {
            return $m.Value
        }
    })

    # Decode common HTML entities (&amp; etc.)
    try {
        $decoded = [System.Net.WebUtility]::HtmlDecode($decoded)
    } catch { }

    return $decoded
}

function Test-IsDiscFolder {
    param([string]$AlbumPath)
    $albumLeaf = ""
    try { $albumLeaf = Split-Path -Path $AlbumPath -Leaf } catch { $albumLeaf = "" }
    return ($albumLeaf -match '^(cd|disc|disk)\s*0*\d+$')
}

function Test-IsRepairCandidate {
    param(
        [string]$BaseName,
        [string]$AlbumPath
    )
    if ([string]::IsNullOrWhiteSpace($BaseName)) { return $false }
    if (Test-IsDiscFolder -AlbumPath $AlbumPath) { return $true }
    if ($BaseName -match '(?i)u[0-9a-f]{4}') { return $true }
    if ($BaseName -match '(?i)&amp;|u0026amp') { return $true }
    if ($BaseName -match '^\d{3}[-_\s\.]+') { return $true }
    return $false
}

function Get-NormalizedBaseName {
    param(
        [string]$BaseName,
        [string]$AlbumPath
    )

    if ([string]::IsNullOrWhiteSpace($BaseName)) { return "" }
    $title = (ConvertFrom-RecoveryEscapes -Value $BaseName).Trim()
    $trackPrefix = ""

    $isDiscFolder = Test-IsDiscFolder -AlbumPath $AlbumPath

    if ($isDiscFolder) {
        if ($title -match '^(?<disc>\d)(?<track>\d{2})[-_\s\.]+(?<rest>.+)$') {
            $trackPrefix = $matches.track
            $title = $matches.rest
        } elseif ($title -match '^(?<track>\d{2})[-_\s\.]+(?<rest>.+)$') {
            $trackPrefix = $matches.track
            $title = $matches.rest
        }
    } elseif ($title -match '^(?<track>\d{2})[-_\s\.]+(?<rest>.+)$') {
        $trackPrefix = $matches.track
        $title = $matches.rest
    }

    $artistGuess = Get-ArtistGuessFromAlbumPath -AlbumPath $AlbumPath
    $artistRef = Get-NormalizedKey -Value $artistGuess

    # Remove leading artist token when redundant.
    if ($title -match '^(?<artist>[^\s\-_]+)[\s\-_]+(?<song>.+)$') {
        $artistToken = Get-NormalizedKey -Value $matches.artist
        if (-not [string]::IsNullOrWhiteSpace($artistRef) -and ($artistRef.StartsWith($artistToken) -or $artistToken.StartsWith($artistRef))) {
            $title = $matches.song
        }
    }

    # Repair-only: normalize separators for malformed recovery names.
    $title = $title -replace '[_]+', ' '
    $title = $title -replace '\s*-\s*', ' '
    if ($IncludeGeneralCleanup) {
        $title = $title -replace '(?i)\s*\[\s*official.*?\]\s*', ' '
        $title = $title -replace '(?i)\s*\(\s*official.*?\)\s*', ' '
        $title = $title -replace '(?i)\s*youtube\s*$', ' '
    }
    $title = $title -replace '\s+', ' '
    $title = $title.Trim()

    if (-not [string]::IsNullOrWhiteSpace($trackPrefix)) {
        return ("{0} {1}" -f $trackPrefix, $title).Trim()
    }
    return $title
}

if (-not (Test-FileAccessibleSafe -Path $LibraryPath)) {
    Write-Host "[ERROR] Library.json not found: $LibraryPath" -ForegroundColor Red
    exit 1
}

try {
    $raw = Get-Content -LiteralPath $LibraryPath -Raw -Encoding UTF8
    $parsed = ConvertFrom-Json -InputObject $raw
    if ($parsed -is [System.Array]) {
        $items = $parsed
    } else {
        $items = @($parsed)
    }
} catch {
    Write-Host "[ERROR] Invalid Library.json: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$rows = New-Object System.Collections.Generic.List[object]
$files = @($items | Where-Object { $_ -and $_.Path } | Group-Object Path | ForEach-Object { $_.Group[0] })

foreach ($song in $files) {
    $oldPath = [string]$song.Path
    if ([string]::IsNullOrWhiteSpace($oldPath)) { continue }
    if (-not (Test-FileAccessibleSafe -Path $oldPath)) {
        $rows.Add([pscustomobject]@{
            Status = "skip-missing"
            OldPath = $oldPath
            NewPath = ""
            Reason = "File missing"
        }) | Out-Null
        continue
    }

    $dir = Split-Path -Path $oldPath -Parent
    $name = [System.IO.Path]::GetFileNameWithoutExtension($oldPath)
    $ext = [System.IO.Path]::GetExtension($oldPath)
    $isRepairTarget = Test-IsRepairCandidate -BaseName $name -AlbumPath ([string]$song.FullDir)

    if (-not $IncludeGeneralCleanup -and -not $isRepairTarget) {
        $rows.Add([pscustomobject]@{
            Status = "skip-not-target"
            OldPath = $oldPath
            NewPath = ""
            Reason = "Not a repair candidate"
        }) | Out-Null
        continue
    }

    $newBase = Get-NormalizedBaseName -BaseName $name -AlbumPath ([string]$song.FullDir)

    if ([string]::IsNullOrWhiteSpace($newBase)) {
        $rows.Add([pscustomobject]@{
            Status = "skip-empty"
            OldPath = $oldPath
            NewPath = ""
            Reason = "Empty normalized name"
        }) | Out-Null
        continue
    }

    $newName = "$newBase$ext"
    $newPath = Join-Path $dir $newName

    if ($newPath -ieq $oldPath) {
        $rows.Add([pscustomobject]@{
            Status = "unchanged"
            OldPath = $oldPath
            NewPath = $newPath
            Reason = "Already normalized"
        }) | Out-Null
        continue
    }

    $candidatePath = $newPath
    $counter = 1
    while (Test-FileAccessibleSafe -Path $candidatePath) {
        $candidateName = "{0} ({1}){2}" -f $newBase, $counter, $ext
        $candidatePath = Join-Path $dir $candidateName
        $counter++
    }
    $newPath = $candidatePath
    $newName = [System.IO.Path]::GetFileName($newPath)

    if ($effectiveApply) {
        try {
            Rename-Item -LiteralPath $oldPath -NewName $newName -ErrorAction Stop
            Write-WriteActionLog -Action "rename" -Status "applied" -SourcePath $oldPath -TargetPath $newPath -Details "Apply+IUnderstand"
            $rows.Add([pscustomobject]@{
                Status = "renamed"
                OldPath = $oldPath
                NewPath = $newPath
                Reason = "Applied"
            }) | Out-Null
        } catch {
            Write-WriteActionLog -Action "rename" -Status "error" -SourcePath $oldPath -TargetPath $newPath -Details $_.Exception.Message
            $rows.Add([pscustomobject]@{
                Status = "error"
                OldPath = $oldPath
                NewPath = $newPath
                Reason = $_.Exception.Message
            }) | Out-Null
        }
    } elseif ($Apply -and -not $IUnderstand) {
        Write-WriteActionLog -Action "rename" -Status "blocked-safety" -SourcePath $oldPath -TargetPath $newPath -Details "Missing -IUnderstand"
        $rows.Add([pscustomobject]@{
            Status = "blocked-safety"
            OldPath = $oldPath
            NewPath = $newPath
            Reason = "Blocked: use -Apply -IUnderstand"
        }) | Out-Null
    } else {
        $rows.Add([pscustomobject]@{
            Status = "preview"
            OldPath = $oldPath
            NewPath = $newPath
            Reason = "Dry run"
        }) | Out-Null
    }
}

$rows | Export-Csv -LiteralPath $reportCsv -NoTypeInformation -Encoding UTF8
$rows | ConvertTo-Json -Depth 4 | Out-File -LiteralPath $reportJson -Encoding UTF8 -Force

$previewCount = @($rows | Where-Object { $_.Status -eq "preview" }).Count
$renamedCount = @($rows | Where-Object { $_.Status -eq "renamed" }).Count
$errorCount = @($rows | Where-Object { $_.Status -eq "error" }).Count
$skipCount = @($rows | Where-Object { $_.Status -like "skip-*" }).Count
$skipNotTargetCount = @($rows | Where-Object { $_.Status -eq "skip-not-target" }).Count
$blockedSafetyCount = @($rows | Where-Object { $_.Status -eq "blocked-safety" }).Count

Write-Host ""
Write-Host "NormalizeTrackNames summary" -ForegroundColor Cyan
$modeLabel = if ($effectiveApply) { "APPLY" } elseif ($Apply) { "APPLY-BLOCKED-SAFETY" } else { "PREVIEW" }
Write-Host "Mode: $modeLabel" -ForegroundColor White
Write-Host "General cleanup: $IncludeGeneralCleanup" -ForegroundColor White
Write-Host "Preview entries: $previewCount" -ForegroundColor Yellow
Write-Host "Renamed: $renamedCount" -ForegroundColor Green
Write-Host "Skipped: $skipCount" -ForegroundColor DarkYellow
Write-Host "  - Not target: $skipNotTargetCount" -ForegroundColor DarkYellow
Write-Host "Blocked safety: $blockedSafetyCount" -ForegroundColor Magenta
Write-Host "Errors: $errorCount" -ForegroundColor Red
Write-Host "CSV report: $reportCsv" -ForegroundColor White
Write-Host "JSON report: $reportJson" -ForegroundColor White
Write-Host "Write actions log: $writeActionsLogPath" -ForegroundColor White
Write-Host ""
