# Anicel

Anicel is a Flutter/Dart 2D bitmap animation tool targeting a TVPaint-style production workflow.

**License: all rights reserved.** This repository is public so the source
can be read and so CI can build it on every platform — that is not a
grant of rights. See [LICENSE](LICENSE) and [THIRD_PARTY.md](THIRD_PARTY.md).

## Color space

Anicel's working color space is **sRGB** — every brush, fill and
composite treats its 8-bit RGBA bytes as sRGB, matching the drawing
stage of professional 2D pipelines (TVPaint/CSP); delivery color
conversion (Rec.709, DCI-P3, ACES) belongs to the downstream
compositing step. Exported PNG sequences are tagged with the standard
`sRGB`/`gAMA`/`cHRM` chunks so other tools interpret the colors
identically instead of guessing.
