import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/screen_texture.dart' show ScreenTexture;

/// Every screen open, by the texture id its layer names: what a test reads
/// a screen back from ([screenDrawnAsAPicture]) — `flutter test` shows no
/// texture.
final Map<int, GpuSurface> shownScreens = {};

/// A surface of [width] × [height] as the platform makes the ones it
/// shows: RGBA where it can, else BGRA — Apple's make BGRA alone
/// (platform/apple.rs), Linux's RGBA alone.
GpuSurface shownSurfaceOf(int width, int height) => shownOf(
  ({required bgra}) => appGpuEngine.surface(width, height, bgra: bgra),
  '$width × $height',
);

/// What [make] makes RGBA, else BGRA — refused both ways, the refusal says
/// [what] was asked for and BOTH reasons.
///
/// ↩️It said only the second till 2026-11-16, and on Linux the second is
/// always the same: BGRA is not a format Flutter's GL texture shows. Every
/// refusal of a CI shard read `Bgra8Unorm is not a format…` while the RGBA
/// was refused for want of VK_EXT_image_drm_format_modifier, and then for a
/// screen past udmabuf's 64 MiB — two different causes behind one line, and
/// a session took the line for the cause (관제 2026-11-16, board
/// ci-linux-shards-cannot-make-a-shown-surface).
T shownOf<T>(T Function({required bool bgra}) make, String what) {
  try {
    return make(bgra: false);
  } on StateError catch (rgba) {
    try {
      return make(bgra: true);
    } on StateError catch (bgra) {
      throw GpuRefused(
        'no shown surface of $what — RGBA: ${rgba.message}; '
        'BGRA: ${bgra.message}',
      );
    }
  }
}

/// The screens of [shownScreens] that count the frames drawn on them, by
/// the same ids ([ScreenTexture.debugFramesDrawn]).
final Map<int, ScreenTexture> shownScreenTextures = {};

/// Each counting screen's pixels as last read back, and how many frames
/// had been drawn on it then.
final Map<int, ({ui.Image image, int drawn})> _readBack = {};

/// Lets go of what the screens were read back as — with the screens.
void forgetScreensReadBack() {
  for (final read in _readBack.values) {
    read.image.dispose();
  }
  _readBack.clear();
}

/// The layer showing [textureId]'s screen as it stands, one texel a device
/// pixel, through every layer above it as a texture is: `flutter test` shows
/// none, so its pixels are read back and drawn.
///
/// 🗣️READ BACK AGAIN ONLY ONCE A FRAME IS DRAWN ON IT (a-process-first-
/// test-never-sees-the-canvas-stand-Q2 = 「안 바뀐 화면은 다시 읽지
/// 않는다」, 유저 2026-11-20): every paint read the whole screen, and 🔬41%
/// of a run's reads were of a screen nothing had been drawn on since the
/// read before (서피스 11-20 — 9,346 reads, 1,104.7 s). A screen that
/// counts no frames — one a test opened its own way — is read every time.
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
  final drawn = shownScreenTextures[textureId]?.debugFramesDrawn;
  final image = drawn == null
      ? _readOf(surface)
      : _readOnceAFrame(textureId, surface, drawn);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    ui.Offset.zero &
        ui.Size(surface.width.toDouble(), surface.height.toDouble()),
    rect,
    ui.Paint()..filterQuality = filterQuality,
  );
  if (drawn == null) {
    image.dispose();
  }
  return PictureLayer(rect)..picture = recorder.endRecording();
}

/// [surface]'s pixels, read back.
ui.Image _readOf(GpuSurface surface) => pictureOf(
  PremultipliedRows.given(surface.read(), surface.width, surface.height),
);

/// [textureId]'s screen as read back when [drawn] frames had been drawn on
/// it — read again where more have since. Kept till the screens go
/// ([forgetScreensReadBack]).
ui.Image _readOnceAFrame(int textureId, GpuSurface surface, int drawn) {
  final kept = _readBack[textureId];
  if (kept != null && kept.drawn == drawn) {
    return kept.image;
  }
  // Out of the keeping before it is let go of: a read the device refuses
  // throws (`GpuReadFailed` — a test that loses its device reads on), and
  // the screens' end would let go of it again.
  _readBack.remove(textureId)?.image.dispose();
  final image = _readOf(surface);
  _readBack[textureId] = (image: image, drawn: drawn);
  return image;
}
