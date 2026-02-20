# MusicSelektor - TO-DO utilisateur

Checklist simple pour un utilisateur final.

## 1) Demarrage

- [ ] Ouvrir `MusicSelektor.exe` (recommande) ou `MusicSelektor.bat`.
- [ ] Si c'est le premier lancement, choisir le dossier racine de musique (ex: `E:\MUSIQUES`).

## 2) Lecture

- [ ] Dans l'arborescence gauche, selectionner un dossier ou un album.
- [ ] Cliquer `LECTURE/PAUSE` pour lancer/mettre en pause.
- [ ] Utiliser `PRECEDENT` / `SUIVANT` pour naviguer.
- [ ] Verifier que la pochette change avec la piste en cours.

## 3) Organisation

- [ ] Dans la colonne du milieu, trier en cliquant les en-tetes:
  - `Artiste`, `Album`, `Piste`, `Format` (A→Z puis Z→A).
- [ ] Supprimer une ou plusieurs pistes via clic droit (envoi Corbeille).

## 4) Mise a jour de bibliotheque

- [ ] Si de nouveaux fichiers/dossiers sont ajoutes:
  - lancer `RESCAN_SAME.bat`
  - puis cliquer `ACTUALISER LA BIBLIOTHEQUE`.

## 5) Pochettes

- [ ] Utiliser `RECHERCHE MANUELLE` ou `TROUVER LES POCHETTES (AUTO - LOT)` selon besoin.
- [ ] Pour les pistes sans sous-dossier album, placer `cover.jpg` dans le dossier concerne.

### Recherche manuelle (pas a pas)

- [ ] Dans la colonne de gauche, selectionner l'album (ou le dossier) a corriger.
- [ ] Cliquer sur `RECHERCHE MANUELLE` (colonne de droite).
- [ ] Dans la page ouverte (images), choisir une image de pochette propre (carree si possible).
- [ ] Copier l'URL directe de l'image **ou** copier l'image dans le presse-papiers.
- [ ] Revenir dans MusicSelektor, puis cliquer `APPLIQUER COVER (PRESSE-PAPIERS)`.
- [ ] Verifier dans l'aperçu que la pochette apparait.
- [ ] Si necessaire, cliquer `ACTUALISER LA BIBLIOTHEQUE` pour rafraichir l'affichage.

Notes utiles:
- La pochette est enregistree dans le dossier cible sous le nom `cover.jpg`.
- Si l'image choisie ne fonctionne pas, recommencer avec une autre source (image non protegee, format JPG/PNG valide).

### Important (menu clic droit dans Google Images)

Dans le menu contextuel de l'image (comme sur ta capture), privilegier:

- `Copier l'adresse de l'image` (recommande)
- ou `Copier l'image`

Eviter:

- `Copier l'adresse du lien` (pointe souvent vers la page web, pas vers le fichier image)
- les miniatures "shopping" ou liens rediriges non directs

Diagnostic rapide:

- Si `APPLIQUER COVER (PRESSE-PAPIERS)` echoue, c'est souvent que l'URL copié n'est pas une vraie image directe.
- Dans ce cas, ouvrir l'image en grand puis refaire `Copier l'adresse de l'image`.

## 6) Doublons

- [ ] Lancer `FIND_DUPLICATES.bat` pour identifier les doublons.
- [ ] Suivre les confirmations de securite avant suppression.

## 7) Entretien

- [ ] Lancer `CLEANUP_WORKSPACE.bat` pour nettoyer les artefacts.
- [ ] (Optionnel) lancer `RUN_REGRESSION_CHECKS.bat` avant une release.
