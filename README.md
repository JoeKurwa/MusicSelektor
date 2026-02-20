# MusicSelektor

Music library scanner and manager for Windows (PowerShell + WPF), focused on indexing, duplicate cleanup, and cover artwork support.

[![Platform](https://img.shields.io/badge/platform-Windows%2010%2B-blue)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![Issues](https://img.shields.io/badge/issues-GitHub-black?logo=github)](https://github.com/JoeKurwa/MusicSelektor/issues)
[![Last Commit](https://img.shields.io/github/last-commit/JoeKurwa/MusicSelektor)](https://github.com/JoeKurwa/MusicSelektor/commits)

---

## FR | EN

- **FR**: Outil pour scanner une bibliotheque audio, detecter les doublons (MD5), gerer les pochettes, et visualiser les albums dans une interface graphique.
- **EN**: Tool to scan an audio library, detect duplicates (MD5), manage covers, and browse albums in a desktop GUI.

---

## Table des matieres / Table of Contents

- [Fonctionnalites / Features](#fonctionnalites--features)
- [Quick Start](#quick-start)
- [Demo / Captures](#demo--captures)
- [Scripts principaux / Main Scripts](#scripts-principaux--main-scripts)
- [Structure du projet / Project Layout](#structure-du-projet--project-layout)
- [Roadmap](#roadmap)
- [Contribuer / Contributing](#contribuer--contributing)
- [Support](#support)
- [Notes importantes / Important Notes](#notes-importantes--important-notes)
- [Licence / License](#licence--license)

---

## Fonctionnalites / Features

- Scan recursif des fichiers audio (`MP3`, `M4A`, `FLAC`, `WAV`)
- Generation de `Library.json` avec les metadonnees
- Interface WPF pour la navigation album/pistes/apercu
- Detection de doublons basee sur hash `MD5`
- Export de rapports doublons (`TXT`, `CSV`)
- Recherche auto de pochettes + rapport `AutoCoverReport.json`

---

## Quick Start

### Prerequis / Requirements

- Windows 10+
- PowerShell 5.1+

### Installation

```bash
git clone https://github.com/JoeKurwa/MusicSelektor.git
cd MusicSelektor
```

### Lancement / Run

- `MusicSelektor.bat` - entree principale (scan + GUI)
- `MusicSelektor.exe` - entree principale recommandee pour utilisateur final
- `SCANNER.bat` - scan uniquement
- `CLEANUP_WORKSPACE.bat` - rangement des artefacts generes
- `RUN_REGRESSION_CHECKS.bat` - verifications anti-regression

Au premier lancement, selectionnez votre dossier racine de musique.

### Checklist utilisateur (TO-DO)

Suivre cette checklist dans l'ordre pour utiliser MusicSelektor comme prevu:

- [ ] Lancer `MusicSelektor.exe` (ou `MusicSelektor.bat`).
- [ ] Au premier lancement, choisir le dossier racine (ex: `E:\MUSIQUES`).
- [ ] Verifier que l'arborescence gauche affiche bien `MUSIQUES` puis les dossiers/albums.
- [ ] Cliquer un dossier ou album, puis `LECTURE/PAUSE` pour demarrer.
- [ ] Utiliser `SUIVANT` / `PRECEDENT` et verifier que la pochette se met a jour.
- [ ] Trier la colonne du milieu en cliquant les en-tetes (`Artiste`, `Album`, `Piste`, `Format`).
- [ ] Supprimer des pistes via clic droit (liste du milieu) si necessaire.
- [ ] Ajouter des dossiers/pistes puis lancer `RESCAN_SAME.bat`, ensuite `ACTUALISER LA BIBLIOTHEQUE`.
- [ ] Completer les pochettes manquantes (recherche manuelle / auto-cover). Voir `docs/USER_TODOLIST.md` pour le pas-a-pas detaille.
- [ ] Lancer `FIND_DUPLICATES.bat` pour traiter les doublons si besoin.
- [ ] Lancer `CLEANUP_WORKSPACE.bat` pour garder un workspace propre.

### Commandes directes / Direct commands

```powershell
.\SCANNER.bat
.\FIND_DUPLICATES.bat
.\CLEANUP_WORKSPACE.bat
.\RUN_REGRESSION_CHECKS.bat
.\PREPARE_RELEASE.bat
powershell -ExecutionPolicy Bypass -File ".\CreateLibrary.ps1"
```

---

## Demo / Captures

Ajoute tes captures dans `docs/screenshots/` avec ces noms:

- `main-window.png`
- `duplicates-view.png`
- `covers-workflow.png`

Une fois les fichiers ajoutes, insere les images ainsi:

```md
![Main Window](docs/screenshots/main-window.png)
![Duplicates View](docs/screenshots/duplicates-view.png)
![Cover Workflow](docs/screenshots/covers-workflow.png)
```

---

## Scripts principaux / Main Scripts

- `MusicSelektor.bat` - scan puis ouverture GUI
- `SCANNER.bat` - scan complet (choix du dossier)
- `RESCAN_SAME.bat` - re-scan du **même** dossier racine (sans fenêtre) — à utiliser après avoir ajouté un nouveau dossier (ex. « divers ») pour que la bibliothèque le prenne en compte
- `FIND_DUPLICATES.bat` - module doublons
- `CLEANUP_WORKSPACE.bat` - rangement workspace (artefacts vers `reports/`)
- `RUN_REGRESSION_CHECKS.bat` - checks automatiques (syntaxe/securite/config)
- `PREPARE_RELEASE.bat` - nettoyage avant release
- `CreateLibrary.ps1` - indexation bibliotheque
- `MusicPlayer.ps1` - logique interface principale
- `FindDuplicates.ps1` - moteur detection doublons
- `MusicPlayerGUI.xaml` - layout de l'interface

---

## Structure du projet / Project Layout

- `MusicPlayer.ps1`, `CreateLibrary.ps1`, `FindDuplicates.ps1`, `NormalizeTrackNames.ps1` : scripts coeur
- `reports/` : sorties de travail (auto-cover, normalisation, verification manuelle, doublons, etc.)
- `CoverSearchCache.json` : cache local de recherche pochettes
- `MusicSelektor.debug.log`, `MusicSelektor.network.trace.log`, `MusicSelektor.write-actions.log` : logs de debug/reseau/actions

Note: les artefacts de travail (`reports/`, logs, caches) sont ignores via `.gitignore` pour garder un depot propre.

Nettoyage avance (conserver seulement N rapports recents par famille):

```powershell
powershell -ExecutionPolicy Bypass -File ".\CleanupWorkspaceArtifacts.ps1" -DeleteOld -KeepLatest 5
```

---

## Roadmap

- [x] Indexation bibliotheque audio
- [x] UI WPF de consultation
- [x] Detection MD5 des doublons
- [x] Export TXT/CSV des rapports
- [x] Auto-cover avec rapport
- [ ] Workflow CI GitHub Actions
- [ ] Pack release (zip) automatique
- [ ] Captures/GIF de demonstration

---

## Contribuer / Contributing

Contributions bienvenues / Contributions welcome.

- Guide: `CONTRIBUTING.md`
- Code of conduct: `CODE_OF_CONDUCT.md`
- Issues: https://github.com/JoeKurwa/MusicSelektor/issues
- Changelog: `CHANGELOG.md`

---

## Support

- Ouvrir une issue: https://github.com/JoeKurwa/MusicSelektor/issues
- Inclure:
  - version Windows,
  - version PowerShell (`$PSVersionTable.PSVersion`),
  - etapes de reproduction,
  - message d'erreur complet.

---

## Notes importantes / Important Notes

- Sauvegarde recommandee avant suppression de doublons.
- Le calcul MD5 peut etre long sur de grosses collections.
- `Library.json` peut devenir volumineux.
- Le cache de recherche est stocke dans `CoverSearchCache.json`.
- Les scripts sensibles utilisent un mode securite explicite (`-IUnderstand`) pour eviter les actions destructives involontaires.
- **Pistes dans le dossier principal** : pour les pistes qui se trouvent directement dans un dossier (sans sous-dossier album), on ne peut pas lier une pochette via les metadonnees. Solution : placez un fichier `cover.jpg` (ou `folder.jpg`, `album.jpg`) dans **ce meme dossier** ; MusicSelektor l’affichera comme pochette pour toutes les pistes du dossier. Voir `docs/PistesDossierPrincipal.md` pour plus de details.
- **Nouveaux dossiers** : la bibliotheque (`Library.json`) n'est creee ou mise a jour que lors d'un **scan**. Si vous ajoutez un dossier (ex. « divers »), lancez **`RESCAN_SAME.bat`** puis dans le lecteur **« ACTUALISER LA BIBLIOTHÈQUE »** (ou relancez l'app).

---

## Licence / License

MIT - voir `LICENSE`.

## Auteur / Author

Joe Kurwa
