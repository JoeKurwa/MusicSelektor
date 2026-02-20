# Contribution Guide

Merci de contribuer a MusicSelektor.

## Workflow recommande

1. Forkez le projet.
2. Creez une branche dediee : `feature/nom-court` ou `fix/nom-court`.
3. Faites des commits petits et lisibles.
4. Ouvrez une Pull Request claire.

## Regles de qualite

- Garder les scripts Windows compatibles PowerShell 5.1.
- Eviter les changements qui cassent les chemins relatifs existants.
- Preferer les actions reversibles pour les operations sensibles (ex: deplacer plutot que supprimer).
- Mettre a jour la documentation si un comportement utilisateur change.

## Convention de commit (simple)

- `feat:` nouvelle fonctionnalite
- `fix:` correction de bug
- `docs:` documentation
- `refactor:` refactor sans changement fonctionnel
- `chore:` maintenance

Exemple: `fix: robustifier le lancement silencieux du lecteur`

## Checklist avant PR

- [ ] Le script principal `MusicSelektor.bat` fonctionne.
- [ ] Le scan fonctionne (`SCANNER.bat`).
- [ ] Le module doublons fonctionne (`FIND_DUPLICATES.bat`).
- [ ] Aucun fichier temporaire/log local n'est ajoute au repo.
- [ ] README et CHANGELOG a jour si necessaire.
