import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, visibleForTesting;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:gpu_engine/gpu_engine.dart';

/// What the canvas view shows the engine's screen on: a texture of the
/// view's size in device pixels, and the way a frame drawn on it reaches
/// Flutter (screen-on-the-engine c6) — two surfaces, each a texture of its
/// own, alternated, on Windows, iOS, macOS and Linux; a SurfaceProducer's
/// window on Android. The frame grids show their tiles through one already
/// (`TimelineGridScreenHost`, grid-on-the-engine ④).
// ⏳The canvas view's widget reads this at the end of the flip lane (관제 11-08 15:02 ⓐ):
// the live row's held pixels — the stroke being drawn in its CPU buffer,
// the selection's float, a lift's float, a fill's range — are drawn by the
// walk inside their row, under the rows above it, and the engine reads only
// its pool's tiles. A texture shown before those pixels are engine rows
// shows no stroke until pen-up, or lays a float over the rows above it;
// parting the walk from the engine by what is held is what CLAUDE.md's
// absolute rule 2 forbids.
sealed class ScreenTexture {
  ScreenTexture(this.width, this.height, {required int surfaces})
    : _bytes = width * height * 4 * surfaces {
    _liveBytes += _bytes;
  }

  /// What every screen open holds, in bytes, for the memory census
  /// (`every_counted_byte_is_censused`, 관제 2026-11-09 08:07 E①).
  static int get liveBytes => _liveBytes;
  static int _liveBytes = 0;

  final int _bytes;

  /// A texture of [width] × [height] device pixels on [engine], the
  /// platform's way.
  static Future<ScreenTexture> open(
    GpuEngine engine,
    int width,
    int height,
  ) async => Platform.isAndroid
      ? _WindowTexture(await engine.window(width, height), width, height)
      : _AlternatedTextures(engine, width, height);

  /// [surface] alone, presented onto and shown by no texture Flutter
  /// knows: what a test reads a screen back from ([GpuSurface.fingerprint])
  /// — `flutter test` registers no texture. The surface stays the test's.
  @visibleForTesting
  factory ScreenTexture.debugOnSurface(GpuSurface surface) = _SurfaceTexture;

  final int width;
  final int height;

  /// The id a `Texture` widget shows the frame last presented by.
  ValueListenable<int> get textureId;

  /// The id the frame [present] draws next is shown by: what a layer put
  /// down before the frame is presented shows it by.
  int get nextTextureId;

  /// [draw]s the next frame onto what Flutter is not showing, then shows
  /// it. [draw] waits for the GPU before it returns, as every kernel that
  /// writes a texture the screen shows does ([GpuScreen.show]): Flutter
  /// shows what it is handed as it is.
  void present(void Function(GpuTarget next) draw);

  /// Frees the texture, once Flutter shows it no more.
  Future<void> free() {
    _liveBytes -= _bytes;
    return _free();
  }

  Future<void> _free();
}

/// 🚨TWO TEXTURES, EACH REGISTERED ONCE, the widget switching between them
/// (gpu-engine-feasibility ⑤ — 보드/인프라, 11-06 03:00, an RTX 4080,
/// release, three runs): Flutter opens a texture again only when its
/// handle changes (external_texture_d3d.cc:84), so one texture's two slots
/// opened a handle at every frame — raster p50 0.99 · 1.18 · 0.86 ms
/// against 0.78 · 0.65 · 0.56 ms for two textures —, and one surface alone
/// is written while Flutter may still read it: nothing on Windows tells
/// either side the other is done.
final class _AlternatedTextures extends ScreenTexture {
  factory _AlternatedTextures(GpuEngine engine, int width, int height) {
    final surfaces = [
      for (var i = 0; i < 2; i++)
        engine.surface(width, height, bgra: _showsBgra),
    ];
    final textures = [
      for (final surface in surfaces) SharedTexture.register(surface),
    ];
    return _AlternatedTextures._(surfaces, textures, width, height);
  }

  _AlternatedTextures._(
    this._surfaces,
    this._textures,
    super.width,
    super.height,
  ) : _shown = ValueNotifier(_textures.first.id),
      super(surfaces: _surfaces.length);

  /// Whether Flutter shows a BGRA surface here: Apple's Flutter shows
  /// 32BGRA alone among RGB layouts (rust/src/platform/apple.rs), Linux's
  /// GL texture is GL_RGBA8 alone (rust/src/platform/linux.rs), and on
  /// Windows the screen's bytes matched the GPU's in BGRA and not in RGBA
  /// (gpu-engine-feasibility ⑤, three runs: BGRA MATCH 3ed77c11, RGBA
  /// MISMATCH e20eea22).
  static final bool _showsBgra = !Platform.isLinux;

  final List<GpuSurface> _surfaces;
  final List<SharedTexture> _textures;
  final ValueNotifier<int> _shown;

  /// The surface the next frame is drawn on: the one not shown.
  int _next = 0;

  @override
  ValueListenable<int> get textureId => _shown;

  @override
  int get nextTextureId => _textures[_next].id;

  @override
  void present(void Function(GpuTarget next) draw) {
    draw(_surfaces[_next]);
    final texture = _textures[_next];
    texture.show(0);
    _shown.value = texture.id;
    _next = 1 - _next;
  }

  @override
  Future<void> _free() async {
    for (final texture in _textures) {
      texture.unregister();
    }
    await SchedulerBinding.instance.endOfFrame;
    for (final surface in _surfaces) {
      surface.free();
    }
    _shown.dispose();
  }
}

final class _SurfaceTexture extends ScreenTexture {
  _SurfaceTexture(this._surface)
    : super(_surface.width, _surface.height, surfaces: 1);

  final GpuSurface _surface;
  final ValueNotifier<int> _id = ValueNotifier(0);

  @override
  ValueListenable<int> get textureId => _id;

  @override
  int get nextTextureId => 0;

  @override
  void present(void Function(GpuTarget next) draw) => draw(_surface);

  @override
  Future<void> _free() async => _id.dispose();
}

/// Android's: the engine presents into a SurfaceProducer's window, whose
/// images Flutter shows without a copy — its swapchain keeps the image
/// drawn on apart from the one shown.
final class _WindowTexture extends ScreenTexture {
  // ⚠️Two is the image drawn on and the one shown, the least it can be: how
  // many its queue keeps is Android's, and the census does not read a
  // texture there (`texturesAreInTheRamFigure`).
  _WindowTexture(this._window, super.width, super.height)
    : _id = ValueNotifier(_window.textureId),
      super(surfaces: 2);

  final GpuWindow _window;
  final ValueNotifier<int> _id;

  @override
  ValueListenable<int> get textureId => _id;

  @override
  int get nextTextureId => _window.textureId;

  @override
  void present(void Function(GpuTarget next) draw) {
    draw(_window);
    _window.present();
  }

  @override
  Future<void> _free() async {
    _id.dispose();
    await _window.free();
  }
}
