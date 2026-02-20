param(
    [string]$Url = "",
    [string]$AlbumPath = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PSScriptRoot }
$stateFile = Join-Path $scriptDir ".next-cover-target.txt"
$writeLogPath = Join-Path $scriptDir "MusicSelektor.write-actions.log"

function Write-WriteActionLog {
    param(
        [string]$Action,
        [string]$Status,
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$Details
    )
    try {
        $safeSource = Format-LogValue -Value $SourcePath
        $safeTarget = Format-LogValue -Value $TargetPath
        $safeDetails = Format-LogValue -Value $Details -MaxLen 320
        $stamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
        "$stamp script=SaveCoverFromClipboardUrl action=$Action status=$Status source=`"$safeSource`" target=`"$safeTarget`" details=`"$safeDetails`"" | Out-File -LiteralPath $writeLogPath -Encoding UTF8 -Append
    } catch { }
}

function Format-LogValue {
    param(
        [AllowNull()]
        [string]$Value,
        [int]$MaxLen = 220
    )
    if ($null -eq $Value) { return "" }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }
    $text = ($text -replace '[\r\n\t]+', ' ').Trim()

    if ($text -match '^(?i)data:image\/(?<fmt>jpeg|jpg|png);base64,(?<payload>.+)$') {
        $fmt = [string]$matches.fmt
        $payloadLen = ([string]$matches.payload).Length
        return ("data:image/{0};base64,[truncated:{1} chars]" -f $fmt, $payloadLen)
    }

    if ($text.Length -gt $MaxLen) {
        return ($text.Substring(0, $MaxLen) + "...[truncated]")
    }
    return $text
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
            if ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) { return $true }
            if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) { return $true }
            return $false
        } finally {
            $stream.Close()
        }
    } catch {
        return $false
    }
}

function Get-ImageFormatFromMagic {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "unknown" }
    if (-not (Test-Path -LiteralPath $Path)) { return "unknown" }
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $bytes = New-Object byte[] 8
            $null = $stream.Read($bytes, 0, 8)
            if ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) { return "png" }
            if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) { return "jpeg" }
            return "unknown"
        } finally {
            $stream.Close()
        }
    } catch {
        return "unknown"
    }
}

function Convert-ImageToJpeg {
    param(
        [string]$InputPath,
        [string]$OutputPath
    )
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null
        $img = [System.Drawing.Image]::FromFile($InputPath)
        try {
            $bmp = New-Object System.Drawing.Bitmap $img.Width, $img.Height
            try {
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                try {
                    # Fond blanc pour les PNG avec transparence.
                    $g.Clear([System.Drawing.Color]::White)
                    $g.DrawImage($img, 0, 0, $img.Width, $img.Height)
                } finally {
                    $g.Dispose()
                }
                $bmp.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            } finally {
                $bmp.Dispose()
            }
        } finally {
            $img.Dispose()
        }
        return $true
    } catch {
        return $false
    }
}

function Save-DataImageUrlToFile {
    param(
        [string]$DataUrl,
        [string]$OutputFile
    )
    if ([string]::IsNullOrWhiteSpace($DataUrl)) { return $false }
    $raw = $DataUrl.Trim().Trim("'").Trim('"')
    $commaIdx = $raw.IndexOf(',')
    if ($commaIdx -lt 0) { return $false }

    $header = $raw.Substring(0, $commaIdx)
    $payload = $raw.Substring($commaIdx + 1)
    if ($header -notmatch '^(?i)data:image\/(jpeg|jpg|png)(;[^,]*)?$') {
        return $false
    }
    if ($header -notmatch '(?i);base64') {
        return $false
    }

    try {
        $payload = $payload -replace '\s+', ''
        if ([string]::IsNullOrWhiteSpace($payload)) { return $false }

        # Certains navigateurs/sources fournissent une variante URL-safe
        # ou percent-encodee; on normalise avant decodage.
        if ($payload -match '%[0-9A-Fa-f]{2}') {
            try { $payload = [System.Web.HttpUtility]::UrlDecode($payload) } catch { }
        }
        if ($payload -match '[-_]' -and $payload -notmatch '[+/]') {
            $payload = $payload.Replace('-', '+').Replace('_', '/')
        }
        $payload = $payload -replace '\s+', ''

        $mod4 = $payload.Length % 4
        if ($mod4 -gt 0) {
            $payload += ('=' * (4 - $mod4))
        }

        $bytes = [Convert]::FromBase64String($payload)
        if ($bytes.Length -lt 8) { return $false }
        [System.IO.File]::WriteAllBytes($OutputFile, $bytes)
        return $true
    } catch {
        return $false
    }
}

function Resolve-DirectImageUrl {
    param([string]$InputUrl)
    if ([string]::IsNullOrWhiteSpace($InputUrl)) { return "" }
    $candidate = $InputUrl.Trim().Trim("'").Trim('"')
    if ($candidate -notmatch '^(?i)https?://') { return $candidate }
    try {
        $uri = [Uri]$candidate
        if ($uri.Host -match '(?i)(^|\.)google\.[^/]+$' -and $uri.AbsolutePath -match '(?i)^/imgres$') {
            $query = [System.Web.HttpUtility]::ParseQueryString($uri.Query)
            $imgUrl = [string]$query.Get("imgurl")
            if (-not [string]::IsNullOrWhiteSpace($imgUrl)) {
                return $imgUrl.Trim()
            }
        }
    } catch { }
    return $candidate
}

if ([string]::IsNullOrWhiteSpace($AlbumPath)) {
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $AlbumPath = (Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8).Trim()
        } catch { }
    }
}

$needTargetRefresh = [string]::IsNullOrWhiteSpace($AlbumPath) -or (-not (Test-Path -LiteralPath $AlbumPath))
if ($needTargetRefresh) {
    # Tente de rafraichir automatiquement la cible si l'etat est vide ou obsolete.
    try {
        $openNext = Join-Path $scriptDir "OpenNextMissingCover.ps1"
        if (Test-Path -LiteralPath $openNext) {
            & $openNext | Out-Null
            if (Test-Path -LiteralPath $stateFile) {
                $refreshed = (Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8).Trim()
                if (-not [string]::IsNullOrWhiteSpace($refreshed) -and (Test-Path -LiteralPath $refreshed)) {
                    $AlbumPath = $refreshed
                }
            }
        }
    } catch { }
}

if ([string]::IsNullOrWhiteSpace($AlbumPath)) {
    throw "AlbumPath manquant. Choisis d'abord l'option 1 (ouvrir le prochain cover manquant)."
}
if (-not (Test-Path -LiteralPath $AlbumPath)) {
    throw "Dossier album introuvable: $AlbumPath`nRelance l'option 1 pour charger une cible valide sur ton clone."
}

if ([string]::IsNullOrWhiteSpace($Url)) {
    try { $Url = [string](Get-Clipboard) } catch { $Url = "" }
}
if (-not [string]::IsNullOrWhiteSpace($Url)) {
    $clipboardValue = $Url.Trim().Trim("'").Trim('"')
    $isLocalPath = $clipboardValue -match '^[A-Za-z]:\\'
    if ($isLocalPath -and (Test-Path -LiteralPath $clipboardValue)) {
        Write-Host "Le presse-papiers contient un chemin local, pas une URL d'image." -ForegroundColor Yellow
        Write-Host "Copie l'adresse directe de l'image (clic droit > Copier l'adresse de l'image)." -ForegroundColor Yellow
        $Url = ""
    }
}
if ([string]::IsNullOrWhiteSpace($Url)) {
    Write-Host "Presse-papiers vide. Colle l'URL de l'image puis Entrée." -ForegroundColor Yellow
    $Url = Read-Host "URL image"
}
if ([string]::IsNullOrWhiteSpace($Url)) {
    throw "URL vide. Copie d'abord l'adresse de l'image (pas la page Google), ou colle-la quand le script la demande."
}
$Url = $Url.Trim().Trim("'").Trim('"')

if (($Url -notmatch '^(?i)data:image\/') -and ($Url -notmatch '^(?i)https?://')) {
    Write-Host "Le presse-papiers ne contient pas une URL web valide." -ForegroundColor Yellow
    $Url = Read-Host "URL image (https://...)"
    $Url = [string]$Url
}
if ([string]::IsNullOrWhiteSpace($Url)) {
    throw "URL vide. Copie d'abord l'adresse de l'image (pas la page Google), ou colle-la quand le script la demande."
}
$Url = $Url.Trim().Trim("'").Trim('"')
if (($Url -notmatch '^(?i)data:image\/') -and ($Url -notmatch '^(?i)https?://')) {
    throw "URL invalide: $Url"
}

$targetFile = Join-Path $AlbumPath "cover.jpg"
$tempFile = Join-Path $env:TEMP ("MusicSelektor_cover_manual_" + [guid]::NewGuid().ToString() + ".img")
$finalTempFile = $tempFile

try {
    Write-WriteActionLog -Action "save-cover-from-url" -Status "start" -SourcePath $Url -TargetPath $targetFile -Details "Begin save attempt"
    $saved = $false
    $Url = Resolve-DirectImageUrl -InputUrl $Url
    if ($Url -match '^(?i)data:image\/') {
        $saved = Save-DataImageUrlToFile -DataUrl $Url -OutputFile $tempFile
        if (-not $saved) {
            throw "Data URL image invalide (base64 non exploitable). Recopie l'image (clic droit > Copier l'adresse de l'image) puis reessaie."
        }
    } else {
        if ($Url -notmatch '^(?i)https?://') {
            throw "URL invalide: $Url"
        }
        if ($Url -match '(?i)^https?://([^/]+\.)?google\.[^/]+/search\?') {
            throw "Tu as colle une page de recherche Google, pas une image. Copie l'adresse directe de l'image (clic droit > Copier l'adresse de l'image)."
        }
        Invoke-WebRequest -Uri $Url -OutFile $tempFile -TimeoutSec 25 -ErrorAction Stop
    }

    # Normalise toujours vers un vrai JPEG pour eviter les boucles "invalid-cover-jpg".
    $detectedFormat = Get-ImageFormatFromMagic -Path $tempFile
    if ($detectedFormat -eq "png") {
        $jpegTemp = Join-Path $env:TEMP ("MusicSelektor_cover_manual_" + [guid]::NewGuid().ToString() + ".jpg")
        $converted = Convert-ImageToJpeg -InputPath $tempFile -OutputPath $jpegTemp
        if (-not $converted) {
            throw "Conversion PNG vers JPEG impossible. Essaie une autre image source."
        }
        $finalTempFile = $jpegTemp
    } elseif ($detectedFormat -eq "jpeg") {
        $finalTempFile = $tempFile
    } else {
        throw "Le fichier image recupere n'est ni PNG ni JPEG valide."
    }

    if (-not (Test-ImageFileDisplayable -Path $finalTempFile)) {
        Write-WriteActionLog -Action "save-cover-from-url" -Status "invalid-image" -SourcePath $Url -TargetPath $targetFile -Details "Downloaded file is not a valid PNG/JPEG"
        throw "Le fichier telecharge n'est pas une image valide (jpg/png)."
    }
    Move-Item -LiteralPath $finalTempFile -Destination $targetFile -Force
    Write-WriteActionLog -Action "save-cover-from-url" -Status "applied" -SourcePath $Url -TargetPath $targetFile -Details "Saved as cover.jpg"
    Write-Output ("OK: cover saved -> {0}" -f $targetFile)
} catch {
    Write-WriteActionLog -Action "save-cover-from-url" -Status "error" -SourcePath $Url -TargetPath $targetFile -Details $_.Exception.Message
    throw
} finally {
    if (Test-Path -LiteralPath $tempFile) {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
    if ($finalTempFile -ne $tempFile -and (Test-Path -LiteralPath $finalTempFile)) {
        Remove-Item -LiteralPath $finalTempFile -Force -ErrorAction SilentlyContinue
    }
}
