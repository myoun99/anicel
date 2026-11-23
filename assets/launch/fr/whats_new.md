## Nouveautés de cette version

## Améliorations

- **Dessin au stylet quand le GPU prend du retard** — Un trait est confié au moteur de dessin une seule fois par image affichée. Quand l'écran ne suit pas, le travail des traits ne s'accumule plus sur le GPU et ne ralentit plus le canevas.
- **Le canevas sur Android** — Le canevas s'affiche de la même façon que sur toutes les autres plateformes. C'est cette différence qui faisait sauter le canevas d'une image, sauf la caméra, quand le stylet touchait l'écran après un panoramique.
- **Certains appareils Android** — Là où le moteur de dessin ne peut pas écrire directement dans le tampon de l'écran, le canevas s'affiche en recopiant seulement ce qui a changé.
- **L'écran des statistiques d'images** — Il montre les pas d'un trait, le retard du GPU et la mémoire, le temps jusqu'au premier pas d'un trait et du lever du stylet à son enregistrement, ainsi que la voie d'affichage du canevas et sa vérification.

## Corrections

- Réduire un côté de la boîte de transformation presque à un point affichait l'aperçu sans déformation, et appuyer sur Entrée faisait disparaître l'image. Corrigé.
