/// A pixel size as a person reads it: `1920×1080` — the width first, the
/// multiplication sign between, no spaces.
///
/// 🚨ONE SPELLING (F-375, 2026-10-17): the import window's resolution
/// column (유저: 「1920x1080 이런 해상도」) made the seventh place to write
/// one. Four already wrote `1920×1080` — the size presets, and in every
/// language the camera's and the canvas's export sizes (the camera's also
/// in the project settings) and the cut piece in hand — and the canvas's
/// and the camera's adjust pills alone wrote `1920 × 1080`.
String pixelSizeLabel(int width, int height) => '$width×$height';
