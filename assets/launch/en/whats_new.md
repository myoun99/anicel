## What's new in this version

## Improved

- **Drawing with a pen where the GPU falls behind** — A stroke is handed to the drawing engine once per screen frame. When the screen cannot keep up, stroke work no longer piles up on the GPU and slows the canvas down.
- **The canvas on Android** — The canvas is shown the same way as on every other platform. That difference was why the canvas, all but the camera, jumped a frame when a pen touched down after a pan.
- **Some Android devices** — Where the drawing engine cannot write into the screen's buffer directly, the canvas is shown by copying over only what changed.
- **The frame stats screen** — It shows a stroke's steps, the GPU's backlog and memory, the time to a stroke's first step and from lifting the pen to its save, and the way the canvas is shown with a check of it.

## Fixed

- Narrowing one side of the transform box to nearly a point showed the preview unwarped, and pressing Enter made the picture vanish. Fixed.
