param(
    [switch]$IUnderstand
)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, PresentationFramework

# Forcer UTF-8 + caracteres accentues via codes Unicode (evite problemes d'encodage)
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$e = [char]0x00E9   # e accent aigu (e)
$e_grave = [char]0x00E8   # e grave (e)

# Script de detection de doublons pour MusicSelektor
# Détecte les fichiers MP3 dupliqués par hash MD5

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (!$ScriptDir) { $ScriptDir = $PSScriptRoot }
$LibraryPath = Join-Path $ScriptDir "Library.json"
$WriteActionsLogPath = Join-Path $ScriptDir "MusicSelektor.write-actions.log"
$AllowDestructiveOps = [bool]$IUnderstand

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
        "$stamp script=FindDuplicates action=$Action status=$Status source=`"$SourcePath`" target=`"$TargetPath`" details=`"$Details`"" | Out-File -LiteralPath $WriteActionsLogPath -Encoding UTF8 -Append
    } catch { }
}

function Write-FileUtf8Bom {
    param(
        [string]$Path,
        [string]$Content
    )
    try {
        $enc = New-Object System.Text.UTF8Encoding($true) # BOM explicite pour compatibilite Windows/Excel
        [System.IO.File]::WriteAllText($Path, $Content, $enc)
    } catch {
        # fallback minimal
        $Content | Out-File -LiteralPath $Path -Encoding UTF8 -Force
    }
}

function Test-FileExistsSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        return (Test-Path -LiteralPath $Path -ErrorAction Stop)
    } catch {
        try {
            $null = Get-Item -LiteralPath $Path -ErrorAction Stop -Force
            return $true
        } catch {
            return $false
        }
    }
}

function Get-FileHashMD5Safe {
    param([string]$Path)
    if (-not (Test-FileExistsSafe -Path $Path)) { return $null }
    $stream = $null
    $md5 = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hashBytes = $md5.ComputeHash($stream)
        return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
    } catch {
        return $null
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($md5) { $md5.Dispose() }
    }
}

function Get-JsonArraySafe {
    param([string]$RawJson)
    if ([string]::IsNullOrWhiteSpace($RawJson)) { return @() }
    $parsed = ConvertFrom-Json -InputObject $RawJson
    if ($null -eq $parsed) { return @() }
    if ($parsed -is [System.Array]) { return $parsed }
    return @($parsed)
}

# Vérification de l'existence de Library.json
if (-not (Test-Path $LibraryPath)) {
    [System.Windows.MessageBox]::Show("Le fichier Library.json est introuvable.`nVeuillez d'abord scanner votre bibliothèque avec CreateLibrary.ps1", "Erreur", "OK", "Error")
    exit
}

# Chargement de la bibliothèque
try {
    $LibraryRaw = Get-Content $LibraryPath -Raw -Encoding UTF8
    $LibraryData = Get-JsonArraySafe -RawJson $LibraryRaw
    if ($null -eq $LibraryData -or $LibraryData.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Le fichier Library.json est vide ou invalide.`nVeuillez relancer le scan.", "Erreur", "OK", "Error")
        exit 1
    }
    # Log discret (désactiver pour production)
    # Write-Host "Bibliotheque chargee: $($LibraryData.Count) fichiers" -ForegroundColor Green
} catch {
    [System.Windows.MessageBox]::Show("Erreur lors du chargement de Library.json :`n`n$($_.Exception.Message)", "Erreur", "OK", "Error")
    Write-Host "ERREUR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Interface de progression
$ProgressForm = New-Object System.Windows.Forms.Form
$ProgressForm.Size = New-Object System.Drawing.Size(500, 150)
$ProgressForm.StartPosition = "CenterScreen"
$ProgressForm.FormBorderStyle = "FixedDialog"
$ProgressForm.Text = "MusicSelektor by Joe Kurwa - D${e}tection de doublons"
$ProgressForm.TopMost = $true

$ProgressLabel = New-Object System.Windows.Forms.Label
$ProgressLabel.Text = "Analyse des fichiers audio en cours..."
$ProgressLabel.Location = New-Object System.Drawing.Point(20, 20)
$ProgressLabel.AutoSize = $true
$ProgressForm.Controls.Add($ProgressLabel)

$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location = New-Object System.Drawing.Point(20, 60)
$ProgressBar.Size = New-Object System.Drawing.Size(450, 30)
$ProgressBar.Maximum = $LibraryData.Count
$ProgressForm.Controls.Add($ProgressBar)

$ProgressForm.Show()
[System.Windows.Forms.Application]::DoEvents()

# Calcul des hash MD5 pour chaque fichier
$FileHashes = @{}
$Processed = 0
$CandidatesBySize = @{}

# Phase 1: regrouper par taille pour eviter de hasher les fichiers uniques
foreach ($Song in $LibraryData) {
    if ($null -eq $Song -or [string]::IsNullOrWhiteSpace($Song.Path)) {
        $Processed++
        continue
    }

    if (Test-FileExistsSafe -Path $Song.Path) {
        try {
            $fileInfo = Get-Item -LiteralPath $Song.Path -ErrorAction Stop -Force
            $sizeKey = [string]$fileInfo.Length
            if (-not $CandidatesBySize.ContainsKey($sizeKey)) {
                $CandidatesBySize[$sizeKey] = New-Object System.Collections.Generic.List[object]
            }
            $CandidatesBySize[$sizeKey].Add($Song) | Out-Null
        } catch {
            # Fichier inaccessible: ignore
        }
    }

    $Processed++
    if ($ProgressBar.Maximum -gt 0) {
        [void]($ProgressBar.Value = [Math]::Min($Processed, $ProgressBar.Maximum))
    }
    if (($Processed % 25) -eq 0 -or $Processed -eq $LibraryData.Count) {
        $Percent = if ($LibraryData.Count -gt 0) { [math]::Round(($Processed / $LibraryData.Count) * 100, 0) } else { 0 }
        [void]($ProgressLabel.Text = "Preparation: $Processed sur $($LibraryData.Count) fichiers ($Percent`%)")
        [System.Windows.Forms.Application]::DoEvents()
    }
}

$HashCandidatesCount = (($CandidatesBySize.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 } | ForEach-Object { $_.Value.Count } | Measure-Object -Sum).Sum)
if ($null -eq $HashCandidatesCount) { $HashCandidatesCount = 0 }
$ProgressBar.Maximum = [Math]::Max(1, $HashCandidatesCount)
$ProgressBar.Value = 0
$Processed = 0

# Phase 2: hasher uniquement les groupes de meme taille
foreach ($entry in $CandidatesBySize.GetEnumerator()) {
    $group = $entry.Value
    if ($group.Count -le 1) { continue }

    foreach ($Song in $group) {
        $hashString = Get-FileHashMD5Safe -Path $Song.Path
        if ([string]::IsNullOrWhiteSpace($hashString)) {
            $Processed++
            continue
        }

        if (-not $FileHashes.ContainsKey($hashString)) {
            $FileHashes[$hashString] = New-Object System.Collections.Generic.List[PSCustomObject]
        }
        $FileHashes[$hashString].Add($Song)

        $Processed++
        [void]($ProgressBar.Value = [Math]::Min($Processed, $ProgressBar.Maximum))
        if (($Processed % 25) -eq 0 -or $Processed -eq $HashCandidatesCount) {
            $Percent = if ($HashCandidatesCount -gt 0) { [math]::Round(($Processed / $HashCandidatesCount) * 100, 0) } else { 100 }
            [void]($ProgressLabel.Text = "Hash MD5: $Processed sur $HashCandidatesCount fichiers candidats ($Percent`%)")
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
}

$ProgressForm.Close()

# Détection des doublons (hash présent plusieurs fois)
$Duplicates = @{}
foreach ($Hash in $FileHashes.Keys) {
    if ($FileHashes[$Hash].Count -gt 1) {
        $Duplicates[$Hash] = $FileHashes[$Hash]
    }
}

# Création de l'interface de visualisation des doublons
$XamlWindow = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MusicSelektor by Joe Kurwa - Doublons detectes ($($Duplicates.Count) groupes)" Height="700" Width="1200" Background="#121212">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" Text="DOUBLONS DETECTES" Foreground="#4682B4" FontWeight="Bold" FontSize="18" Margin="0,0,0,10"/>
        <TextBlock Grid.Row="0" Name="SummaryText" Text="" Foreground="#888" FontSize="12" Margin="0,25,0,10"/>
        
        <TreeView Grid.Row="1" Name="DuplicatesTreeView" Background="#181818" Foreground="White" BorderThickness="1" BorderBrush="#333">
            <TreeView.Resources>
                <Style TargetType="TreeViewItem">
                    <Setter Property="Foreground" Value="White"/>
                    <Setter Property="FontSize" Value="12"/>
                </Style>
            </TreeView.Resources>
        </TreeView>
        
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,15,0,0">
            <Button Name="ExportBtn" Content="EXPORTER LA LISTE" Width="180" Height="40" Background="#2A2A2A" Foreground="White" Margin="5"/>
            <Button Name="OpenSelectedBtn" Content="OUVRIR L'EMPLACEMENT" Width="210" Height="40" Background="#2A2A2A" Foreground="White" Margin="5"/>
            <Button Name="RefreshBtn" Content="RAFRAICHIR" Width="140" Height="40" Background="#2A2A2A" Foreground="White" Margin="5"/>
            <Button Name="DeleteBtn" Content="SUPPRIMER" Width="120" Height="40" Background="#DC143C" Foreground="White" Margin="5"/>
            <Button Name="CloseBtn" Content="FERMER" Width="120" Height="40" Background="#4682B4" Foreground="White" Margin="5"/>
        </StackPanel>
    </Grid>
</Window>
"@

try {
    $Window = [Windows.Markup.XamlReader]::Load([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($XamlWindow)))
} catch {
    [System.Windows.MessageBox]::Show("Erreur lors du chargement de l'interface : $_", "Erreur", "OK", "Error")
    exit
}

$DuplicatesTreeView = $Window.FindName("DuplicatesTreeView")
$SummaryText = $Window.FindName("SummaryText")
$ExportBtn = $Window.FindName("ExportBtn")
$OpenSelectedBtn = $Window.FindName("OpenSelectedBtn")
$RefreshBtn = $Window.FindName("RefreshBtn")
$DeleteBtn = $Window.FindName("DeleteBtn")
$CloseBtn = $Window.FindName("CloseBtn")

$script:TotalDuplicateFiles = 0
$script:TotalUniqueFiles = 0
$script:TotalWastedSpace = 0

function Get-ExistingDuplicateGroups {
    $updated = @{}
    foreach ($Hash in $Duplicates.Keys) {
        $existing = New-Object System.Collections.Generic.List[object]
        foreach ($Song in $Duplicates[$Hash]) {
            if ($null -eq $Song -or [string]::IsNullOrWhiteSpace([string]$Song.Path)) { continue }
            if (Test-FileExistsSafe -Path $Song.Path) {
                $existing.Add($Song) | Out-Null
            }
        }
        if ($existing.Count -gt 1) {
            $updated[$Hash] = $existing
        }
    }
    return $updated
}

function Update-DuplicatesView {
    param([switch]$ShowRefreshMessage)

    $updated = Get-ExistingDuplicateGroups
    $Duplicates.Clear()
    foreach ($entry in $updated.GetEnumerator()) {
        $Duplicates[$entry.Key] = $entry.Value
    }

    $DuplicatesTreeView.Items.Clear()
    $script:TotalDuplicateFiles = ($Duplicates.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
    if ($null -eq $script:TotalDuplicateFiles) { $script:TotalDuplicateFiles = 0 }
    $script:TotalUniqueFiles = $Duplicates.Count
    $script:TotalWastedSpace = 0

    foreach ($Hash in $Duplicates.Keys | Sort-Object) {
        $Group = $Duplicates[$Hash]
        $GroupNode = New-Object System.Windows.Controls.TreeViewItem
        $GroupNode.Header = "Groupe ($($Group.Count) fichiers) - Hash: $($Hash.Substring(0,8))..."
        $GroupNode.Foreground = "#FF6B6B"
        $GroupNode.FontWeight = "Bold"

        try {
            $FirstFile = Get-Item -LiteralPath $Group[0].Path -ErrorAction SilentlyContinue -Force
            if ($FirstFile) {
                $FileSize = $FirstFile.Length
                $WastedSpace = $FileSize * ($Group.Count - 1)
                $script:TotalWastedSpace += $WastedSpace
                $SizeMB = [math]::Round($FileSize / 1MB, 2)
                $WastedMB = [math]::Round($WastedSpace / 1MB, 2)
                $distinctFolders = @(
                    $Group |
                    ForEach-Object { try { Split-Path -Path $_.Path -Parent } catch { "" } } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Select-Object -Unique
                )
                $folderCount = @($distinctFolders).Count
                $GroupNode.Header = "Groupe ($($Group.Count) fichiers / $folderCount dossier(s)) - $SizeMB MB chacun - $WastedMB MB gaspill${e}s"
            }
        } catch {
            # Ignorer les erreurs de lecture de taille (dates invalides, etc.)
        }

        foreach ($Song in $Group) {
            $SongNode = New-Object System.Windows.Controls.TreeViewItem
            $parentDir = ""
            try { $parentDir = Split-Path -Path $Song.Path -Parent } catch { $parentDir = "" }
            $folderLeaf = ""
            try { $folderLeaf = Split-Path -Path $parentDir -Leaf } catch { $folderLeaf = "" }
            if ([string]::IsNullOrWhiteSpace($folderLeaf)) { $folderLeaf = $parentDir }
            $SongNode.Header = "$($Song.FileName) - $($Song.Album) | Dossier: $folderLeaf"
            $SongNode.Tag = $Song.Path
            $SongNode.ToolTip = "Chemin complet: $($Song.Path)"
            $SongNode.Foreground = "White"
            [void]$GroupNode.Items.Add($SongNode)
        }

        [void]$DuplicatesTreeView.Items.Add($GroupNode)
    }

    $WastedGB = [math]::Round($script:TotalWastedSpace / 1GB, 2)
    $SummaryText.Text = "$($script:TotalUniqueFiles) groupe(s) de doublons detect${e}(s) - $($script:TotalDuplicateFiles) fichier(s) au total - Environ $WastedGB GB d'espace gaspill${e}"
    $Window.Title = "MusicSelektor by Joe Kurwa - Doublons detectes ($($script:TotalUniqueFiles) groupes)"

    if ($ShowRefreshMessage) {
        [System.Windows.MessageBox]::Show(
            "Rafraichissement termine.`n$($script:TotalUniqueFiles) groupe(s) de doublons encore actif(s).",
            "Information",
            "OK",
            "Information"
        )
    }
}

Update-DuplicatesView

function Open-SelectedDuplicateLocation {
    $selected = $DuplicatesTreeView.SelectedItem
    if ($null -eq $selected) {
        [System.Windows.MessageBox]::Show("Selectionnez un fichier dans un groupe de doublons.", "Information", "OK", "Information")
        return
    }

    $path = $selected.Tag
    if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
        if (-not (Test-FileExistsSafe -Path $path)) {
            [System.Windows.MessageBox]::Show("Le fichier selectionne n'existe plus :`n$path", "Fichier introuvable", "OK", "Warning")
            return
        }
        try {
            Start-Process "explorer.exe" -ArgumentList "/select,`"$path`""
            return
        } catch {
            [System.Windows.MessageBox]::Show("Impossible d'ouvrir l'emplacement :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
            return
        }
    }

    # Si l'utilisateur clique le titre du groupe, on ouvre les dossiers distincts du groupe.
    try {
        $groupPaths = @(
            $selected.Items |
            ForEach-Object { $_.Tag } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
        if ($groupPaths.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Aucun fichier exploitable dans ce groupe.", "Information", "OK", "Information")
            return
        }

        $folders = @(
            $groupPaths |
            ForEach-Object { try { Split-Path -Path $_ -Parent } catch { "" } } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
        )
        $openedCount = 0
        foreach ($folder in $folders) {
            if (Test-Path -LiteralPath $folder) {
                Start-Process "explorer.exe" -ArgumentList "`"$folder`""
                $openedCount++
            }
        }
        if ($openedCount -gt 0) {
            [System.Windows.MessageBox]::Show("$openedCount dossier(s) ouvert(s) pour comparaison.", "Information", "OK", "Information")
        }
    } catch {
        [System.Windows.MessageBox]::Show("Impossible d'ouvrir les dossiers du groupe :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
    }
}

# Événements
$ExportBtn.Add_Click({
    Update-DuplicatesView
    $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveDialog.Filter = "Fichier texte (*.txt)|*.txt|Fichier CSV (*.csv)|*.csv"
    $SaveDialog.FileName = "Doublons_MusicSelektor_$(Get-Date -Format 'yyyy-MM-dd').txt"
    
    if ($SaveDialog.ShowDialog() -eq "OK") {
        $currentWastedGB = [math]::Round($script:TotalWastedSpace / 1GB, 2)
        $Output = @()
        $Output += "=== RAPPORT DE DOUBLONS - MusicSelektor ==="
        $Output += "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $Output += "Total groupes: $($script:TotalUniqueFiles)"
        $Output += "Total fichiers: $($script:TotalDuplicateFiles)"
        $Output += "Espace gaspill${e}: $currentWastedGB GB"
        $Output += ""
        $Output += "=" * 60
        $Output += ""
        
        foreach ($Hash in $Duplicates.Keys | Sort-Object) {
            $Group = $Duplicates[$Hash]
            $Output += "GROUPE ($($Group.Count) fichiers):"
            foreach ($Song in $Group) {
                $Output += "  - $($Song.Path)"
            }
            $Output += ""
        }
        
        $ext = [System.IO.Path]::GetExtension($SaveDialog.FileName).ToLowerInvariant()
        if ($ext -eq ".csv") {
            $csvRows = New-Object System.Collections.Generic.List[object]
            foreach ($Hash in $Duplicates.Keys | Sort-Object) {
                $Group = $Duplicates[$Hash]
                foreach ($Song in $Group) {
                    $csvRows.Add([pscustomobject]@{
                        Hash = $Hash
                        FileName = $Song.FileName
                        Album = $Song.Album
                        Path = $Song.Path
                    }) | Out-Null
                }
            }
            $csvText = ($csvRows | ConvertTo-Csv -NoTypeInformation -Delimiter ';') -join "`r`n"
            Write-FileUtf8Bom -Path $SaveDialog.FileName -Content $csvText
        } else {
            $txtContent = ($Output -join "`r`n")
            Write-FileUtf8Bom -Path $SaveDialog.FileName -Content $txtContent
        }
        [System.Windows.MessageBox]::Show("Rapport export${e} avec succ${e_grave}s !", "Succ${e_grave}s", "OK", "Information")
    }
})

$OpenSelectedBtn.Add_Click({
    Open-SelectedDuplicateLocation
})

$RefreshBtn.Add_Click({
    Update-DuplicatesView -ShowRefreshMessage
})

$DuplicatesTreeView.Add_MouseDoubleClick({
    try {
        Open-SelectedDuplicateLocation
    } catch { }
})

$DeleteBtn.Add_Click({
    if (-not $AllowDestructiveOps) {
        Write-WriteActionLog -Action "delete-duplicates" -Status "blocked-safety" -SourcePath "" -TargetPath "" -Details "Missing -IUnderstand"
        [System.Windows.MessageBox]::Show(
            "Mode securite actif.`n`nLa suppression est bloquee tant que le script n'est pas lance avec :`nFindDuplicates.ps1 -IUnderstand",
            "Securite",
            "OK",
            "Warning"
        )
        return
    }

    $Result = [System.Windows.MessageBox]::Show(
        "ATTENTION : Cette action va supprimer les fichiers dupliqués.`n`n" +
        "Pour chaque groupe de doublons, tous les fichiers SAUF LE PREMIER seront supprimés.`n`n" +
        "Voulez-vous vraiment continuer ?",
        "Confirmation de suppression",
        "YesNo",
        "Warning"
    )
    
    if ($Result -eq "Yes") {
        $DeletedCount = 0
        $DeletedSize = 0
        
        foreach ($Hash in $Duplicates.Keys) {
            $Group = $Duplicates[$Hash]
            # Garder le premier, supprimer les autres
            for ($i = 1; $i -lt $Group.Count; $i++) {
                $FileToDelete = $Group[$i].Path
                try {
                    # Utiliser -LiteralPath pour gérer les caractères spéciaux
                    $FileExists = Test-Path -LiteralPath $FileToDelete -ErrorAction SilentlyContinue
                    if (-not $FileExists) {
                        # Essayer avec Get-Item si Test-Path échoue (dates invalides)
                        try {
                            $null = Get-Item -LiteralPath $FileToDelete -ErrorAction Stop -Force
                            $FileExists = $true
                        } catch {
                            $FileExists = $false
                        }
                    }
                    
                    if ($FileExists) {
                        try {
                            $FileInfo = Get-Item -LiteralPath $FileToDelete -Force
                            $DeletedSize += $FileInfo.Length
                            Remove-Item -LiteralPath $FileToDelete -Force
                            Write-WriteActionLog -Action "delete-duplicates" -Status "applied" -SourcePath $FileToDelete -TargetPath "" -Details "Delete duplicate"
                            $DeletedCount++
                        } catch {
                            Write-WriteActionLog -Action "delete-duplicates" -Status "error" -SourcePath $FileToDelete -TargetPath "" -Details $_.Exception.Message
                            Write-Warning "Impossible de supprimer : $FileToDelete - $($_.Exception.Message)"
                        }
                    }
                } catch {
                    Write-Warning "Erreur lors de la vérification : $FileToDelete - $($_.Exception.Message)"
                }
            }
        }
        
        $DeletedGB = [math]::Round($DeletedSize / 1GB, 2)
        [System.Windows.MessageBox]::Show(
            "Suppression terminée !`n`n" +
            "Fichiers supprimés : $DeletedCount`n" +
            "Espace libéré : $DeletedGB GB`n`n" +
            "Pensez à relancer le scan pour mettre à jour la bibliothèque.",
            "Suppression terminée",
            "OK",
            "Information"
        )
        
        $Window.Close()
    }
})

$CloseBtn.Add_Click({
    $Window.Close()
})

# Affichage de la fenêtre
$Window.ShowDialog() | Out-Null
