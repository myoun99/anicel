import 'dart:ui' as ui;

/// An image of next to nothing, rastered behind everything handed to the
/// raster thread before the call — what both fences are laid with.
Future<ui.Image> _rasteredBehind() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(
    recorder,
  ).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(1, 1);
  } finally {
    picture.dispose();
  }
}

/// Completes once the raster thread is past everything handed to it before
/// the call — not the GPU: what the thread handed on may still be running
/// there ([gpuBehind]).
Future<void> rasterThreadBehind() async {
  (await _rasteredBehind()).dispose();
}

/// Completes once the GPU has done everything handed to it before the call:
/// an image read back waits for every command before it.
///
/// 🔬2026-10-15 (the glass, release, 144Hz, a cut played from nothing
/// made): a playback making the raster thread had called done kept the GPU
/// busy 6.0ms more at the median, 18ms at p90 and 38ms at most.
Future<void> gpuBehind() async {
  final image = await _rasteredBehind();
  try {
    await image.toByteData();
  } finally {
    image.dispose();
  }
}
