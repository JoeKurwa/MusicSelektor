# Changelog

Tous les changements notables de ce projet seront documentés dans ce fichier.

## [Non publié]

### Corrigé
- 🐛 Accents et emoji mal affichés sous Windows PowerShell 5.1 (« bibliothÃ¨que ») : messages de suppression de `FindDuplicates.ps1`, bouton `TROUVER LES POCHETTES (AUTO - LOT)` après une recherche auto, invite de `SaveCoverFromClipboardUrl.ps1` et textes de `RESCAN_SAME.bat`

### Amélioré
- ✨ `TestRegression.ps1` refuse tout caractère non ASCII hors commentaires dans les `.ps1`, et tout caractère non ASCII dans les `.bat`, pour éviter que le problème revienne

### Documentation
- 📝 Ajout de `CLAUDE.md` : consignes de travail et architecture pour Claude Code

## [1.2.1] - 2026-02-20

### Documentation
- 📝 Ajout d'une checklist utilisateur claire dans `README.md` (section "Checklist utilisateur (TO-DO)")
- 📝 Ajout du guide `docs/USER_TODOLIST.md` avec parcours d'utilisation pas-a-pas
- 📝 Mise en avant de `MusicSelektor.exe` comme point d'entree recommande pour utilisateur final

## [1.2.0] - 2026-02-18

### Ajouté
- ✅ Arborescence dossiers/albums dans la colonne de gauche avec racine fonctionnelle `MUSIQUES`
- ✅ Lecture d'un dossier parent (playlist agrégée sur sous-dossiers), pas seulement un album feuille
- ✅ Rafraîchissement automatique de la pochette à chaque changement de piste (`SUIVANT` / `PRECEDENT` / auto-next)
- ✅ Tri A→Z / Z→A au clic sur les en-têtes de la colonne du milieu (`Artiste`, `Album`, `Piste`, `Format`)
- ✅ Clic droit dans la colonne du milieu pour supprimer une ou plusieurs pistes (envoi Corbeille + confirmation)
- ✅ Launcher `MusicSelektor.exe` pour usage utilisateur final (ouvre `MusicSelektor.bat`)

### Corrigé
- 🐛 Doublons d'arborescence de type `MUSIQUES > MUSIQUES`
- 🐛 Régression de lecture après passage à l'arborescence (clic dossier ne lançait plus la lecture)
- 🐛 Lisibilité des pistes (survol/sélection) dans la colonne du milieu
- 🐛 Encodage de certains messages UI

### Amélioré
- ✨ Uniformisation visuelle (thème turquoise) avec amélioration du contraste texte
- ✨ Bouton `LECTURE` renommé en `LECTURE/PAUSE`
- ✨ Durcissement des tests de non-régression pour les fonctionnalités UI/lecture récentes

## [1.1.0] - 2026-02-17

### Amélioré
- ✨ Professionnalisation des lanceurs `SCANNER.bat` et `FIND_DUPLICATES.bat` (vérifications, codes retour, fermeture automatique)
- ✨ Harmonisation de la documentation utilisateur et contribution
- ✨ Logs de démarrage déplacés vers `%TEMP%` pour garder la racine projet propre

### Ajouté
- ✅ `.editorconfig` pour standardiser l'édition des fichiers
- ✅ `CONTRIBUTING.md` avec workflow de contribution
- ✅ `CODE_OF_CONDUCT.md` pour un cadre communautaire clair
- ✅ Templates GitHub pour les issues et pull requests (`.github/`)
- ✅ `PREPARE_RELEASE.bat` pour nettoyer les artefacts locaux avant publication

## [1.0.0] - 2026-02-17

### Ajouté
- ✅ Module de détection de doublons par hash MD5 (`FindDuplicates.ps1`)
- ✅ Interface graphique pour visualiser et gérer les doublons détectés
- ✅ Fonctionnalité d'export de rapports de doublons (TXT/CSV)
- ✅ Fonctionnalité de suppression sécurisée des doublons
- ✅ Bouton "CHERCHER LES DOUBLONS" dans l'interface principale
- ✅ Calcul et affichage de l'espace disque gaspillé par les doublons
- ✅ Documentation complète (README.md)
- ✅ Licence MIT pour l'open source
- ✅ Fichier .gitignore pour le contrôle de version
- ✅ Lanceur batch pour la détection de doublons (`FIND_DUPLICATES.bat`)

### Corrigé
- 🐛 Correction de l'accès aux propriétés dans `MusicPlayer.ps1` (ligne 47)
- 🐛 Correction de la colonne "Artiste" inexistante dans `MusicPlayerGUI.xaml` (remplacée par "Album")
- 🐛 Ajout de la référence manquante à `CurrentTrackInfo` dans l'interface

### Amélioré
- ✨ Affichage des informations de l'album sélectionné (nom et nombre de pistes)
- ✨ Meilleure gestion des erreurs dans tous les scripts
- ✨ Interface utilisateur améliorée avec indicateurs visuels

### Documentation
- 📝 README.md complet avec guide d'installation et d'utilisation
- 📝 CHANGELOG.md pour suivre les versions
- 📝 Commentaires dans le code pour faciliter la maintenance

---

## Notes de version

### Version 1.0.0
Première version stable prête pour l'open source avec toutes les fonctionnalités principales :
- Indexation de bibliothèque musicale
- Visualisation graphique
- Détection et gestion de doublons
