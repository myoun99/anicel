## Nouveautés de cette version

## Nouveau

- **Le temps par étape dans les statistiques des images** — les Statistiques des images (menu Debug) partagent une image de l'écran entre son dessin, sa finition par le GPU et son affichage, et montrent aussi combien de fois par seconde arrive la saisie du stylet et le temps qu'il faut pour la traiter.
- **Temps du moteur par étape** — activez « Temps du moteur par étape » sous Debug dans les réglages, et les statistiques des images montrent le temps GPU et CPU que le moteur de dessin a passé à chaque endroit (composition des calques, conservation des dessins, dessin de l'écran et d'autres), ainsi que la part de chacun dans l'image la plus lente. Tant qu'il est activé, l'application est ralentie exprès : ne l'activez que pour lire les temps.

## Améliorations

- **Le canevas sous Android** — sous Android, le moteur de dessin dessine dans une texture à lui avant de la passer à l'écran, et ne redessine que là où quelque chose a changé. Tracer un trait est plus léger.
- **Dessiner sous 100 % de zoom** — avec un zoom sous 100 %, les endroits d'une seule couleur, comme le papier vierge, un aplat ou l'intérieur d'un trait, sautent les calculs de réduction. Sur le PC principal, cette étape prend 28 à 39 % de temps en moins.
- **Mémoire des cellulos au repos** — dès que la main se repose, les cellulos enregistrés ou déposés dans l'Espace de session libèrent leur copie en RAM, y compris ceux de l'image sur laquelle se tient le canevas. À l'import d'un fichier aussi, les cellulos de l'image sur laquelle se tient le canevas descendent sur le disque comme les autres. Sur le PC principal, les 172,6 Mo que tenaient ces cellulos sont tombés à 0.
- **Changer d'outil** — changer d'outil (la pipette d'ALT, alterner pinceau et gomme, les outils temporaires) ne redessine plus pour rien le panneau de feuille et la visionneuse.
- **Replier et déplier la timeline** — replier ou déplier une piste de la ligne caméra ne redessine plus la ligne V ni la ligne conte de tout le film.
- **La progression à l'ouverture d'un document** — sous Android, ouvrir un document, par exemple sur Drive, avec le bouton Ouvrir ou depuis les Projets récents, remplit la barre de progression aussi pendant sa copie dans l'application (.anicel, .clip et d'autres).

## Corrections

- Au bout de dix secondes d'attente d'un fichier, « Rien n'est arrivé depuis N s » s'affichait, puis le fichier s'ouvrait quand même. L'attente compte maintenant dans ses propres mots, comme « Lecture du fichier · N s », jusqu'à l'ouverture.
- Juste après le début d'un enregistrement, avant l'arrivée de son premier son, dessiner sa ligne se terminait par une erreur. C'est corrigé.
