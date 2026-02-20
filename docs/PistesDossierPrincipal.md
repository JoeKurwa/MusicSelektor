# Pistes dans le dossier principal

## Contexte

Certaines pistes se trouvent **directement dans un dossier** (dossier racine de la bibliothèque, ou dossier artiste sans sous-dossier album). On ne peut pas lier une pochette à une piste **via les métadonnées** (ID3, etc.) dans ce workflow — MusicSelektor gère les pochettes par **dossier**, pas par fichier.

## Solution : pochette dans le même dossier

Pour afficher une pochette pour ces pistes :

1. Placez une image dans **le même dossier** que les fichiers audio.
2. Nommez-la de préférence **`cover.jpg`** (ou `folder.jpg`, `album.jpg`, `cover.png`, etc.).
3. MusicSelektor détecte automatiquement cette image et l’affiche comme pochette pour toutes les pistes de ce dossier.

Aucune modification des métadonnées des fichiers n’est nécessaire.

## Workflow possible

- Dans l’interface, sélectionnez l’album correspondant au « dossier principal » (il peut s’afficher sous le nom du dossier, ex. *MUSIQUES* si vos pistes sont dans `E:\MUSIQUES\`).
- Utilisez **Recherche Google** / **Coller l’URL** comme pour un album classique : la pochette sera enregistrée dans ce dossier en `cover.jpg`.
- Ou copiez une image dans le dossier et renommez-la en `cover.jpg`.

Quand le dossier sélectionné est le dossier racine de la bibliothèque, l’interface affiche la mention :  
*« (Pochette : placez cover.jpg dans ce dossier) »* pour vous le rappeler.
