## MusicSelektor 1.2.0

### Nouveautés majeures
- Arborescence gauche finalisée (`MUSIQUES` parent, dossiers puis albums).
- Lecture possible directement depuis un dossier parent (playlist multi-sous-dossiers).
- Rafraîchissement automatique de la pochette lors du changement de piste.
- Tri des pistes au clic sur les en-têtes de la colonne du milieu (A→Z / Z→A).
- Suppression de pistes via clic droit dans la colonne du milieu (Corbeille + confirmation).
- Nouveau launcher `MusicSelektor.exe` pour simplifier l’usage côté utilisateur.

### Qualité / stabilité
- Corrections des régressions d’arborescence et de lecture.
- Lisibilité renforcée de la liste des pistes (couleurs hover/sélection).
- Vérifications de non-régression renforcées dans `TestRegression.ps1`.

### Validation release
- `TestRegression.ps1` exécuté avec succès : **0 échec, 0 warning**.
- Configuration release validée :
  - `DebugMode=false`
  - `NetworkTraceEnabled=false`

### Upgrade
- Remplacer les scripts existants par cette version.
- Lancer `MusicSelektor.exe` (ou `MusicSelektor.bat`).
