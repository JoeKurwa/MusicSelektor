param(
    [int]$TimeoutSeconds = 180
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
        $stamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
        "$stamp script=WatchClipboardAndSaveCover action=$Action status=$Status source=`"$SourcePath`" target=`"$TargetPath`" details=`"$Details`"" | Out-File -LiteralPath $writeLogPath -Encoding UTF8 -Append
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

if (-not (Test-Path -LiteralPath $stateFile)) {
    throw "Cible manquante. Lance d'abord OpenNextMissingCover.ps1 -Open."
}

$albumPath = (Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8).Trim()
if ([string]::IsNullOrWhiteSpace($albumPath) -or -not (Test-Path -LiteralPath $albumPath)) {
    throw "Dossier cible invalide: $albumPath"
}

$targetFile = Join-Path $albumPath "cover.jpg"
$startedAt = Get-Date
$baselineClipboard = ""
try { $baselineClipboard = [string](Get-Clipboard) } catch { $baselineClipboard = "" }

Write-Output ("Auto-save actif ({0}s). Copie l'adresse directe de l'image..." -f $TimeoutSeconds)
Write-Output ("Target: {0}" -f $targetFile)

while (((Get-Date) - $startedAt).TotalSeconds -lt $TimeoutSeconds) {
    Start-Sleep -Milliseconds 900
    $clip = ""
    try { $clip = [string](Get-Clipboard) } catch { $clip = "" }
    if ([string]::IsNullOrWhiteSpace($clip)) { continue }
    if ($clip -eq $baselineClipboard) { continue }
    if ($clip -notmatch '^(?i)https?://') { continue }

    $tempFile = Join-Path $env:TEMP ("MusicSelektor_cover_watch_" + [guid]::NewGuid().ToString() + ".img")
    try {
        Invoke-WebRequest -Uri $clip -OutFile $tempFile -TimeoutSec 20 -ErrorAction Stop
        if (-not (Test-ImageFileDisplayable -Path $tempFile)) {
            Write-WriteActionLog -Action "auto-save-cover" -Status "ignored-non-image" -SourcePath $clip -TargetPath $targetFile -Details "Clipboard URL is not a valid image"
            $baselineClipboard = $clip
            continue
        }
        Move-Item -LiteralPath $tempFile -Destination $targetFile -Force
        Write-WriteActionLog -Action "auto-save-cover" -Status "applied" -SourcePath $clip -TargetPath $targetFile -Details "Saved from clipboard URL"
        Write-Output ("OK: cover saved -> {0}" -f $targetFile)
        exit 0
    } catch {
        Write-WriteActionLog -Action "auto-save-cover" -Status "error" -SourcePath $clip -TargetPath $targetFile -Details $_.Exception.Message
        $baselineClipboard = $clip
    } finally {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Output "Timeout: aucune URL image valide detectee dans le presse-papiers."
exit 2
