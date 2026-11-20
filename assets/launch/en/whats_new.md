## What's new in this version

## New

- **Sound row presets** — the top of a sound row's Fx list offers presets (Dialogue, Music, Sound effects, Ambience). Picking one puts a set of effects tuned for that sound (an equalizer, a compressor and so on) on the row at once; after that they are the row's own, and their values can be changed.
- **Noise removal** — the Audio section of a sound row's Fx menu gains Noise removal. One value sets how much of the cleaned sound is heard; just added, it is 0 and leaves the sound unchanged. It works on 44.1 kHz and 96 kHz sound too.
- **Sync to preset** — the window that opens from a file's in-use mark in the media pool gains "Sync to preset". Pick the places already laid that differ from the file's placement preset and bring values such as start, length and fit back to the preset, or use "Apply to all" for every place that differs. It works for sounds, movies and pictures alike.
- **Fit the picture to a new canvas size** — the Canvas size window, and the pill when adjusting on the canvas, can fit the picture to the new canvas with "Fit, keep ratio" or "Stretch, ignore ratio". By default the picture stays as it is, as before.
- **Canvas size for several cuts** — select several cut blocks and change the canvas size, and every selected cut changes at once, in one undo step.
- **Changing a layer's kind** — press a picture row's kind icon to turn the row between Image, Animation and Storyboard. A kind the row cannot become is shown disabled. Press it among several selected rows and they all change. The Layer menu's storyboard toggle has moved to this button.
- **Thinning with the lead edge** — pulling a frame block's lead edge backwards thins the blocks out by the frames pulled (one frame: 1, 3, 5, 7…; two frames: 1, 4, 7…). In the conte panel, pulling a cut's lead edge past the cut's end deletes the cut.
- **Stamp spacing** — the stamp tool's settings gain Spacing, a share of the piece's size; one whole piece by default.
- **Size of cel export movies** — movies on the export window's Cels tab gain a Size (Camera, Canvas). Camera is the default.
- **XDTS target** — with XDTS picked in the timesheet format, the target to export (key drawings, in-betweens) is picked below it. Pick one and only that is written.

## Improved

- **A lighter app** — less hitching while playback pictures are baked ahead (while the green band fills), lighter mouse-wheel scrolling and layer eye toggles on the timeline, and no more waiting on the graphics engine at every stroke. Cuts with a cel number fx, dragging an fx value, the stall at the end of opening a large .anicel, and opening a .tvpp are lighter too.
- **Dragging a blur value** — the screen hitches less as a blur value starts to be dragged, and less while it is dragged.
- **While picking a color** — turning the color wheel of a lane, or of the paper, the backdrop or the pasteboard, shows the color as it goes and records it once, when the window closes, as one undo step.
- **Stamp drags** — a row of stamps laid by one drag goes back with a single Ctrl+Z. Stamps across several cels are laid behind the wait window.
- **Continuous fill and stamp drags** — even if the screen stalls for a moment, every region passed meanwhile is filled, and a row of stamps follows the path as drawn.
- **Camera instructions on the conte paper** — a camera move shared by two panels is written in each panel for its own part (for example 1f-73f T.B and 74f-144f T.B). A cut of one panel writes the whole cut in the same words as its timesheet.
- **Cel export** — a storyboard block with no name is still exported, filed under the next free number (the block's name in the project stays as it is). Filtering by color label leaves rows with no label out of the export list. The export window's folding sections start open.
- **View shortcuts on the floor panel** — zoom and rotate shortcuts work on a timesheet or viewer laid on the floor too.
- **Pasting into S rows** — frames copied from a regular layer are not pasted into an S row, nor S row frames into a regular layer; the paste buttons turn off then.
- **TVPaint import** — when a sound file is not where the .tvpp recorded it, it is looked for under the file's folder. Layer instance names in Hangul, kana or other letters come in as written, and each layer's blending mode (Multiply and so on) comes in too.
- **When the graphics device stops** — on Windows, if the graphics device that draws the screen stops, a window offers "Save and restart", "Quit without saving" or close.
- **Media pool scrollbars** — the media pool's scrollbars are always shown, in the list view and the icon view.
- **The tool list** — tool names in the tool settings panel stand on one line, cut with an ellipsis when they do not fit; the tooltip shows the whole name.

## Fixed

- After undoing every step of a transform box, a change was still held and the selection outline stayed red.
- Once the undo history was full, gestures made of several steps, such as a stamp drag, no longer went back in one undo.
- Dragging stamps could drop the last stamp.
- When editing several selected blocks at once, such as lengthening their frames, the selection rectangle did not follow the blocks.
- Moving to a frame whose green band an edit had emptied showed the picture, but the band did not fill again.
- When a canvas size change moved the anchor, effect points (a radial blur's center, a cel number's place and so on) did not follow the picture.
- Dragging a blur value grew memory by gigabytes, and it did not come back after the blur was removed.
- In the export window's preview, moving between frames showed a black screen until the next picture came, and a new loading ring showed as a small dot.
- In the export window, an XDTS sheet with only in-betweens picked showed as a blank screen.
- A take recorded with noise suppression on was laid slightly late, out of step with the mouth.
- Deleting colors across several blocks made the progress window look stuck; the percentage now fills.
- Widening the panel while the media pool list was scrolled to its far side left the columns and scrollbar shifted.
- With the sub-tool list open, the lower rows of the tool settings panel (continuous fill, gradient and so on) were cut off and could not be scrolled to.
