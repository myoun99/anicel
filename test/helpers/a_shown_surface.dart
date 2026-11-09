import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';

/// Every screen open, by the texture id its layer names: what a test reads
/// a screen back from ([screenDrawnAsAPicture]) — `flutter test` shows no
/// texture.
final Map<int, GpuSurface> shownScreens = {};

/// A surface of [width] × [height] as the platform makes the ones it
/// shows: RGBA where it can, else BGRA — Apple's make BGRA alone
/// (platform/apple.rs), Linux's RGBA alone.
GpuSurface shownSurfaceOf(int width, int height) {
  try {
    return appGpuEngine.surface(width, height, bgra: false);
  } on StateError {
    return appGpuEngine.surface(width, height, bgra: true);
  }
}

/// The layer showing [textureId]'s screen as it stands, one texel a device
/// pixel, through every layer above it as a texture is: `flutter test` shows
/// none, so its pixels are read back and drawn.
Layer screenDrawnAsAPicture({
  required ui.Rect rect,
  required int textureId,
  required ui.FilterQuality filterQuality,
}) {
  final surface = shownScreens[textureId];
  if (surface == null) {
    return TextureLayer(
      rect: rect,
      textureId: textureId,
      filterQuality: filterQuality,
    );
  }
  final image = pictureOf(
    _ScreenRead(surface.width, surface.height, surface.read()),
  );
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    ui.Offset.zero &
        ui.Size(surface.width.toDouble(), surface.height.toDouble()),
    rect,
    ui.Paint()..filterQuality = filterQuality,
  );
  image.dispose();
  return PictureLayer(rect)..picture = recorder.endRecording();
}

/// A screen's pixels read back, premultiplied, for the door to a picture.
final class _ScreenRead implements PictureBytes {
  _ScreenRead(this.width, this.height, this._premultiplied);

  @override
  final int width;
  @override
  final int height;
  final Uint8List _premultiplied;

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) =>
      use(_premultiplied);

  /// Each channel rounded back: the door's premultiply of it is the channel
  /// it came from, to the level, at every alpha.
  @override
  T readStraight<T>(T Function(Uint8List straight) use) {
    final straight = Uint8List(_premultiplied.length);
    for (var at = 0; at < straight.length; at += 4) {
      final alpha = _premultiplied[at + 3];
      straight[at + 3] = alpha;
      if (alpha == 0) {
        continue;
      }
      for (var channel = at; channel < at + 3; channel += 1) {
        straight[channel] = math.min(
          255,
          (_premultiplied[channel] * 510 + alpha) ~/ (2 * alpha),
        );
      }
    }
    return use(straight);
  }
}
