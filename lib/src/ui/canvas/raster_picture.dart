import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

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
///   units — links for the stack, bytes for memory — as the display buffer
///   kept both (↩️`DisplayBufferCache`, until one-picture-per-frame ②-5a).
/// · `dispose()` on an image inside such a chain releases the Dart handle
///   and nothing else.
/// `Picture.toImage()` (async) is a plain snapshot and pins nothing; it is
/// the answer wherever a frame of latency is acceptable. ↩️A deferred image
/// drawn and its plain snapshot kept, as a pair of one recording, is how the
/// display buffer stopped forming a chain at all (2026-09-13) — and how the
/// layer stack's row images were held — until neither was kept
/// (one-picture-per-frame ②-5a · ②-5b-1).
///
/// [inFloats] rasters it a float a channel (`rgbaFloat32`), for a picture
/// that holds numbers past a byte — a row sum's, an iris's table — where
/// the engine's own choice is a byte a channel.
ui.Image rasterPicture(
  ui.PictureRecorder recorder,
  int width,
  int height, {
  bool inFloats = false,
}) => withPicture(
  recorder,
  (picture) => picture.toImageSync(
    width,
    height,
    targetFormat: inFloats
        ? ui.TargetPixelFormat.rgbaFloat32
        : ui.TargetPixelFormat.dontCare,
  ),
);

/// [shader] over the whole of a [width]×[height] raster, rastered as
/// [rasterPicture] does — and laid as it gives it (`BlendMode.src`) where it
/// is [inFloats]: over an empty raster the default blend gives the same, but
/// a number past 1 is no colour a blend is promised to keep.
///
/// ⚠️The caller keeps [shader], and disposes it once this returns.
ui.Image shadedRaster(
  ui.Shader shader,
  int width,
  int height, {
  bool inFloats = false,
}) {
  final recorder = ui.PictureRecorder();
  final paint = ui.Paint()..shader = shader;
  if (inFloats) {
    paint.blendMode = ui.BlendMode.src;
  }
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    paint,
  );
  return rasterPicture(recorder, width, height, inFloats: inFloats);
}

/// [picture]'s plain snapshot, WAITED FOR — the tile compose's, spelled
/// once so that the waits can be counted ([debugOnWaitedSnapshot]). ↩️The
/// steps of a layer image's chain shared it (a halving, the cut of the ink)
/// and were waited for once, at the chain's last step, until no row image
/// was made (one-picture-per-frame ②-5b-1).
Future<ui.Image> waitedSnapshot(ui.Picture picture, int width, int height) {
  debugOnWaitedSnapshot?.call(width, height);
  return picture.toImage(width, height);
}

/// Told of every [waitedSnapshot], with the size it rasters.
@visibleForTesting
void Function(int width, int height)? debugOnWaitedSnapshot;

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
