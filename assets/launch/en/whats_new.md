## What's new in this version

## New

- **"Add files" and "Add folder" in the import window** — Files and folders can be added while the import window stands. They call the same entrance as "Open file" and "Open folder" on the top strip.
- **Everything through the import window** — Brushes, fonts, palettes, effect plugins and shortcut files come in through the same import window as media.
- **Why a file could not be read** — The warning for a file that could not be imported now also says why the app that handed it over refused, how far the file arrived, and what kept a PSD from being read.
- **Cursor "None"** — "None" can be chosen for the cursor in the display settings. Neither the system cursor nor the app's cursor shows over the canvas.
- **Scroll and zoom kept per cut and per timeline** — The timeline panel's and the sheet's scroll are kept for each cut, and the storyboard's scroll and zoom for each timeline, and saved. SE and camera sections hidden from the timeline toolbar stay hidden when the project is opened again.
- **The layer delete window** — It lists the layers a delete takes along, those in cuts of other timelines too, by their cut.

## Improved

- **Strokes right after launch** — What the drawing engine compiled was kept only on Windows; it is kept on every platform now. The first strokes, heavy while it compiled again at every launch, are lighter from the second launch on.
- **Lifting the pen** — The tiles a stroke already drew are handed to the cel as they are, so lifting the pen no longer waits on the GPU.
- **Memory on Android** — The app's fonts are read straight from the APK, saving about 70 MB that copies of them took.
- **The import window's progress** — For PDF, sound and picture files, the progress fills as far as the file has actually been read. A PDF is opened only once.
- **Switching cuts and timelines** — Switching a cut or a timeline no longer throws away and rebuilds every row of the timeline and storyboard panels.
- **Moving the pointer** — Less is redrawn while the pointer moves over dock tabs, panel headers and the timeline bar.
- **The export queue** — A job's row holds the place of its progress bar from the start, so its height does not change while the job gets ready.
- **The debug window** — It shows an input inspector, the memory mappings holding the most private memory, and the playback warmer's pace.

## Fixed

- A fast vertical scroll of the timeline, coming to rest, showed a dialogue's ground or a row's cell bars gone for a frame or more. Fixed.
- Deleting a layer pasted linked into its own cut deleted its source with it. Only that layer is deleted now (between shared cuts it is as before).
- Selecting a layer together with its linked copy and deleting them gave an error. Fixed.
- In a shared cut, rasterizing did nothing when another cut's use of a layer showed a different picture. Fixed. A notice now says when layers were left as references.
- Finishing a lasso while the app had stalled for a moment closed the selection straight back to its start, or selected nothing. Fixed.
- Turning the transform box, a text, the angle dial and the like while the app stalled for a moment read the turn backwards. Fixed.
- On Android, a keyboard Ctrl+Z did nothing until a letter key had been pressed once. Fixed.
- On Android, picking numbered pictures together from Drive and the like brought in only the first. Fixed.
