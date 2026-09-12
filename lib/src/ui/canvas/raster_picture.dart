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
///
/// 🚨★★★WHAT COMES BACK IS NOT PIXELS. IT IS A RECIPE THAT PINS ITS INPUTS
/// FOR ITS WHOLE LIFE. Read from the engine source (2026-09-13, Flutter
/// 3.44.2 / engine 77e2e94772,
/// `lib/ui/painting/display_list_deferred_image_gpu_skia.cc`): the
/// deferred image keeps the picture's display list until the IMAGE is
/// released — after rasterization too, so `OnGrContextCreated` can
/// rasterize it again when the GPU context is lost — and that list holds a
/// reference to every image the picture drew. Three consequences, and each
/// has already cost this app:
/// · Every image drawn into a KEPT result stays resident for as long as
///   the result is kept, whether or not anything else still needs it, and
///   a census that counts the result counts none of them.
/// · A result drawn from a PREVIOUS result of the same kind pins that one,
///   which pins the one before it — a chain, one whole image per link,
///   released only when the head is and then recursively on the raster
///   thread (2026-09-09: stack overflow at ~2,470 links; 2026-09-12: 17GB
///   in two minutes of drawing). Every such chain owes a budget in BOTH
///   units — links for the stack, bytes for memory — and `DisplayBufferCache`
///   is the shape to copy.
/// · `dispose()` on an image inside such a chain releases the Dart handle
///   and nothing else.
/// `Picture.toImage()` (async) is a plain snapshot and pins nothing; it is
/// the answer wherever a frame of latency is acceptable — and, through
/// [rasterPictureAndSnapshot], the way the display buffer stopped forming
/// a chain at all (2026-09-13): the deferred image is only ever DRAWN, and
/// the snapshot of the same picture is what the next paint derives from.
ui.Image rasterPicture(ui.PictureRecorder recorder, int width, int height) =>
    withPicture(recorder, (picture) => picture.toImageSync(width, height));

/// [rasterPicture]'s deferred image, plus — when [snapshot] — a plain
/// `toImage` of the SAME picture, started before the picture is released.
///
/// ⛔Same picture, same pixels: the two are one recording rasterized
/// twice, so whatever describes one (the live-surface tokens it was made
/// from) describes the other, and the caller may keep them as a pair
/// without a second measurement. The `Future` is safe across the picture's
/// disposal — `Picture::toImage` captures the display list in its own
/// raster task (`picture.cc`, `DoRasterizeToImage`).
({ui.Image deferred, Future<ui.Image>? real}) rasterPictureAndSnapshot(
  ui.PictureRecorder recorder,
  int width,
  int height, {
  required bool snapshot,
}) => withPicture(
  recorder,
  (picture) => (
    deferred: picture.toImageSync(width, height),
    real: snapshot ? picture.toImage(width, height) : null,
  ),
);

/// Ends [recorder], hands the picture to [use], and releases it whatever
/// [use] does — the one `finally` every raster above shares.
T withPicture<T>(ui.PictureRecorder recorder, T Function(ui.Picture) use) {
  final picture = recorder.endRecording();
  try {
    return use(picture);
  } finally {
    picture.dispose();
  }
}
