import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/rendering.dart' show Layer, TextureLayer;
import 'dart:ui' show FilterQuality, Offset, Rect, Size;
import 'package:gpu_engine/gpu_engine.dart';

import '../native/app_gpu_engine.dart';
import '../native/screen_texture.dart';

/// How a screen's texture is opened: [ScreenTexture.open]. A test reads one
/// back through [ScreenTexture.debugOnSurface].
@visibleForTesting
Future<ScreenTexture> Function(GpuEngine engine, int width, int height)
debugOpenEngineScreen = ScreenTexture.open;

/// The layer a screen's texture is shown by. A test's draws what the texture
/// holds, read back: `flutter test` shows no texture.
@visibleForTesting
Layer Function({
  required Rect rect,
  required int textureId,
  required FilterQuality filterQuality,
})
debugLayerOfScreen = TextureLayer.new;

/// The step a screen's sides are rounded up to, in device pixels
/// (grid-on-the-engine ④ D1 ⑥, 관제 2026-11-09 08:07 E②): a panel dragged a
/// pixel at a time opens another texture once in this far, not at every
/// pixel.
const int _screenSideStep = 512;

/// THE TEXTURE A BOX OF THE ENGINE'S PIXELS IS SHOWN THROUGH: opened once
/// the app's engine is open ([appGpuEngineOpen]) and the box [asks] for one,
/// its sides rounded up from what is [want]ed, and opened again where that
/// outgrows it — the one it replaces freed once it is shown no more.
///
/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」 — let go of with the engine it was
/// opened on, and opened again on the next ([StandsOnTheAppsEngine]): a
/// device shows nothing of another's.
final class EngineScreenTexture {
  /// A texture for a box that [asks] for one, [opened] telling that one has
  /// just been opened on an engine, [letGo] that the one open went with its
  /// engine, and [putUp] that a frame the GPU finished is up on it
  /// ([ScreenTexture.putUp]) — the box shows it by a paint, and draws the
  /// newest asked for meanwhile where it is [behind].
  EngineScreenTexture({
    required bool Function() asks,
    required void Function(GpuEngine engine) opened,
    required void Function() letGo,
    required void Function({required bool behind}) putUp,
  }) : _asks = asks,
       _opened = opened,
       _letGo = letGo,
       _putUp = putUp;

  final bool Function() _asks;
  final void Function(GpuEngine engine) _opened;
  final void Function() _letGo;
  final void Function({required bool behind}) _putUp;

  late final StandsOnTheAppsEngine _onTheEngine = StandsOnTheAppsEngine(
    letGo: _wentWithItsEngine,
    opened: (_) => unawaited(open()),
  );

  /// The texture open, if any.
  ScreenTexture? get texture => _texture;
  ScreenTexture? _texture;

  /// What the texture has to hold, in device pixels.
  /// The size the texture is to hold, in device pixels.
  (int, int) wanted = (0, 0);

  /// The size a texture is being opened at.
  (int, int)? _opening;
  bool _stopped = false;

  /// Whether the texture open holds what is wanted.
  bool get holdsWhatIsWanted {
    final (width, height) = wanted;
    final texture = _texture;
    return texture != null &&
        texture.width >= width &&
        texture.height >= height;
  }

  /// [draw] presented on the texture open, [draw] told its size — and the
  /// layer of the frame up on it, from [offset], one texel a device pixel:
  /// the one drawn, once the GPU has finished it ([ScreenTexture.present]).
  Layer presented(
    void Function(GpuTarget next, (int, int) size) draw, {
    required Offset offset,
    required double devicePixelRatio,
  }) {
    final texture = _texture!;
    texture.present((next) => draw(next, (texture.width, texture.height)));
    // After it is presented: a frame that failed, or is still being drawn,
    // stands as it stood.
    return _layerOf(texture, offset, devicePixelRatio);
  }

  /// The frame the texture open shows already, nothing drawn, by a layer
  /// as [presented]'s: null where none has been presented on it.
  Layer? standing({required Offset offset, required double devicePixelRatio}) {
    final texture = _texture;
    return texture == null || !texture.showsAFrame
        ? null
        : _layerOf(texture, offset, devicePixelRatio);
  }

  /// What [texture] shows now, from [offset], one texel a device pixel.
  static Layer _layerOf(
    ScreenTexture texture,
    Offset offset,
    double devicePixelRatio,
  ) => debugLayerOfScreen(
    rect:
        offset &
        Size(
          texture.width / devicePixelRatio,
          texture.height / devicePixelRatio,
        ),
    textureId: texture.textureId.value,
    filterQuality: FilterQuality.none,
  );

  void start() => _onTheEngine.start();

  void stop() {
    _stopped = true;
    _onTheEngine.stop();
    _freed();
  }

  /// The engine the texture was opened on is the app's no more: neither is
  /// the texture the box's, nor one being opened there, and the box is told.
  void _wentWithItsEngine() {
    _opening = null;
    _freed();
    _letGo();
  }

  /// The texture open is the box's no more, freed once it is shown no more.
  void _freed() {
    final texture = _texture;
    _texture = null;
    unawaited(texture?.free());
  }

  static int _steppedUp(int side) =>
      (side + _screenSideStep - 1) ~/ _screenSideStep * _screenSideStep;

  /// The size to open a texture at: null where one is being opened at it,
  /// or none is to be — the engine shut, the box not asking, nothing to
  /// show, or the one held holds it.
  (int, int)? get _toOpen {
    final (width, height) = wanted;
    if (appGpuEngineOpen.value == null ||
        !_asks() ||
        holdsWhatIsWanted ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    final size = (_steppedUp(width), _steppedUp(height));
    return size == _opening ? null : size;
  }

  /// Opens the texture [_toOpen] says; the one it replaces is freed once it
  /// is shown no more.
  Future<void> open() async {
    final engine = appGpuEngineOpen.value;
    final asked = _toOpen;
    if (engine == null || asked == null) {
      return;
    }
    final held = _texture;
    _opening = asked;
    final (width, height) = asked;
    final opened = await debugOpenEngineScreen(engine, width, height);
    // ⚠️Asked of the engine too: one opened on an engine let go meanwhile
    // comes at the size the next is being opened at.
    if (_stopped ||
        _opening != asked ||
        !identical(engine, appGpuEngineOpen.value)) {
      await opened.free();
      return;
    }
    _opening = null;
    _texture = opened..putUp = _putUp;
    _opened(engine);
    await held?.free();
  }
}
