## Nouveautés de cette version

## Améliorations

- **L'écran pendant le tracé au stylet** — Sur les tablettes où de nombreuses étapes du trait s'accumulent entre deux images de l'écran, le relevé de « ce qui a changé » ne suffisait plus et tout l'écran était redessiné. Seul ce qui a changé est désormais redessiné : le tracé saccade moins.
- **Appareils aux limites graphiques basses** — Le moteur de dessin ne demande à l'appareil que ce qu'il utilise réellement. Le canevas s'ouvre désormais sur les appareils où des limites basses l'empêchaient de s'ouvrir (comme l'émulateur Android).
- **Flou d'objectif à grand rayon** — Le travail confié en une fois est découpé selon la vitesse de l'appareil : le GPU ne s'arrête plus sur un délai dépassé sur les appareils lents.

## Corrections

- La vue du canevas restait décalée au lieu de revenir à sa place après avoir tourné l'écran puis l'avoir remis : c'est corrigé.
