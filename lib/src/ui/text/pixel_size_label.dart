/// A pixel size as a person reads it: `1920×1080` — the width first, the
/// multiplication sign between, no spaces.
///
/// 🚨ONE SPELLING (F-375, 2026-10-17): the import window's resolution
/// column (유저: 「1920x1080 이런 해상도」) made the seventh place to write
/// one. Five already wrote `1920×1080` — the size presets, the export
/// window's size, the project settings' camera and the cut piece in hand,
/// in every language — and the canvas's and the camera's adjust pills
/// alone wrote `1920 × 1080`.
String pixelSizeLabel(int width, int height) => '$width×$height';
