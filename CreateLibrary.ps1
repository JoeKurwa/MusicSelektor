param([switch]$Rescan)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (!$ScriptDir) { $ScriptDir = $PSScriptRoot }
$ExportPath = Join-Path $ScriptDir "Library.json"
$ConfigPath = Join-Path $ScriptDir "MusicSelektor_config.json"

function Test-FileAccessible {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    # 1) Test provider (robuste avec -LiteralPath)
    try {
        if (Test-Path -LiteralPath $Path -ErrorAction Stop) { return $true }
    } catch { }

    # 2) Fallback .NET (evite certains faux negatifs PowerShell)
    try {
        if ([System.IO.File]::Exists($Path)) { return $true }
    } catch { }

    # 3) Dernier recours via Get-Item
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return ($null -ne $item -and -not $item.PSIsContainer)
    } catch { }

    return $false
}

# --- INTERFACE ---
$Anchor = New-Object System.Windows.Forms.Form
$Anchor.Size = New-Object System.Drawing.Size(400, 150)
$Anchor.StartPosition = "CenterScreen"
$Anchor.FormBorderStyle = "FixedDialog"
$Anchor.Text = "MusicSelektor by Joe Kurwa - Indexation"
$Anchor.TopMost = $true

$Label = New-Object System.Windows.Forms.Label
$Label.Text = "Veuillez choisir votre dossier Musique..."
$Label.Location = New-Object System.Drawing.Point(20, 20)
$Label.AutoSize = $true
$Anchor.Controls.Add($Label)

$Bar = New-Object System.Windows.Forms.ProgressBar
$Bar.Location = New-Object System.Drawing.Point(20, 60)
$Bar.Size = New-Object System.Drawing.Size(340, 30)
$Anchor.Controls.Add($Bar)

# --- CHOIX DU DOSSIER (ou re-scan du meme dossier) ---
$SelectedPath = $null
if ($Rescan) {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Write-Host "ERREUR: Re-scan impossible - aucun scan precedent (config absente)." -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show("Aucun dossier de scan enregistre.`nLancez d'abord un scan normal (SCANNER.bat) et selectionnez votre dossier racine.", "Re-scan impossible", "OK", "Warning")
        exit 1
    }
    try {
        $Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $lastPath = [string]$Config.LastScanPath
        if ([string]::IsNullOrWhiteSpace($lastPath) -or -not (Test-Path -LiteralPath $lastPath)) {
            Write-Host "ERREUR: Re-scan impossible - dossier precedent introuvable ou invalide." -ForegroundColor Red
            [System.Windows.Forms.MessageBox]::Show("Le dossier enregistre n'existe plus ou est invalide.`nRelancez un scan normal (SCANNER.bat) et selectionnez votre dossier racine.", "Re-scan impossible", "OK", "Warning")
            exit 1
        }
        $SelectedPath = $lastPath
        Write-Host "Re-scan du meme dossier: $SelectedPath" -ForegroundColor Cyan
    } catch {
        Write-Host "ERREUR: Re-scan - config invalide: $($_.Exception.Message)" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show("Configuration invalide. Relancez un scan normal (SCANNER.bat).", "Re-scan impossible", "OK", "Warning")
        exit 1
    }
}

if (-not $SelectedPath) {
    $FolderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderDialog.Description = "Selectionnez votre dossier racine de MUSIQUE"
    $FolderDialog.ShowNewFolderButton = $false

    if (Test-Path $ConfigPath) {
        try {
            $Config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($Config.LastScanPath -and (Test-Path $Config.LastScanPath)) {
                $FolderDialog.SelectedPath = $Config.LastScanPath
            }
        } catch { }
    }

    Write-Host "Ouverture de la fenetre de selection de dossier..." -ForegroundColor Cyan
    Write-Host "Veuillez selectionner votre dossier et cliquer sur OK UNE SEULE FOIS." -ForegroundColor Yellow

    $Label.Text = "Ouverture de la fenetre de selection..."
    $Anchor.Show()
    $Anchor.Activate()
    [System.Windows.Forms.Application]::DoEvents()

    $Result = $FolderDialog.ShowDialog($Anchor)
    Write-Host "Resultat du dialogue: $Result" -ForegroundColor Cyan

    if ($Result.ToString() -eq "OK" -or $Result -eq 1) {
        $SelectedPath = $FolderDialog.SelectedPath
    }
}

if ($SelectedPath) {
    if ([string]::IsNullOrWhiteSpace($SelectedPath)) {
        Write-Host "ERREUR: Aucun dossier selectionne!" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show("Aucun dossier n'a ete selectionne.`nLe scan ne peut pas continuer.", "Erreur", "OK", "Error")
        exit 1
    }

    Write-Host "Dossier selectionne: $SelectedPath" -ForegroundColor Green
    Write-Host "Demarrage du scan..." -ForegroundColor Cyan

    $Anchor.Show()
    $Anchor.Activate()
    $Label.Text = "Analyse en cours..."

    try {
        # Recherche de TOUS les fichiers audio, y compris ceux de recuperation avec noms de hash
        # Le but est de detecter les doublons meme si les noms sont differents
        $AudioExtensions = @(".mp3", ".m4a", ".flac", ".wav")
        Write-Host "Recherche des fichiers audio dans: $SelectedPath" -ForegroundColor Cyan
        $Files = Get-ChildItem -Path $SelectedPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $null -ne $_ -and $null -ne $_.FullName -and ($AudioExtensions -contains $_.Extension.ToLowerInvariant()) }
        Write-Host "Recherche terminee." -ForegroundColor Green
    } catch {
        $Anchor.Close()
        $ErrorMessage = "Erreur lors de la lecture du dossier :`n`n$($_.Exception.Message)`n`nLigne: $($_.InvocationInfo.ScriptLineNumber)"
        [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Erreur", "OK", "Error")
        Write-Host "ERREUR: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    
    $Total = $Files.Count
    
    if ($Total -eq 0) {
        $Anchor.Close()
        [System.Windows.Forms.MessageBox]::Show("Aucun fichier audio trouve dans le dossier selectionne.`n`nFormats supportes: MP3, M4A, FLAC, WAV`n`nVerifiez que le dossier contient des fichiers audio.", "Aucun fichier", "OK", "Warning")
        exit 1
    }
    
    Write-Host "Fichiers audio trouves: $Total (y compris fichiers de recuperation)" -ForegroundColor Green
    
    $Bar.Maximum = $Total
    $Bar.Minimum = 0
    $Bar.Value = 0
    
    $Songs = New-Object System.Collections.Generic.List[PSCustomObject]
    $ErrorCount = 0
    
    for ($i = 0; $i -lt $Total; $i++) {
        try {
            $File = $Files[$i]
            if ($null -eq $File) { 
                $ErrorCount++
                $ProcessedCount = $i + 1
                $Bar.Value = $ProcessedCount
                if (($ProcessedCount % 25) -eq 0 -or $ProcessedCount -eq $Total) {
                    $Label.Text = "Traitement: $ProcessedCount / $Total fichiers | Indexes: $($Songs.Count) | Ignores: $ErrorCount"
                    [System.Windows.Forms.Application]::DoEvents()
                }
                continue 
            }
            
            # GCI renvoie deja un FileInfo: on evite un Get-Item supplementaire par fichier.
            # On garde un test d'accessibilite robuste (provider + .NET + Get-Item fallback)
            # pour eviter les faux "fichier inaccessible".
            $FileInfo = $File
            $FileExists = Test-FileAccessible -Path $FileInfo.FullName

            if (-not $FileExists) {
                $ErrorCount++
                Write-Host "Fichier inaccessible: $($File.Name) | $($FileInfo.FullName)" -ForegroundColor Yellow
                $ProcessedCount = $i + 1
                $Bar.Value = $ProcessedCount
                if (($ProcessedCount % 25) -eq 0 -or $ProcessedCount -eq $Total) {
                    $Label.Text = "Traitement: $ProcessedCount / $Total fichiers | Indexes: $($Songs.Count) | Ignores: $ErrorCount"
                    [System.Windows.Forms.Application]::DoEvents()
                }
                continue
            }

            $ActualFile = $FileInfo
            
            $ParentFolder = $ActualFile.DirectoryName
            if ([string]::IsNullOrWhiteSpace($ParentFolder)) { 
                $ErrorCount++
                $ProcessedCount = $i + 1
                $Bar.Value = $ProcessedCount
                if (($ProcessedCount % 25) -eq 0 -or $ProcessedCount -eq $Total) {
                    $Label.Text = "Traitement: $ProcessedCount / $Total fichiers | Indexes: $($Songs.Count) | Ignores: $ErrorCount"
                    [System.Windows.Forms.Application]::DoEvents()
                }
                continue 
            }
            
            # Détecter si c'est un fichier de récupération (nom = hash)
            $IsRecoveryFile = $false
            $FileName = $ActualFile.BaseName
            if ($FileName -match '^[a-f0-9]{32}$' -or $FileName -match '^[a-f0-9]{40}$' -or $FileName -match '^[a-f0-9]{64}$') {
                $IsRecoveryFile = $true
            }
            
            # Ajouter TOUS les fichiers, même ceux de récupération
            # Le système de détection de doublons par hash MD5 les identifiera
            try {
                $Songs.Add([PSCustomObject]@{
                    ScanRoot = $SelectedPath
                    FullDir  = $ParentFolder
                    FileName = $ActualFile.Name
                    Title    = if ($IsRecoveryFile) { "[RECUP] $FileName" } else { $ActualFile.BaseName }
                    Album    = Split-Path $ParentFolder -Leaf
                    Path     = $ActualFile.FullName
                    IsRecovery = $IsRecoveryFile
                })
            } catch {
                $ErrorCount++
                Write-Host "ERREUR lors de l'ajout du fichier $i ($($ActualFile.Name)) : $($_.Exception.Message)" -ForegroundColor Yellow
                $ProcessedCount = $i + 1
                $Bar.Value = $ProcessedCount
                if (($ProcessedCount % 25) -eq 0 -or $ProcessedCount -eq $Total) {
                    $Label.Text = "Traitement: $ProcessedCount / $Total fichiers | Indexes: $($Songs.Count) | Ignores: $ErrorCount"
                    [System.Windows.Forms.Application]::DoEvents()
                }
                continue
            }

            $ProcessedCount = $i + 1
            if (($ProcessedCount % 25) -eq 0 -or $ProcessedCount -eq $Total) { 
                $Bar.Value = $ProcessedCount
                $Label.Text = "Traitement: $ProcessedCount / $Total fichiers | Indexes: $($Songs.Count) | Ignores: $ErrorCount"
                [System.Windows.Forms.Application]::DoEvents()
            }
        } catch {
            $ErrorCount++
            $FileName = if ($File) { $File.Name } else { "inconnu" }
            Write-Host "ERREUR fichier $i ($FileName) : $($_.Exception.Message)" -ForegroundColor Yellow
            $ProcessedCount = $i + 1
            $Bar.Value = $ProcessedCount
            if (($ProcessedCount % 25) -eq 0 -or $ProcessedCount -eq $Total) {
                $Label.Text = "Traitement: $ProcessedCount / $Total fichiers | Indexes: $($Songs.Count) | Ignores: $ErrorCount"
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
    }
    
    $ValidFiles = $Songs.Count
    $RecoveryFiles = ($Songs | Where-Object { $_.IsRecovery }).Count
    $AlbumsCount = ($Songs | Select-Object -ExpandProperty FullDir -Unique).Count
    
    # Affichage des statistiques détaillées
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  STATISTIQUES DU SCAN" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Fichiers audio trouves: $Total" -ForegroundColor White
    Write-Host "Fichiers indexes avec succes: $ValidFiles" -ForegroundColor Green
    if ($ErrorCount -gt 0) {
        Write-Host "Fichiers ignores (erreurs): $ErrorCount" -ForegroundColor Yellow
        Write-Host "  Causes: fichiers introuvables, dates invalides, caracteres speciaux" -ForegroundColor Gray
    }
    Write-Host "Albums detectes: $AlbumsCount" -ForegroundColor Cyan
    if ($RecoveryFiles -gt 0) {
        Write-Host "Fichiers de recuperation: $RecoveryFiles" -ForegroundColor Magenta
        Write-Host "  (Ces fichiers seront identifies comme doublons si identiques)" -ForegroundColor Gray
    }
    $SuccessRate = if ($Total -gt 0) { [math]::Round(($ValidFiles / $Total) * 100, 1) } else { 0 }
    Write-Host "Taux de reussite: $SuccessRate%" -ForegroundColor $(if ($SuccessRate -gt 90) { "Green" } elseif ($SuccessRate -gt 70) { "Yellow" } else { "Red" })
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Mise à jour finale de la barre et du libelle (coherent pour l'utilisateur)
    $Bar.Value = $Total
    $Label.Text = "Analyse terminee: $Total / $Total fichiers traites | Indexes: $ValidFiles | Ignores: $ErrorCount"
    [System.Windows.Forms.Application]::DoEvents()

    # --- EXPORT FINAL ---
    try {
        Write-Host ""
        Write-Host "Sauvegarde dans Library.json..." -ForegroundColor Cyan
        
        if ($Songs.Count -eq 0) {
            $Anchor.Close()
            Write-Host "ERREUR: Aucun fichier a sauvegarder!" -ForegroundColor Red
            [System.Windows.Forms.MessageBox]::Show("Aucun fichier n'a pu etre indexe.`nLe fichier Library.json ne sera pas cree.", "Erreur", "OK", "Error")
            exit 1
        }
        
        $Songs | ConvertTo-Json -Depth 5 | Out-File $ExportPath -Encoding UTF8 -Force
        
        # Vérifier que le fichier a bien été créé
        if (-not (Test-Path $ExportPath)) {
            throw "Le fichier Library.json n'a pas pu etre cree."
        }
        
        # Calculer la taille du fichier
        $FileSize = (Get-Item $ExportPath).Length / 1MB
        $FileSizeFormatted = "{0:N2}" -f $FileSize
        
        $Anchor.Close()
        
        # Mémoriser le dossier pour le prochain scan en preservant les autres clefs config.
        try {
            $configMap = [ordered]@{}
            if (Test-Path -LiteralPath $ConfigPath) {
                try {
                    $existingCfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($existingCfg) {
                        foreach ($p in $existingCfg.PSObject.Properties) {
                            $configMap[$p.Name] = $p.Value
                        }
                    }
                } catch { }
            }
            if (-not $configMap.Contains("DebugMode")) { $configMap["DebugMode"] = $true }
            $configMap["LastScanPath"] = $SelectedPath
            $configMap | ConvertTo-Json | Out-File $ConfigPath -Encoding UTF8 -Force
        } catch { }
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  SCAN TERMINE AVEC SUCCES!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Fichier cree: Library.json ($FileSizeFormatted MB)" -ForegroundColor White
        Write-Host "Vous pouvez maintenant utiliser le lecteur pour visualiser" -ForegroundColor White
        Write-Host "votre bibliotheque et detecter les doublons." -ForegroundColor White
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        
        Write-Host "Code de sortie: 0 (succes)" -ForegroundColor Green
        exit 0
    } catch {
        $Anchor.Close()
        $ErrorMessage = "Erreur lors de la creation de Library.json :`n`n$($_.Exception.Message)`n`nLigne: $($_.InvocationInfo.ScriptLineNumber)"
        [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Erreur", "OK", "Error")
        Write-Host "ERREUR: Impossible de creer Library.json" -ForegroundColor Red
        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Ligne: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
        Write-Host "Code de sortie: 1 (echec)" -ForegroundColor Red
        exit 1
    }
} else {
    # L'utilisateur a annulé la sélection ou fermé la fenêtre
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  SCAN ANNULE" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "Vous avez annule la selection du dossier." -ForegroundColor Yellow
    Write-Host "Le scan n'a pas ete effectue." -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
