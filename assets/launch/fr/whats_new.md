## Nouveautés de cette version

## Nouveau

- **Plusieurs timelines** — le bouton de timeline dans la légende du panneau de conte crée, ouvre, renomme, duplique et supprime des timelines. Ouvrir une autre timeline change tout, plans et lignes SE compris. Un plan synchronisé, partagé par deux timelines, a son propre bouton de synchronisation à côté du bouton de lien.
- **Marqueurs de règle** — double-cliquez sur la règle pour poser un marqueur avec un texte, une couleur et une durée. Faites-le glisser pour le déplacer ; double-cliquez dessus pour le modifier ou le supprimer.
- **Pixelliser un fx** — le bouton de pixellisation dans l'en-tête d'un groupe fx ou d'une transformation fige ce seul fx dans l'image, tel qu'il s'affiche. Le bouton reste éteint tant qu'aucune valeur n'a changé.
- **Dégradé et remplissage continu** — avec « Dégradé » activé dans les réglages de l'outil de remplissage, choisissez une plage par zone ou au lasso, puis faites glisser à nouveau pour y peindre un dégradé. « Remplissage continu » remplit d'un coup toutes les zones survolées en maintenant l'appui.
- **Début et fin du trait** — « Début et fin » dans les réglages du pinceau affine et éclaircit le début et la fin du trait. Les pinceaux Clip Studio apportent leurs réglages de début et de fin.
- **Importer des pinceaux TVPaint** — importez un BRUSH.tvpx exporté depuis le panneau personnalisé de TVPaint avec « Importer des pinceaux ».
- **Feuilles de temps XDTS** — les formats de feuille de temps comptent les quatre feuilles du visualiseur XDTS (A3 6 secondes, B4 6 secondes, B4 3 secondes, Ponoc 6 secondes). Activez « Sortie de l'encre » à l'export XDTS pour joindre l'écriture manuscrite de la feuille, visible dans le visualiseur.
- **Vidéo dans l'export des cellulos** — l'onglet Cellulos de la fenêtre d'export écrit aussi une vidéo par plan (MP4, MOV ou GIF). Les formats vidéo de l'onglet Séquence gagnent le GIF, et les dossiers créés par « Dossiers » prennent un préfixe et un suffixe.
- **Importation** — choisissez « Nouveau projet » sous « Vers » dans la fenêtre d'import pour ouvrir le fichier dans un nouvel onglet. Une vidéo peut entrer en « Image seule » ou « Son seul », et une vidéo d'une autre cadence que le projet peut être ajustée au projet. Des fichiers numérotés déposés ensemble se regroupent en une ligne, et chaque ligne peut être désactivée pour la laisser de côté.
- **GPU** — dans Préférences ▸ Système, choisissez le GPU utilisé par l'application (Automatique, Économie d’énergie, Hautes performances ; Windows) et voyez le nom du GPU utilisé. L'onglet Mémoire montre aussi la mémoire vidéo de l'application.
- **Solo par prise** — le bouton de prise dans la légende n'affiche que les lignes des prises choisies.
- **Chercher par touche** — dans la fenêtre des raccourcis clavier, appuyez sur le bouton à côté du champ de recherche puis tapez une touche pour trouver les actions qui l'utilisent. En cas de conflit, le nom de l'autre action s'affiche à côté de l'avertissement ; appuyez dessus pour retirer la touche d'un côté.
- **Pilules de sélection et de transformation** — une sélection terminée reçoit une pilule en dessous (désélectionner, inverser, anticrénelage), et l'outil de transformation une pilule sous son cadre (anticrénelage, miroir horizontal, miroir vertical, valider, annuler). La grille montre tous ses points avant d'y toucher, et la position de chaque point se saisit dans le panneau des réglages de l'outil.
- **Aperçu des retouches de couleur** — Binariser, Supprimer la couleur et Conserver la couleur ont un bouton d'aperçu : le résultat s'affiche sur le canevas avant de l'appliquer.
- **Zoom Alt+molette** — dans la timeline, la feuille d'exposition et le panneau de conte, Alt+molette agrandit et réduit les images. Le zoom à deux doigts garde le point entre les doigts.
- **Liste des plans** — la première case de la légende montre le nom du plan actuel ; appuyez dessus pour ouvrir la liste des plans, où l'on peut aussi les renommer.

## Améliorations

- **Une application plus légère** — les calculs lourds passent à la carte graphique et à des fils d'exécution séparés : dessiner, remplir, transformer, lire et enregistrer dans un grand plan fige moins l'écran. Le défilement et la lecture de la timeline et du conte sont plus légers, et dès le deuxième lancement la fenêtre « Préparation de l'application » disparaît en une seconde environ.
- **Mémoire** — ouvrir un grand plan, remplir encore et encore ou dupliquer une timeline ne fait plus autant grimper la mémoire.
- **Traits à la souris** — un trait tracé à la souris dans une scène lourde traîne moins.
- **Pinceaux à mélange** — un trait avec le mélange activé accroche moins en passant sur ce qui est déjà peint.
- **Boutons de réinitialisation** — un bouton de réinitialisation n'est actif que s'il y a quelque chose à rétablir, et il prend alors la couleur d'accent. Les boutons de rotation de la pilule du canevas gardent leur couleur habituelle ; quand la vue est tournée, c'est la réinitialisation de la rotation qui s'allume.
- **Fenêtre d'attente** — couper, coller, dupliquer, valider une transformation et les retouches de couleur sur plusieurs images passent derrière la fenêtre d'attente ; une seule image se traite aussitôt, sans fenêtre.
- **Plans liés** — coller un bloc de plan en « Coller lié » crée un plan lié tel qu'il est, durée, clés caméra et conte compris. Les plans liés sont écrits sous le numéro du plan dans l'en-tête de la feuille de temps, et les calques d'un plan lié ne peuvent pas être déliés.
- **Échanger les images** — collez sur un bloc d'un calque image ou d'une ligne synchronisée, ou faites glisser un bloc sur le bloc d'une autre ligne : le bloc reste, seule son image change. Glisser vers le bloc voisin dans une ligne synchronisée échange aussi seulement les images.
- **Sélections** — une sélection commencée sur une case vide copie, coupe et colle comme une sélection commencée sur un bloc.
- **Lignes de calque** — créer un dossier avec plusieurs calques sélectionnés les y range. Détacher agit sur tous les calques sélectionnés. Un nouveau calque attaché s'ajoute juste au-dessus ou au-dessous de la ligne où vous êtes, et le bouton de repli des calques attachés se divise en une moitié haute et une moitié basse. Un dossier replié se colle replié.
- **Légende** — le solo par étiquette de couleur choisit par étiquette seule, quelle que soit la prise. Le bouton de timeline de la légende du conte a la taille d'un nom de ligne.
- **SE** — l'étiquette SE sur le canevas réunit son nom et son type dans une seule case. Le nom et la réplique d'un bloc SE tiennent sur une ligne, et Entrée ferme la fenêtre avec « OK ». La feuille de temps ne grise plus les lignes vides de la colonne SE.
- **Lignes de son** — la case de fusion porte un bouton haut-parleur et une barre de volume global (jusqu'à 200). L'opacité d'une ligne de son s'affiche sur le canevas pendant le glissement. Le volume global se règle par cette seule barre : la piste « Volume global » du groupe fx audio a disparu.
- **Saisir la valeur d'une barre** — double-cliquez sur la barre d'opacité d'une ligne ou sur la barre de volume global d'une ligne de son : un pavé numérique s'ouvre dessous pour taper la valeur. Le conte, la timeline et la feuille d'exposition se comportent de même.
- **La timeline pendant la lecture** — les boutons comme la pilule d'image ne changent plus pendant la lecture. Survolez la ligne rouge d'un bloc qui dépasse le bord d'un plan : une infobulle en donne la raison.
- **Fenêtre des raccourcis clavier** — la fenêtre est plus grande, et sous « Canevas › Outils » chaque outil est suivi de ses sous-outils. La barre de défilement ne recouvre plus les boutons de réinitialisation. Dans le préréglage TVPaint, Alt-glisser déplace la vue et Ctrl+Alt-glisser la fait tourner.
- **Pilule de pinceau sur les panneaux d'arrière-plan** — avec la visionneuse principale ou une feuille en arrière-plan, la même pilule de pinceau que sur le canevas se tient au même endroit.
- **Outil de découpe** — choisissez « Affichage » ou « Calque » sous « Référence ». « Affichage » découpe tous les calques visibles tels qu'ils s'affichent.
- **Outil de remplissage** — en maintenant l'appui et en bougeant, le damier glisse avec le curseur.
- **Valeurs par défaut de l'import** — les images entrent à leur taille d’origine. Des options longues n'élargissent plus la fenêtre d'import. Réimporter un fichier du même nom prévisualise et importe le nouveau fichier. Les fichiers intégrés de la médiathèque montrent leur date d'intégration au lieu d'un chemin.
- **Pourcentage à l'ouverture et à l'import** — à l'ouverture d'un projet comme à l'import depuis la fenêtre d'import, le pourcentage avance avec la part du fichier déjà lue. La barre ne reste plus figée pendant qu'un fichier descend du cloud, et un fichier .anicel affiche son pourcentage dès le début.
- **Cadence** — 23,976 i/s porte la mention « Recommandé ».
- **Export** — l'aperçu vidéo montre la même image que le fichier écrit. Enregistrer sous (PNG) imprime la trajectoire de caméra, les repères et la pelure d'oignon comme sur le canevas. L'onglet Cellulos a toujours une barre de défilement pour les dossiers de calques, et exporte les feuilles de temps de tous les plans liés.
- **Étiquettes de couleur** — l'étape « Décors » disparaît. Les étiquettes de papier commencent par le papier du LO et prennent la couleur de leur étape, et un nouveau calque image naît à la couleur du LO.
- **Format de feuille de temps** — avec « Noms de BOOK · sans répétition », les BOOK superposés s'écrivent en abrégé, comme BOOK1,2,3.
- **Calque de direction** — le dessin d'un calque de direction s'affiche toujours au-dessus des lignes de dessin, et les nouvelles lignes de dessin s'ajoutent sous la ligne de direction.
- **Lettres** — les numéros de cellulo et les étiquettes SE sont dessinés aussi nets que les images. Le chinois simplifié du conte s'imprime avec la même graisse à l'écran et en PDF.
- **Fusion de calques image** — des calques image fusionnés restent un calque image.
- **Le son dans la visionneuse** — un fichier son s'ouvre en deux formes d'onde : le fichier entier et un gros plan autour de la tête de lecture. Appuyez sur l'une ou l'autre pour y aller.
- **Plug-ins fx** — un plug-in qui échoue à dessiner affiche ⚠ en tête de sa ligne. Appliquer un plug-in pour la première fois ne fige plus l'application. « Limite de travail des plug-ins FX externes » dans les Préférences propose des paliers plus lisibles.
- **Redémarrage du pilote graphique** — les dessins non enregistrés sont conservés quand le pilote redémarre.
- **Déplacer la vue** — les surimpressions comme le cadre de caméra suivent l'image quand vous déplacez ou zoomez. Pendant une transformation, le contour de la sélection suit les bords des pixels.
- **Pipette** — appuyer sur Alt au milieu d'un glissement ne passe à la pipette qu'à la fin du glissement.
- **Mode clair** — la couleur de fond autour du canevas ne change pas en mode clair.
- **Caméras TVPaint** — une caméra TVPaint qui suit un chemin courbe arrive avec autant de clés que le fichier en a. Auparavant, une clé tombait toutes les quelques images là où le chemin s'incurvait.
- **Transformer de grandes images** — une sélection plus grande que ce que la carte graphique traite d'un coup se transforme quand même avec l'outil de transformation, grille comprise.
- **Enregistrement de voix** — la réduction de bruit et le traitement du volume se font sur un autre fil d'exécution à l'arrêt de l'enregistrement : l'écran ne se fige plus à la fin d'une longue prise.

## Corrections

- **Mises à jour Android** — chaque mise à jour de l'application effaçait les réglages et faisait revenir la fenêtre du premier lancement.
- **Fermeture sous Windows** — l'application continuait de tourner après la fermeture de sa fenêtre.
- **Export** — exporter un plan pendant que le canevas était sur un autre plan fermait parfois l'application.
- **Images noires à la lecture du conte** — une image noire apparaissait sur le canevas au passage d'un plan au suivant.
- **Traits** — les courbes rapides devenaient anguleuses, les traits à la souris dans une scène lourde se reliaient par de longues droites, la première encre d'un trait s'affichait en retard, et l'anticrénelage « Aucun » effaçait le grain des pointes bitmap.
- **Maj ou Ctrl maintenue** — la répétition automatique de la touche arrivait comme un nouvel appui, lâchant une droite à la Maj ou arrêtant la lecture.
- Un calque d'un plan lié ne pouvait pas être renommé, et un plan lié créé par « Coller lié » ne revenait pas avec Rétablir après une annulation.
- Après avoir réordonné des calques par glissement, ou en avoir ajouté ou supprimé, des blocs s'affichaient sur les mauvaises lignes.
- La dernière ligne d'un groupe de calques attachés ou d'un dossier ne pouvait pas en être sortie par glissement.
- La couleur des blocs d'une ligne de dossier s'interrompait en chemin, et une ligne de couleur de bloc apparaissait au-dessus des triangles d'angle.
- Réduire la vue par pages mélangeait les numéros d'image.
- La poignée en haut au milieu d'un graphe était cachée sous sa barre d'outils.
- Un décalage A/V négatif avançait à peine l'image.
- En transformation, appuyer sur une poignée déplaçait toute l'image, le curseur devenait une main pendant un glissement au stylet, certaines lignes ne suivaient pas quand plusieurs lignes étaient transformées ensemble, et une petite sélection resserrée en perspective disparaissait.
- La roue chromatique ne suivait pas le noir pur (#000000).
- Avec « Remplir au-delà du canevas » désactivé, un remplissage débordait quand même du canevas.
- Une ligne floue d'1 px apparaissait au bord du canevas, et un flou au-delà du canevas était coupé au bout de l'image.
- Dans les plans liés et les lignes attachées synchronisées, annuler pouvait montrer l'image d'une autre ligne ou laisser des cellulos vides.
- Les lignes attachées ne suivaient pas les déplacements par fx de référence de leur ligne de base.
- Le bouton des médias de la bande de droite s'allumait sans montrer son panneau.
- Le premier projet « Sans titre » ouvert au lancement n'utilisait pas la couleur de fond réglée.
- Le premier clic sur le bouton Fx après la fermeture de la fenêtre d'installation de plug-in ne faisait rien.
- Glisser sur le canevas avec l'outil Découpe entière traçait un coup de pinceau.
- Se placer sur la piste « Centre » d'un flou radial couvrait le canevas d'un voile gris.
- Zoomer après un déplacement de la vue faisait sauter l'image pendant une trame.
- Dans le préréglage TVPaint, la touche + ne changeait pas la taille du pinceau.
- Ouvrir un fichier TVPaint à plusieurs clips affichait un faux avertissement.
- Le fantôme de pelure d'oignon d'une ligne à numéros de cellulo perdait son numéro.
- Les images et les calques vectoriels d'un fichier CLIP STUDIO étaient coupés au bord du canevas : une image posée au-delà n'apparaissait pas sur le fond, et déplacer le calque ne la ramenait pas.
- Dans un plan dont une ligne porte un plug-in fx, l'écran se figeait à répétition plus d'une seconde pendant la préparation des images pour la lecture.
- Un trait au stylet tracé pendant un long gel de l'écran perdait son début.
- En tamponnant une image retournée avec l'outil de découpe, le fantôme suivait le curseur avec retard.
- À la largeur minimale du panneau des réglages de l'outil, les lettres des boutons d'anticrénelage se chevauchaient et débordaient de leur case.
- Après le redémarrage de la carte graphique, une seconde notification demandait encore de redémarrer l'application.
- La lecture d'une vidéo s'arrêtait juste après un retour en arrière, le son exporté en MP4 perdait son tout début une fois rouvert, et les couleurs des vidéos exportées sous Windows étaient mal lues.
- Sous Windows, une vidéo comptait deux images de trop, et un saut affichait l'image située deux images plus tôt.
- Importer un JPEG aux informations de taille fausses fermait l'application.
