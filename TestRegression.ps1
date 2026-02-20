param(
    [switch]$NoCleanupSmoke
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PSScriptRoot }

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Add-Warning {
    param([string]$Message)
    $warnings.Add($Message) | Out-Null
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Add-Pass {
    param([string]$Message)
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

Write-Host "=== MusicSelektor Regression Checks ===" -ForegroundColor Cyan
Write-Host ""

# 1) Fichiers critiques
$requiredFiles = @(
    "MusicSelektor.bat",
    "SCANNER.bat",
    "CreateLibrary.ps1",
    "MusicPlayer.ps1",
    "MusicPlayerGUI.xaml",
    "FindDuplicates.ps1",
    "NormalizeTrackNames.ps1",
    "CleanupWorkspaceArtifacts.ps1",
    "MusicSelektor_config.json"
)

foreach ($name in $requiredFiles) {
    $full = Join-Path $scriptDir $name
    if (Test-Path -LiteralPath $full) {
        Add-Pass "Fichier present: $name"
    } else {
        Add-Failure "Fichier manquant: $name"
    }
}

Write-Host ""

# 2) Verification syntaxe PowerShell
$ps1Files = Get-ChildItem -LiteralPath $scriptDir -File -Filter "*.ps1" -ErrorAction SilentlyContinue
foreach ($file in $ps1Files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $short = ($errors | Select-Object -First 1).Message
        Add-Failure "Syntaxe invalide dans $($file.Name): $short"
    } else {
        Add-Pass "Syntaxe OK: $($file.Name)"
    }
}

Write-Host ""

# 3) Chargement XAML principal
try {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    $xamlPath = Join-Path $scriptDir "MusicPlayerGUI.xaml"
    $xaml = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $null = [Windows.Markup.XamlReader]::Load($reader)
    Add-Pass "XAML charge correctement (MusicPlayerGUI.xaml)"
} catch {
    Add-Failure "XAML invalide (MusicPlayerGUI.xaml): $($_.Exception.Message)"
}

Write-Host ""

# 4) Regles de securite (scripts sensibles)
$findDupPath = Join-Path $scriptDir "FindDuplicates.ps1"
$normPath = Join-Path $scriptDir "NormalizeTrackNames.ps1"

try {
    $findDupText = Get-Content -LiteralPath $findDupPath -Raw -Encoding UTF8
    if ($findDupText -match '\[switch\]\$IUnderstand' -and
        $findDupText -match 'blocked-safety' -and
        $findDupText -match 'delete-duplicates') {
        Add-Pass "Securite doublons presente (IUnderstand + blocage)"
    } else {
        Add-Failure "Regles securite doublons incomplètes"
    }
} catch {
    Add-Failure "Lecture impossible FindDuplicates.ps1: $($_.Exception.Message)"
}

try {
    $normText = Get-Content -LiteralPath $normPath -Raw -Encoding UTF8
    if ($normText -match '\[switch\]\$IUnderstand' -and
        $normText -match '\$effectiveApply\s*=\s*\(\$Apply\s*-and\s*\$IUnderstand\)' -and
        $normText -match 'blocked-safety') {
        Add-Pass "Securite normalisation presente (IUnderstand + blocage)"
    } else {
        Add-Failure "Regles securite normalisation incomplètes"
    }
} catch {
    Add-Failure "Lecture impossible NormalizeTrackNames.ps1: $($_.Exception.Message)"
}

Write-Host ""

# 5) Config release (anti-bruit)
$cfgPath = Join-Path $scriptDir "MusicSelektor_config.json"
try {
    $cfgRaw = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8
    $cfg = $cfgRaw | ConvertFrom-Json

    if ($cfg.PSObject.Properties.Name -contains "DebugMode") {
        if ([bool]$cfg.DebugMode -eq $false) {
            Add-Pass "Config release: DebugMode=false"
        } else {
            Add-Warning "DebugMode=true (utilisable en dev, bruyant en release)"
        }
    } else {
        Add-Warning "Cle DebugMode absente dans MusicSelektor_config.json"
    }

    if ($cfg.PSObject.Properties.Name -contains "NetworkTraceEnabled") {
        if ([bool]$cfg.NetworkTraceEnabled -eq $false) {
            Add-Pass "Config release: NetworkTraceEnabled=false"
        } else {
            Add-Warning "NetworkTraceEnabled=true (utilisable en dev, bruyant en release)"
        }
    } else {
        Add-Warning "Cle NetworkTraceEnabled absente dans MusicSelektor_config.json"
    }
} catch {
    Add-Failure "Config invalide MusicSelektor_config.json: $($_.Exception.Message)"
}

Write-Host ""

# 6) Smoke test cleanup (mode non destructif)
if (-not $NoCleanupSmoke) {
    try {
        & (Join-Path $scriptDir "CleanupWorkspaceArtifacts.ps1") -KeepLatest 5 | Out-Null
        Add-Pass "Smoke cleanup OK (sans suppression d'historique)"
    } catch {
        Add-Failure "Smoke cleanup KO: $($_.Exception.Message)"
    }
} else {
    Add-Warning "Smoke cleanup ignore (NoCleanupSmoke)"
}

Write-Host ""

# 7) Non-regression UI / lecture (features recentes)
try {
    $playerPath = Join-Path $scriptDir "MusicPlayer.ps1"
    $xamlPath = Join-Path $scriptDir "MusicPlayerGUI.xaml"
    $playerText = Get-Content -LiteralPath $playerPath -Raw -Encoding UTF8
    $xamlText = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8

    if ($xamlText -match 'Name="OpenFolderBtn".*Content="LECTURE/PAUSE"') {
        Add-Pass "UI: bouton LECTURE/PAUSE present"
    } else {
        Add-Failure "UI: bouton LECTURE/PAUSE absent"
    }

    if ($playerText -match 'function Set-NowPlayingCoverFromTrackPath' -and
        $playerText -match 'Set-NowPlayingCoverFromTrackPath\s+-TrackPath') {
        Add-Pass "Lecture: rafraichissement pochette sur changement de piste"
    } else {
        Add-Failure "Lecture: rafraichissement pochette manquant"
    }

    if ($playerText -match 'function Set-MusicListSort' -and
        $playerText -match 'MusicList sort:') {
        Add-Pass "UI: tri de la liste pistes par clic en-tete"
    } else {
        Add-Failure "UI: tri de la liste pistes manquant"
    }

    if ($playerText -match 'function Remove-TrackFiles' -and
        $playerText -match 'Supprimer la/les piste\(s\) selectionnee\(s\)') {
        Add-Pass "UI: suppression de pistes via clic droit presente"
    } else {
        Add-Failure "UI: suppression de pistes via clic droit absente"
    }
} catch {
    Add-Failure "Non-regression UI/lecture: lecture impossible des fichiers: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "=== Resultat ===" -ForegroundColor Cyan
Write-Host ("Echecs : {0}" -f $failures.Count) -ForegroundColor Red
Write-Host ("Warnings : {0}" -f $warnings.Count) -ForegroundColor Yellow

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
