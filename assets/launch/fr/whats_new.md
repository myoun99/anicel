## Nouveautés de cette version

## Nouveau

- **Guides dans le script AE** — le script AE pose la trajectoire de la caméra et les directions en calques guides au-dessus de la composition du canevas.
- **Effets dans le script AE** — une rangée avec Luminosité/Contraste, Teinte/Saturation, un flou gaussien, directionnel, radial ou d'objectif, ou Masquage par couleur reçoit l'effet After Effects le plus proche, avec ses valeurs.
- **Mouvements de caméra dans le conte** — « Mouvements de caméra », dans Format de la feuille de conte, choisit d'agrandir la case ou de garder le mouvement dedans. Par défaut, « Dans la case » : la case garde sa taille et montre tout le mouvement réduit. « Réglages du plan », juste en dessous, ne remplace le choix que pour le plan actuel ou les plans sélectionnés.
- **Vue par pages de la règle** — le bouton à l'angle gauche de la règle de la timeline choisit entre Images, Secondes+images et Pages. En Pages, la numérotation repart à chaque page de la feuille de temps et le changement de page s'inscrit sous la forme « p2 ». La règle du panneau Conte compte par pages de feuille de conte.
- **Poser un panneau au fond** — glissez la Feuille de conte, la Feuille de temps, l'Enveloppe de plan ou la Visionneuse secondaire vers la bande du haut : un bouton apparaît, et il pose ce panneau à la place du canevas. Le bouton du canevas le ramène.

## Améliorations

- **Traits sur iPhone et iPad** — un trait n'écrit plus que ce qui change, sans redessiner toute l'image, et les images prennent deux fois moins de mémoire. En contrepartie, les photos et vidéos P3 s'affichent en sRGB.
- **Crayons** — les crayons 2H, HB, 2B et 4B, le crayon de couleur et le porte-mine sont refaits. Le grain vient maintenant de la pointe de la brosse et non de la texture du papier : il reste même texture coupée. L'espacement par défaut des préréglages passe à 5 %, et l'ancien porte-mine reste dans le groupe Plume sous le nom Stylo porte-mine. Les nouveaux réglages arrivent avec « Réinitialiser la bibliothèque ».
- **Lignes de caméra du conte** — une ligne de mouvement nomme ses deux clés, comme « 1f-5f T.U », ou « A-B T.U » si elles ont un nom. FIX ne s'écrit qu'avant et après un mouvement de caméra, et une case où la caméra ne fait rien reste vide. Retirer la rangée caméra de la feuille efface ces lignes et la colonne CAM de la feuille de temps. Les cadres de caméra d'une case se dessinent à chaque clé, comme sur le canevas.
- **Brosses importées** — la vraie pointe d'une brosse .sut est lue, et l'ajustement du flux selon l'intervalle suit le fichier. L'anticrénelage n'efface plus les gris de la pointe. Les brosses déjà importées doivent être réimportées.

## Corrections

- **Traits en retard sur le curseur** — plus le trait était long, plus la ligne s'éloignait du curseur ; elle suit désormais.
- **Import de vidéos sur Android** — importer une vidéo laissait l'aperçu noir et ne créait ni plan ni calque.
- Le script AE s'arrêtait sur un cellulo sans image, et l'opacité d'une rangée se perdait.
- Les droites Z en série prennent chacune la pression de l'appui précédent.
- L'onglet Cellulos de l'export écarte les cellulos sans image : le compte de la liste égale les fichiers écrits.
- Toucher une case de contenu de la feuille de conte dans un plan sans calque storyboard dit maintenant pourquoi.
