## Nouveautés de cette version

## Nouveau

- **Préréglages des lignes de son** — le haut de la liste Fx d'une ligne de son propose des préréglages (Dialogue, Musique, Effets sonores, Ambiance). En choisir un pose d'un coup sur la ligne un ensemble d'effets accordé à ce son (un égaliseur, un compresseur, etc.) ; ensuite, ils appartiennent à la ligne et leurs valeurs se modifient.
- **Réduction du bruit** — la section Audio du menu Fx d'une ligne de son gagne la Réduction du bruit. Une seule valeur règle la part du son nettoyé que l'on entend ; tout juste ajoutée, elle vaut 0 et ne change pas le son. Elle fonctionne aussi sur des sons à 44,1 kHz et 96 kHz.
- **Synchroniser au préréglage** — la fenêtre qu'ouvre la marque « en usage » d'un fichier dans la médiathèque gagne « Synchroniser au préréglage ». Choisissez parmi les emplacements déjà posés ceux qui diffèrent du préréglage de placement du fichier pour ramener le début, la durée, l'ajustement, etc. au préréglage, ou utilisez « Appliquer à tous » pour tous ceux qui diffèrent. Cela marche pour les sons, les vidéos et les images.
- **Ajuster l'image à la nouvelle taille du canevas** — la fenêtre Taille du canevas, et la pastille de l'ajustement sur le canevas, peuvent ajuster l'image au nouveau canevas avec « Ajuster, proportions gardées » ou « Étirer, proportions ignorées ». Par défaut, l'image reste telle quelle, comme avant.
- **Taille du canevas de plusieurs plans** — sélectionnez plusieurs blocs de plan et changez la taille du canevas : tous les plans sélectionnés changent d'un coup, en une seule annulation.
- **Changer le type d'un calque** — appuyez sur l'icône de type d'une ligne d'image pour la faire passer entre Image, Animation et Storyboard. Un type que la ligne ne peut pas prendre est affiché désactivé. Appuyé parmi plusieurs lignes sélectionnées, il les change toutes. La bascule storyboard du menu Calque est passée à ce bouton.
- **Éclaircir avec le bord avant** — tirer vers l'arrière le bord avant d'un bloc d'images éclaircit les blocs selon le nombre d'images tirées (une image : 1, 3, 5, 7… ; deux images : 1, 4, 7…). Dans le panneau de conte, tirer le bord avant d'un plan au-delà de sa fin supprime le plan.
- **Espacement du tampon** — les réglages de l'outil Tampon gagnent un Espacement, en part de la taille du morceau ; un morceau entier par défaut.
- **Taille des vidéos de l'export des cellulos** — les vidéos de l'onglet Cellulos de la fenêtre d'export gagnent une Taille (Caméra, Canevas). Caméra par défaut.
- **Cible XDTS** — avec XDTS choisi dans le format de feuille d'exposition, la cible à exporter (animation clé, intervalles) se choisit en dessous. Si vous n'en choisissez qu'une, seule celle-ci est écrite.

## Améliorations

- **Une application plus légère** — moins d'à-coups pendant le précalcul des images de lecture (pendant que la bande verte se remplit), une molette et des bascules d'œil de calque plus légères sur la timeline, et plus d'attente du moteur graphique à chaque trait. Les plans avec un fx de numéro de cellulo, le glissement d'une valeur de fx, l'arrêt à la fin de l'ouverture d'un gros .anicel et l'ouverture d'un .tvpp sont aussi plus légers.
- **Glisser une valeur de flou** — l'écran se fige moins quand on commence à faire glisser une valeur de flou, et moins pendant le glissement.
- **Pendant le choix d'une couleur** — tourner la roue chromatique d'une piste, ou celle du papier, de l'arrière-plan ou du Fond, montre la couleur à mesure et ne l'enregistre qu'une fois, à la fermeture de la fenêtre, en une seule annulation.
- **Tampons par glissement** — une rangée de tampons posée d'un seul glissement s'annule d'un seul Ctrl+Z. Les tampons sur plusieurs cellulos se posent derrière la fenêtre d'attente.
- **Remplissage continu et tampons par glissement** — même si l'écran se fige un instant, chaque zone traversée entre-temps est remplie, et la rangée de tampons suit le chemin tel qu'il a été tracé.
- **Instructions de caméra sur le papier de conte** — un mouvement de caméra partagé par deux cases est écrit dans chaque case pour sa propre part (par exemple 1f-73f T.B et 74f-144f T.B). Un plan d'une seule case écrit le plan entier avec les mêmes mots que sa feuille d'exposition.
- **Export des cellulos** — un bloc de storyboard sans nom s'exporte quand même, sous le prochain numéro libre (le nom du bloc dans le projet ne change pas). Filtrer par étiquette de couleur retire de la liste d'export les lignes sans étiquette. Les sections repliables de la fenêtre d'export commencent ouvertes.
- **Raccourcis d'affichage sur le panneau de fond** — les raccourcis de zoom et de rotation fonctionnent aussi sur une feuille d'exposition ou une visionneuse posée au fond.
- **Coller dans les lignes S** — des images copiées d'un calque ordinaire ne se collent pas dans une ligne S, ni celles d'une ligne S dans un calque ordinaire ; les boutons de collage se désactivent alors.
- **Import TVPaint** — quand un fichier son n'est pas à l'endroit enregistré dans le .tvpp, il est cherché sous le dossier du fichier. Les noms d'instance de calque en hangeul, en kana ou en d'autres lettres arrivent tels quels, et le mode de fusion de chaque calque (Produit, etc.) aussi.
- **Quand le périphérique graphique s'arrête** — sous Windows, si le périphérique graphique qui dessine l'écran s'arrête, une fenêtre propose « Enregistrer et redémarrer », « Quitter sans enregistrer » ou fermer.
- **Barres de défilement de la médiathèque** — les barres de défilement de la médiathèque sont toujours affichées, en vue liste comme en vue icônes.
- **La liste des outils** — les noms d'outils du panneau des réglages de l'outil tiennent sur une ligne, coupés par des points de suspension s'ils ne tiennent pas ; l'infobulle montre le nom entier.

## Corrections

- Après avoir annulé chaque étape d'une boîte de transformation, une modification restait retenue et le contour de la sélection restait rouge.
- Une fois l'historique d'annulation plein, les gestes faits de plusieurs étapes, comme un glissement de tampons, ne s'annulaient plus en une fois.
- Un glissement de tampons pouvait perdre le dernier tampon.
- En modifiant plusieurs blocs sélectionnés à la fois, par exemple en allongeant leurs images, le rectangle de sélection ne suivait pas les blocs.
- Aller sur une image dont une modification avait vidé la bande verte montrait l'image, mais la bande ne se remplissait plus.
- Quand un changement de taille du canevas déplaçait l'ancre, les points des effets (le centre d'un flou radial, la place d'un numéro de cellulo, etc.) ne suivaient pas l'image.
- Faire glisser une valeur de flou faisait grimper la mémoire de plusieurs gigaoctets, qui ne revenait pas une fois le flou retiré.
- Dans l'aperçu de la fenêtre d'export, passer d'une image à l'autre montrait un écran noir jusqu'à l'image suivante, et un nouvel anneau de chargement apparaissait comme un petit point.
- Dans la fenêtre d'export, une feuille XDTS avec seulement les intervalles choisis s'affichait comme un écran vide.
- Une prise enregistrée avec la réduction du bruit activée était posée un peu en retard, décalée de la bouche.
- Supprimer des couleurs sur plusieurs blocs donnait une fenêtre de progression qui semblait figée ; le pourcentage se remplit désormais.
- Élargir le panneau pendant que la liste de la médiathèque était défilée jusqu'au bout laissait les colonnes et la barre de défilement décalées.
- Avec la liste des sous-outils ouverte, les lignes du bas du panneau des réglages de l'outil (remplissage continu, dégradé, etc.) étaient coupées et inaccessibles au défilement.
