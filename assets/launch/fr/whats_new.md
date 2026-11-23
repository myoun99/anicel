## Nouveautés de cette version

## Améliorations

- **L'écran pendant le tracé au stylet** — sur les tablettes où de nombreuses étapes du trait s'accumulent entre deux images de l'écran, le relevé de « ce qui a changé » ne suffisait plus et tout l'écran était redessiné. Seul ce qui a changé est désormais redessiné : le tracé saccade moins.
- **Choisir une image** — quand vous choisissez de nouveau une image après avoir déplacé ou tracé sur le canevas, le dock du bas et la Feuille de temps ne sont plus redessinés plusieurs fois pour rien.
- **Appareils aux limites graphiques basses** — le moteur de dessin ne demande à l'appareil que ce qu'il utilise réellement. Le canevas s'ouvre désormais sur les appareils où des limites basses l'empêchaient de s'ouvrir (comme l'émulateur Android).
- **Flou d'objectif à grand rayon** — le travail confié en une fois est découpé selon la vitesse de l'appareil : le GPU ne s'arrête plus sur un délai dépassé sur les appareils lents.

## Corrections

- La vue du canevas restait décalée au lieu de revenir à sa place après avoir tourné l'écran puis l'avoir remis : c'est corrigé.
