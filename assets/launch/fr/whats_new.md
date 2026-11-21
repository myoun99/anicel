## Nouveautés de cette version

## Nouveau

- **Le relevé Wintab dans l'Inspecteur d'entrée** — sous Windows, les étapes par lesquelles l'application est passée en commençant à recevoir le stylet par Wintab sont gardées dans l'Inspecteur d'entrée (menu Debug). Si le stylet s'arrête, ce relevé montre où il s'est arrêté.

## Améliorations

- **Préparation de l'application au premier lancement** — la fenêtre « Préparation de l'application », qui s'était allongée au premier lancement d'une nouvelle version, retrouve à peu près sa durée d'autour du 13 novembre. Les lancements suivants restent courts comme avant.
- **Mémoire des dessins importés** — à l'import d'un fichier comme un .tvpp, chaque dessin est déposé dans l'Espace de session (le disque) dès son arrivée et libère sa RAM. Les dessins de l'image sur laquelle se tient le canevas restent tels quels. Avec un .tvpp de 220 dessins ouvert, « Cette application, en RAM » est passée de 2,26 Go à 0,96 Go (le PC principal). En échange, l'import prend environ deux secondes de plus.
- **Mémoire d'un cellulo modifié** — après l'ouverture d'un fichier, un trait sur un cellulo d'une image que la bande verte a remplie une fois ne fait grandir « Dessins » dans l'onglet mémoire que de la partie tracée, et non du cellulo entier. Les cellulos de l'image où l'on se tenait à l'ouverture du fichier restent comme avant pour l'instant.
- **Enregistrer après de nombreuses retouches** — la mémoire de l'application monte beaucoup moins pendant l'enregistrement après la retouche de nombreux cellulos. L'enregistrement après la retouche de 220 cellulos montait de 2,0 à 2,3 Go ; il monte maintenant d'environ 0,64 Go (le PC principal).
- **Réserve de tuiles** — le moteur de dessin ne met plus de côté la mémoire des tuiles qu'il a libérées pour la réutiliser, et la rend tout de suite. La ligne « Réserve de tuiles du moteur de dessin » de l'onglet mémoire a disparu.
- **Polices** — le moteur graphique lit les polices fournies avec l'application là où elles se trouvent, sans en garder une copie. Sous Windows, « Cette application, en RAM » a baissé d'environ 24 Mo. Android reste comme avant.
- **Images composées** — dès que la main se repose, les images composées de la lecture sont elles aussi repliées et prennent moins de mémoire graphique, et la ligne « Images composées » de l'onglet mémoire montre la taille qu'elles occupent vraiment. La bande verte se remplit d'autant plus dans la place libérée.
- **Le canevas sous Android** — sous Android, la fenêtre de l'application affiche son image sans attendre le tour du moteur graphique. Ceci a été revu pour que les traits au stylet, le panoramique et le zoom juste après l'ouverture d'un nouveau projet saccadent moins. Ce n'est pas encore mesuré sur un appareil.

## Corrections

- Avec une visionneuse ouverte, aller dans un autre onglet de projet (un onglet existant ou un onglet créé avec Ctrl+N) puis revenir gardait le numéro de page mais montrait l'image de la première page. Les visionneuses principale et secondaire reviennent maintenant à la page et au zoom qu'elles montraient.
