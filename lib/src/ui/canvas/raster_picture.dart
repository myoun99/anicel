import 'dart:ui' as ui;

/// Ends [recorder] and rasters its picture to a [width]×[height] image,
/// synchronously — the ONE spelling of a step that was copied eight times.
///
/// 🚨`toImageSync` THROWS (an engine without a GPU context, a size the
/// backend refuses), and each copy of this had its own memory of that: the
/// display buffer's, the effect chain's, the provisional tile's, the
/// stand-in's. A dispose written on the line after the raster runs only
/// when the raster did not throw, so every copy that forgot the `finally`
/// kept its picture — and the clone gate counted the ones that remembered
/// as copies of each other (2026-09-11, 88 → 91). One body, one `finally`,
/// and a caller that needs to release something ELSE on the same throw
/// (the effect chain's shader) wraps this in its own.
ui.Image rasterPicture(ui.PictureRecorder recorder, int width, int height) {
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(width, height);
  } finally {
    picture.dispose();
  }
}
