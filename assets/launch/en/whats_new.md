## What's new in this version

## New

- **Time by stage in the frame statistics** — the frame statistics (the Debug menu) split a screen's frame into its draw, the GPU finishing it and its show, and also show how many times a second the pen's input arrives and how long it takes to deal with.
- **Engine stages** — turn on "Engine Stages" under Debug in the settings, and the frame statistics show the GPU and CPU time the drawing engine spent at each place (compositing layers, keeping drawings, drawing the screen and others), and the share of each in the slowest frame. While it is on the app is slowed on purpose, so turn it on only to read the times.

## Improved

- **The canvas on Android** — on Android the drawing engine draws into a texture of its own before handing it to the screen, and draws again only where something changed. Drawing a stroke is lighter.
- **Drawing below 100% zoom** — with the zoom below 100%, places of one color alone, such as blank paper, a flat fill or the inside of a line, skip the shrinking sums. On the main PC that stage takes 28–39% less time.
- **Memory of resting cels** — once your hand rests, cels that are saved or put down to the session scratch let go of their copy in RAM, the cels of the frame the canvas stands on included. When a file is imported, the cels of the frame the canvas stands on go down to the disk like the others too. On the main PC the 172.6 MB those cels held went to 0.
- **Switching tools** — switching tools (ALT's eyedropper, swapping brush and eraser, temporary tools) no longer draws the sheet panel and the viewer again for nothing.
- **Folding and unfolding the timeline** — folding or unfolding a lane of the camera row no longer draws the whole film's V row and conte row again.
- **Progress while opening a document** — on Android, opening a document such as one on Drive, from the Open button or from Recent projects, fills the progress bar while it is copied into the app too (.anicel, .clip and others).

## Fixed

- Ten seconds into waiting for a file, "Nothing has arrived for N s" came up and the file then opened anyway. The wait now counts on in its own words, such as "Reading the file · N s", until it opens.
- Just after a recording began, before its first sound came in, drawing its row ended in an error. This is fixed.
