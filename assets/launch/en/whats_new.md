## What's new in this version

## New

- **Guides in the AE script** — the AE script lays the camera's path and directions as guide layers over the canvas comp.
- **Effects in the AE script** — a row with Brightness & Contrast, Hue/Saturation, a Gaussian, Directional, Radial or Camera Lens Blur, or Color Key gets the nearest After Effects effect, with its values carried over.
- **Camera moves in the conte** — "Camera moves" in Conte sheet format chooses whether the cell grows or the move stays inside it. The default is "Keep in the cell": the cell keeps its size and shows the whole move scaled down. "Cut settings" under it overrides that for the current cut or the selected cuts alone.
- **Page view on the ruler** — the button at the timeline ruler's left corner chooses Frames, Seconds+frames or Pages. On Pages the numbers restart with each timesheet page, and the turn of a page reads like "p2". The Conte panel's ruler counts by conte sheet pages.
- **Lay a panel on the floor** — drag the Conte Sheet, Timesheet, Cut envelope or Sub Viewer to the top strip and it gets a button; pressing it lays that panel where the canvas sits. The canvas button brings the canvas back.

## Improved

- **Strokes on iPhone and iPad** — a stroke writes only what changed into the frame's picture instead of redrawing the whole frame, and pictures take half the memory. In exchange, P3 photos and videos display as sRGB.
- **Pencils** — the 2H, HB, 2B and 4B pencils, the colored pencil and the mechanical pencil are rebuilt. The pencil feel now comes from the brush tip rather than the paper texture, so the grain stays with the texture off. Brush presets now default to 5% spacing, and the old mechanical pencil stays on in the Pen group as Mechanical Pen. The new settings arrive with "Reset brush library".
- **Camera lines in the conte** — a move's line names its two keys, like "1f-5f T.U", or "A-B T.U" when they have names. FIX appears only before and after a camera move, and a cell where the camera does nothing stays blank. Turning the camera row off the sheet clears these lines and the timesheet's CAM column together. The camera rectangles in a cell are drawn at every key, as on the canvas.
- **Imported brushes** — a .sut brush's real tip is read, and its flow-by-spacing setting follows the file. Anti-aliasing no longer clears a tip's greys. Brushes imported before need importing again.

## Fixed

- **Strokes falling behind the cursor** — the longer the stroke, the further the line fell behind; it now keeps up.
- **Video import on Android** — importing a video left the preview black and made no new cut or layer.
- The AE script stopped at a cel with no picture, and a row's opacity went missing.
- Z straight lines in a row each take the pressure of the press before.
- The export's Cels tab leaves out cels with no picture, so its count matches the files written.
- Tapping a conte sheet's content cell in a cut with no storyboard layer now says why.
