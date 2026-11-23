## What's new in this version

## Improved

- **The screen while you draw with the pen** — on tablets where many stroke steps pile up between two screen frames, the record of "what changed" ran short and the whole screen was redrawn. Now only what changed is redrawn, so drawing stutters less.
- **Panning while zoomed out** — panning the canvas below 100% redrew the whole screen. Now what is already drawn is shifted and only the newly uncovered part is drawn, so panning stutters less.
- **Picking a frame** — when you pick a frame again after moving or drawing on the canvas, the bottom dock and the Timesheet are no longer redrawn several times over for nothing.
- **Devices with low graphics limits** — the drawing engine asks the device only for what it actually uses. The canvas now opens on devices whose low limits kept it from opening at all (such as the Android emulator).
- **Lens blur at a large radius** — the work handed over at once is split to the device's speed, so the GPU no longer stops on a timeout on slow devices.

## Fixed

- Fixed the canvas view staying shifted instead of returning to its place after the screen was rotated and rotated back.
