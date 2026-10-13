# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Règles de travail (demandées par le propriétaire du projet)

- Réponds en français.
- **Enregistre tout** : tout changement est commité (convention plus bas) puis poussé sur la branche de travail avant de rendre la main. Une session cloud est éphémère : ce qui n'est pas poussé est perdu.
- **Erreurs** : quand une erreur est signalée, corrige-la, puis ajoute-la au [Journal des erreurs](#journal-des-erreurs) en fin de fichier, dans le même commit. Relis ce journal avant chaque tâche : une erreur consignée ne doit jamais se reproduire.
- Dis toujours ce qui a été vérifié et ce qui ne l'a pas été (voir « Environnement cloud »).

## Le projet

Application Windows uniquement : Windows PowerShell 5.1 + WPF/WinForms, sans build ni dépendance. Les scripts s'exécutent tels quels depuis le dossier du dépôt ; les `.bat` sont les points d'entrée utilisateur. Interface, messages, docs et commits sont en français.

## Commandes (Windows)

```powershell
.\MusicSelektor.bat          # scan si Library.json absent, puis ouvre le lecteur (MusicPlayer.ps1, fenêtre cachée)
.\SCANNER.bat                # scan seul : CreateLibrary.ps1, lancé en -STA (dialogue de dossier WinForms)
.\RESCAN_SAME.bat            # CreateLibrary.ps1 -Rescan : réutilise LastScanPath de la config
.\FIND_DUPLICATES.bat        # FindDuplicates.ps1 (suppression bloquée sans -IUnderstand)
.\RUN_REGRESSION_CHECKS.bat  # = TestRegression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\TestRegression.ps1 -NoCleanupSmoke
```

- Pas de framework de test : `TestRegression.ps1` est un script unique (fichiers requis, syntaxe et encodage de chaque `.ps1`, chargement du XAML, garde-fous de sécurité, config release, smoke test du nettoyage, regex de non-régression UI). On ne peut pas y lancer un contrôle isolé ; `-NoCleanupSmoke` saute le smoke test, qui déplace réellement des fichiers vers `reports/`.
- Il exige `MusicSelektor_config.json`, ignoré par git et créé par le premier scan : sur un clone neuf, il échoue tant qu'aucun scan n'a tourné. En release, `DebugMode` et `NetworkTraceEnabled` doivent valoir `false` (sinon warnings), alors que `CreateLibrary.ps1` écrit `DebugMode: true` quand la clé est absente.

## Environnement cloud (claude.ai/code, conteneur Linux)

- Ni Windows, ni WPF, ni `.bat` : impossible de lancer l'app. Ne jamais présenter comme testé ce qui n'a pas tourné sous Windows.
- Contrôle minimal possible avec PowerShell 7, installé hors du dépôt :
  ```bash
  PWSH_DIR=~/.local/pwsh && mkdir -p "$PWSH_DIR"
  curl -sSL https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/powershell-7.4.6-linux-x64.tar.gz | tar -xz -C "$PWSH_DIR"
  chmod +x "$PWSH_DIR/pwsh"   # l'archive ne conserve pas le bit exécutable
  "$PWSH_DIR/pwsh" -NoProfile -File ./TestRegression.ps1 -NoCleanupSmoke
  ```
  Trois échecs sont attendus hors Windows (`MusicSelektor_config.json` absent, compté deux fois, et XAML/WPF indisponible) ; tout le reste doit être `[OK]`. Le parseur de PowerShell 7 accepte une syntaxe que 5.1 refuse : ce contrôle ne prouve pas la compatibilité 5.1.
- Pour piloter le PC Windows depuis le téléphone : Remote Control, à lancer **sur le PC** dans le dossier du projet (`claude --rc` ou `claude remote-control`, ou `/rc` dans une session déjà ouverte). La forme `claude rc` n'est pas documentée.

## Architecture

- **Flux de données** : `CreateLibrary.ps1` parcourt le dossier racine (`.mp3 .m4a .flac .wav`) et écrit `Library.json`, un tableau plat `{ScanRoot, FullDir, FileName, Title, Album, Path, IsRecovery}` (album = dossier parent ; `IsRecovery` = nom de fichier qui est un hash), et mémorise `LastScanPath` dans `MusicSelektor_config.json`. `Library.json` n'est réécrit que par un scan et par la suppression de pistes dans la GUI (`Remove-TrackFiles` retire les entrées). Tout autre changement de fichiers (ajouts, renommages par `NormalizeTrackNames.ps1`, doublons supprimés) exige un re-scan puis « ACTUALISER LA BIBLIOTHÈQUE ».
- **`MusicPlayer.ps1`** (~2200 lignes, monolithique) charge `MusicPlayerGUI.xaml` avec `XamlReader`, puis récupère les contrôles par `$Window.FindName("...")`. Les attributs `Name=` du XAML sont donc un contrat : renommer un contrôle impose de modifier les deux fichiers. L'état vit dans des variables `$Script:` et `$global:` (`RawData`, `AlbumsIndex`, `ScanRoot`). Lecture externe par défaut (`Start-Process` sur le fichier audio) ; lecteur WPF `MediaPlayer` seulement si `InternalPlayerEnabled: true` dans la config, avec repli sur l'externe en cas d'erreur.
- **Pochettes = fichiers image par dossier**, jamais dans les métadonnées. `Get-AlbumCoverFile` cherche `cover`, `folder`, `album`, `artwork`, `front` puis `<nom du dossier>` (`.jpg`, `.png`, `.jpeg`) dans le dossier de l'album, son parent et les dossiers frères `Jaquette`/`Covers`/`Artwork`. En dernier recours, il prend la plus grosse image sur un niveau de profondeur. L'enregistrement se fait toujours en `cover.jpg`. Recherche en ligne : API iTunes Search, puis MusicBrainz + Cover Art Archive, avec le cache `CoverSearchCache.json`, au moins 250 ms entre requêtes et des lots de 75 albums. Les images sont chargées en mémoire (`ReadAllBytes` + `OnLoad`) : `cover.jpg` reste remplaçable pendant que l'app tourne.
- **Code dupliqué, pas de module partagé** : chaque `.ps1` est autonome. Tout le moteur de pochettes existe en double dans `MusicPlayer.ps1` (GUI) et `AutoCoverBatch.ps1` (CLI), et `Write-WriteActionLog` en 5 copies. Une correction dans une copie doit être reportée dans les autres.
- **Circuit manuel des pochettes** (menu `ASSISTANT_POCHETTES.bat`) :
  1. `OpenNextMissingCover.ps1` choisit le prochain album sans `cover.jpg` valide, à partir des CSV de revue de `reports/manual-cover/`, ou à défaut du dernier rapport `not-found` d'`AutoCoverBatch.ps1` dans `reports/auto-cover/`.
  2. Il mémorise la cible dans `.next-cover-target.txt` et ouvre le navigateur.
  3. `SaveCoverFromClipboardUrl.ps1` lit cette cible et enregistre en `cover.jpg` l'URL ou la data URL copiée dans le presse-papiers. Le bouton « APPLIQUER COVER » de la GUI appelle le même script avec `-AlbumPath`.
  4. `VerifyManualCovers.ps1` fait le bilan.
- **Garde-fous** : les scripts qui modifient des fichiers tournent en aperçu par défaut. L'action réelle exige `-Apply -IUnderstand` (`-IUnderstand` seul pour `FindDuplicates.ps1`). Une tentative sans ce flag est journalisée `blocked-safety`. Ces scripts tracent leurs écritures dans `MusicSelektor.write-actions.log` (`script=... action=... status=...`). La suppression depuis la GUI passe par la Corbeille, mais `FindDuplicates.ps1 -IUnderstand` supprime définitivement (`Remove-Item -Force`).
- **Chaînes vérifiées par regex dans `TestRegression.ps1`** (ne pas les renommer sans mettre à jour le test) :
  - `Name="OpenFolderBtn"` suivi de `Content="LECTURE/PAUSE"` sur la même ligne du XAML ;
  - `function Set-NowPlayingCoverFromTrackPath`, appelée avec `-TrackPath` ;
  - `function Set-MusicListSort` et le texte `MusicList sort:` ;
  - `function Remove-TrackFiles` et le texte `Supprimer la/les piste(s) selectionnee(s)` ;
  - `[switch]$IUnderstand`, `blocked-safety`, `delete-duplicates` et `$effectiveApply = ($Apply -and $IUnderstand)`.

## Conventions et pièges

- **PowerShell 5.1 strict** : rien de propre à PowerShell 7 (`? :`, `??`, `?.`, `&&`/`||`, `-Parallel`). L'app tourne sous `powershell.exe`.
- **Encodage** : les `.ps1` sont en UTF-8 **sans BOM**, que PowerShell 5.1 lit en ANSI. Aucun caractère non ASCII hors commentaires dans un `.ps1`, et `TestRegression.ps1` le refuse : écrire le français sans accents comme le reste du code, ou utiliser `[char]0x00E9` (cf. `FindDuplicates.ps1`). Pour un emoji, utiliser `[char]::ConvertFromUtf32(0x1F916)` (cf. `MusicPlayer.ps1`). Le XAML est lu en UTF-8, donc accents et emoji y fonctionnent. Aucun caractère non ASCII non plus dans les `.bat`, que `cmd.exe` affiche selon la page de code OEM ; `TestRegression.ps1` le vérifie aussi.
- Fins de ligne CRLF pour `.ps1`/`.bat`/`.xaml`, LF pour `.md` (`.gitattributes`) ; indentation de 4 espaces.
- Chemins de musique : toujours `-LiteralPath`, car les noms contiennent souvent `[ ]`. Les scripts trouvent leurs fichiers depuis leur propre dossier (`Split-Path -Parent $MyInvocation.MyCommand.Definition`) : ils doivent rester à la racine.
- Fichiers générés, ignorés par git : `Library.json`, `MusicSelektor_config.json`, `CoverSearchCache.json`, `AutoCoverReport.json`, `*.log`, `reports/`. Exception : `LastAutoCoverTiming.json` est versionné mais réécrit par l'app après chaque recherche auto ; ne pas committer ces changements.
- Release :
  - Mettre à jour `CHANGELOG.md` et `RELEASE_NOTES_x.y.z.md`.
  - `AUTOMATE_GITHUB_RELEASE.ps1` commite, pousse sur `main` et tague (par défaut `v1.2.0`, codé en dur) : ne jamais le lancer sans demande explicite.
  - `PREPARE_RELEASE.bat` supprime des fichiers locaux, dont `Lanceur_Invisible.vbs`, qui est versionné.
  - `BuildMusicSelektorExe.ps1` compile `MusicSelektor.exe`, un lanceur C# de `MusicSelektor.bat`, ignoré par git.
- Commits `feat:`/`fix:`/`docs:`/`refactor:`/`chore:` (`CONTRIBUTING.md`) ; modèle de PR dans `.github/pull_request_template.md`. Mettre à jour `README.md` et `CHANGELOG.md` quand le comportement utilisateur change.

## Journal des erreurs

À relire avant chaque tâche. Une ligne par erreur signalée : `- AAAA-MM-JJ — erreur commise — règle à appliquer désormais`.

_Aucune entrée pour l'instant._
