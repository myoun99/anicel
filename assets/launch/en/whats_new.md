## What's new in this version

## New

- **Several timelines** — the timeline button on the conte panel's legend makes, opens, renames, duplicates and deletes timelines. Opening another timeline switches everything over, cuts and SE rows included. A synced cut, shared by two timelines, has a sync button of its own beside the link button.
- **Ruler markers** — double-click the ruler to place a marker with text, a color and a length. Drag it to move it; double-click it to edit or delete it.
- **Rasterize an fx** — the rasterize button on an fx group's or a transform's header bakes that one fx into the picture just as it shows. The button is off while no value has changed.
- **Gradient and continuous fill** — with "Gradient" on in the fill tool's settings, pick a range with a region or a lasso, then drag again to paint a gradient across it. "Continuous Fill" fills every region you pass over while holding down, all at once.
- **Stroke start and end** — "Start and end" in the brush settings makes a stroke's start and end thin and light. Clip Studio brushes bring their start and end settings with them.
- **Import TVPaint brushes** — bring in a BRUSH.tvpx exported from TVPaint's custom panel with "Import brushes".
- **XDTS timesheets** — the timesheet formats now include the XDTS viewer's four sheets (A3 6 seconds, B4 6 seconds, B4 3 seconds, Ponoc 6 seconds). Turn on "Ink output" when exporting XDTS and the timesheet's handwriting goes along, shown in the viewer.
- **Video in cel export** — the export window's Cels tab writes a video for each cut too (MP4, MOV or GIF). The Sequence tab's video formats gain GIF, and folders made by "Folders" take a prefix and a suffix.
- **Importing** — choose "New project" under "Into" in the import window to open the file in a new tab. Videos can come in as "Picture only" or "Sound only", and a video at another frame rate than the project's can be fitted to the project. Numbered files dropped together gather into one row, and each row can be switched off to leave it out.
- **GPU** — in Preferences ▸ System, choose the GPU the app uses (Automatic, Power saving, High performance; Windows) and see the name of the GPU in use. The Memory tab shows the video memory the app uses too.
- **Solo take** — the take button on the legend shows only the rows of the takes you pick.
- **Find by key** — in the keyboard shortcuts window, press the button beside the search box and type a key to find the actions that use it. When keys clash, the name of the other action shows beside the warning; press it to take the key off one side.
- **Selection and transform pills** — a finished selection gets a pill below it (deselect, invert, anti-alias), and the transform tool a pill below its box (anti-alias, flip horizontal, flip vertical, confirm, cancel). Mesh shows all its points before you touch it, and each point's position can be typed in the tool settings panel.
- **Color edit preview** — Binarize, Delete color and Keep color have a preview button, so you see the result on the canvas before running it.
- **Alt+wheel zoom** — on the timeline, X-sheet and conte panel, Alt+wheel zooms the frames in and out. A two-finger zoom holds the spot between the fingers.
- **Cut list** — the legend's first cell shows the current cut's name; press it to open a list of cuts, where cuts can be renamed too.

## Improved

- **A lighter app** — heavy work has moved to the graphics card and to threads of its own, so drawing, filling, transforming, playing and saving in a large cut stall the screen less. Scrolling and playing the timeline and conte are lighter too, and from the second launch on the "Preparing app" window clears in about a second.
- **Memory** — opening a large cut, filling over and over, and duplicating a timeline no longer make memory climb so far.
- **Mouse strokes** — a stroke drawn with the mouse in a heavy scene drags behind less.
- **Color mixing brushes** — a stroke with color mixing on stalls less as it crosses what is already painted.
- **Reset buttons** — a reset is on only when there is something to put back, and when on it wears the accent color. The canvas pill's rotate buttons stay their usual color; when the view is turned, the rotation reset lights up instead.
- **The wait window** — cutting, pasting, duplicating, confirming a transform and color edits across several pictures run behind the wait window; a single picture goes straight through with no window.
- **Linked cuts** — pasting a cut block linked makes a linked cut as it stands, length, camera keys and conte included. A linked cut's partners are written under its number in the timesheet header, and a linked cut's layers cannot be unlinked.
- **Trading pictures** — paste onto a block of an image layer or a synced row, or drag a block onto another row's block, and the block stays while only its picture changes. Dragging within a synced row onto the next block trades just the pictures as well.
- **Selections** — a selection started on an empty cell copies, cuts and pastes the same as one started on a block.
- **Layer rows** — make a folder with several layers picked and they go into it. Detach acts on every picked layer. A new attach layer lands just above or below the row you stand on, and the attach fold button is split into an upper and a lower half. A folded folder pastes folded.
- **Legend** — a color label solo picks by label alone, whatever the take. The conte legend's timeline button reads at the same size as a row's name.
- **SE** — an SE name tag on the canvas holds its name and type in one box. An SE block's name and line are single lines, and Enter closes the window with "OK". The timesheet no longer shades the empty rows of the SE column.
- **Sound rows** — the blend cell holds a speaker button and a total volume bar (up to 200). A sound row's opacity shows on the canvas while you drag it. The total volume is this bar alone: the "Total volume" lane in the audio fx group is gone.
- **Typing a bar's value** — double-click a row's opacity bar or a sound row's total volume bar and a number pad opens under it to type the value. The conte, the timeline and the X-sheet all work alike.
- **The timeline during playback** — buttons such as the frame pill no longer change while playing. Hover the red line of a block that crosses a cut's edge and a tooltip tells why.
- **Keyboard shortcuts window** — the window is larger, and under "Canvas › Tools" each tool is followed by its sub-tools. The scrollbar no longer overlaps the reset buttons. In the TVPaint preset, Alt-drag moves the view and Ctrl+Alt-drag turns it.
- **Brush pill on background panels** — with the main viewer or a sheet laid as the background, the same brush pill as the canvas's stands in the same place.
- **Cut tool** — choose "Display" or "Layer" under "Reference". "Display" cuts every visible layer just as it shows.
- **Fill tool** — holding down and moving slides the checker pattern along with the cursor.
- **Import defaults** — pictures come in at their original size. Long options no longer widen the import window. Importing a file of the same name again previews and brings in the new file. Kept files in the media pool show the date they were kept instead of a path.
- **Percent while opening and importing** — opening a project, or importing from the import window, the percent grows with how much of the file has been read. The bar no longer stands still while a file comes down from the cloud, and a .anicel file shows its percent from the start.
- **Frame rate** — 23.976 fps is marked "Recommended".
- **Export** — the video preview shows the same picture as the file it writes. Save As (PNG) prints the camera path, guides and onion skin as the canvas shows them. The Cels tab always has a scrollbar for layer folders, and exports the timesheets of every linked cut.
- **Color labels** — the "Art" process is gone. Paper labels start from the LO paper and take their stage's color, and a new image layer starts in the LO color.
- **Timesheet format** — with "Book names · repeats left out" on, overlapping books are written short, as BOOK1,2,3.
- **Direction layer** — a direction layer's drawing always shows above the drawing rows, and new drawing rows are added below the direction row.
- **Letters** — cel numbers and SE name tags are drawn as sharp as the pictures. Simplified Chinese in the conte prints at the same weight on screen and in PDF.
- **Merging image layers** — image layers merged together stay an image layer.
- **Sound in the viewer** — a sound file opens as two waveforms, the whole file and a close-up around the playhead. Press either to go there.
- **fx plugins** — a plugin that fails to draw shows ⚠ at the head of its row. Applying a plugin for the first time no longer stalls the app. "External FX plugin work limit" in Preferences has steps that are easier to read.
- **Graphics driver restarts** — unsaved drawing is kept when the driver restarts.
- **Moving the view** — overlays such as the camera frame move together with the picture when you pan or zoom. While transforming, a selection's outline follows the pixel edges.
- **Eyedropper** — pressing Alt in the middle of a drag switches to the eyedropper only once the drag ends.
- **Light mode** — the background color around the canvas stays as it is in light mode.
- **TVPaint cameras** — a TVPaint camera moving along a curved path comes in with only as many keys as the file has. Before, a key landed every few frames wherever the path bent.
- **Transforming large pictures** — a selection larger than the graphics card can handle at once can still be transformed with the transform tool, mesh included.
- **Voice recording** — noise suppression and the volume pass run on another thread when recording stops, so the screen no longer freezes at the end of a long take.

## Fixed

- **Android updates** — every app update wiped the settings and brought back the first-run window.
- **Closing on Windows** — the app kept running after its window was closed.
- **Exporting** — exporting a cut while the canvas stood on another cut sometimes closed the app.
- **Black frames in conte playback** — a black frame showed on the canvas as playback crossed from one cut to the next.
- **Strokes** — fast curves came out angular, mouse strokes in a heavy scene joined up in long straight lines, a stroke's first ink showed late, and anti-aliasing "None" wore away the grain of bitmap tips.
- **Holding Shift or Ctrl** — the key's auto-repeat came in as a new press, letting go of a Shift line or stopping playback.
- A layer in a linked cut could not be renamed, and a linked cut made by a linked paste did not come back with redo after an undo.
- After dragging layers into a new order, or adding and deleting them, blocks showed on the wrong rows.
- The last row of an attach group or a folder could not be dragged out of it.
- A folder row's block color broke off partway, and a line of block color showed above a block's corner triangles.
- Zooming out the page view mixed up the frame numbers.
- The handle at the top middle of a graph was hidden under its toolbar.
- A negative A/V offset barely moved the picture ahead.
- In a transform, pressing a handle moved the whole picture, the cursor turned into a hand while dragging with the pen, some rows did not follow when several rows were transformed together, and a small selection squeezed in perspective vanished.
- The color wheel did not follow pure black (#000000).
- With "Fill Beyond Canvas" off, a fill still ran out past the canvas.
- A blurred 1px line showed along the canvas edge, and a blur past the canvas was cut off at the picture's end.
- In linked cuts and synced attach rows, undo could show another row's picture or leave empty cels behind.
- Attach rows did not follow their base row's reference fx moves.
- The media button on the right strip lit up without showing its panel.
- The first "Untitled" project opened at launch did not use the background color you had set.
- The first click on the Fx button after closing the plugin install window did nothing.
- Dragging on the canvas with the whole cut tool drew a brush stroke.
- Standing on the "Centre" lane of a radial blur covered the canvas with a grey veil.
- Zooming after panning made the view jump for one frame.
- In the TVPaint preset, the + key did not change the brush size.
- Opening a TVPaint file with several clips showed a false warning.
- The onion skin ghost of a row with cel numbers left the number out.
- A CLIP STUDIO file's pictures and vector layers were cut at the canvas edge, so a picture kept past the canvas never showed on the pasteboard and moving the layer did not bring it back.
- In a cut with an fx plugin on a row, the screen kept stalling for over a second while pictures were prepared ahead for playback.
- A pen stroke drawn while the screen was frozen for a long time lost its beginning.
- Stamping a flipped picture with the cut tool, the ghost lagged behind the cursor.
- At the tool settings panel's narrowest width, the anti-alias buttons' letters overlapped and spilled out of their cell.
- Reading a video stopped right after rewinding it, sound exported to MP4 lost its first moment when opened again, and colors of videos exported on Windows were read wrong.
- On Windows, a video's frame count came out two too many, and a jump showed the picture from two frames before.
- Importing a JPEG with false size information closed the app.
