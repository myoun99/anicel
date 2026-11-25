## Nouveautés de cette version

## Nouveau

- **« Ajouter des fichiers » et « Ajouter un dossier » dans la fenêtre d'importation** — On peut ajouter des fichiers et des dossiers pendant que la fenêtre d'importation est ouverte. Ils appellent la même entrée qu'« Ouvrir un fichier » et « Ouvrir un dossier » de la barre du haut.
- **Tout passe par la fenêtre d'importation** — Les brosses, polices, palettes, plugins d'effets et fichiers de raccourcis arrivent par la même fenêtre d'importation que les médias.
- **Pourquoi un fichier n'a pas pu être lu** — L'avertissement d'un fichier qui n'a pas pu être importé indique aussi pourquoi l'application qui l'a transmis l'a refusé, jusqu'où le fichier est arrivé et ce qui a empêché de lire un PSD.
- **Curseur « Aucun »** — On peut choisir « Aucun » pour le curseur dans les réglages d'affichage. Ni le curseur du système ni celui de l'application n'apparaît sur le canevas.
- **Défilement et zoom gardés par plan et par timeline** — Le défilement du panneau de timeline et de la feuille est gardé pour chaque plan, celui du storyboard et son zoom pour chaque timeline, et ils sont enregistrés. Les sections SE et caméra masquées depuis la barre d'outils de la timeline restent masquées à la réouverture.
- **La fenêtre de suppression de calques** — Elle liste, par plan, les calques qu'une suppression emporte, y compris ceux des plans d'autres timelines.

## Améliorations

- **Les traits juste après le lancement** — Ce que le moteur de dessin compile n'était gardé que sous Windows ; il l'est désormais sur toutes les plateformes. Les premiers traits, lourds parce que tout était recompilé à chaque lancement, sont plus légers dès le deuxième lancement.
- **Lever le stylet** — Les tuiles déjà dessinées par le trait sont confiées telles quelles au cel : lever le stylet n'attend plus le GPU.
- **La mémoire sur Android** — Les polices de l'application sont lues directement dans l'APK, ce qui économise environ 70 Mo que prenaient leurs copies.
- **La progression de la fenêtre d'importation** — Pour les fichiers PDF, son et image, la progression avance au rythme de ce qui a réellement été lu. Un PDF n'est ouvert qu'une seule fois.
- **Changer de plan ou de timeline** — Changer de plan ou de timeline ne jette plus ni ne reconstruit toutes les lignes des panneaux de timeline et de storyboard.
- **Déplacer le pointeur** — Moins de choses sont redessinées quand le pointeur passe sur les onglets des docks, les en-têtes de panneaux et la barre de timeline.
- **La file d'exportation** — La ligne d'une tâche réserve dès le départ la place de sa barre de progression ; sa hauteur ne change plus pendant la préparation.
- **La fenêtre de débogage** — Elle affiche un inspecteur d'entrée, les mappages mémoire qui tiennent le plus de mémoire privée et le rythme du préchargement de la lecture.

## Corrections

- Un défilement vertical rapide de la timeline, à l'arrêt, faisait disparaître pendant une image ou plus le fond d'un dialogue ou les barres de cellules d'une ligne. Corrigé.
- Supprimer un calque collé lié dans son propre plan supprimait aussi sa source. Seul ce calque est supprimé désormais (entre plans partagés, rien ne change).
- Sélectionner un calque avec sa copie liée et les supprimer provoquait une erreur. Corrigé.
- Dans un plan partagé, la rastérisation ne faisait rien quand l'usage d'un calque dans un autre plan montrait une autre image. Corrigé. Une notification signale désormais les calques restés des références.
- Terminer un lasso pendant un bref arrêt de l'application refermait la sélection droit vers son point de départ, ou ne sélectionnait rien. Corrigé.
- Tourner la boîte de transformation, un texte, le cadran d'angle, etc. pendant un bref arrêt de l'application lisait la rotation à l'envers. Corrigé.
- Sur Android, Ctrl+Z au clavier ne faisait rien tant qu'une touche de lettre n'avait pas été pressée. Corrigé.
- Sur Android, choisir ensemble des images numérotées depuis Drive ou ailleurs n'importait que la première. Corrigé.
