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
    PremultipliedRows(surface.read(), surface.width, surface.height),
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
