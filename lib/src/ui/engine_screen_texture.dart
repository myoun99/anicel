import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import '../native/app_gpu_engine.dart';
import '../native/screen_texture.dart';

/// How a screen's texture is opened: [ScreenTexture.open]. A test reads one
/// back through [ScreenTexture.debugOnSurface].
@visibleForTesting
Future<ScreenTexture> Function(GpuEngine engine, int width, int height)
debugOpenEngineScreen = ScreenTexture.open;

/// The step a screen's sides are rounded up to, in device pixels
/// (grid-on-the-engine ④ D1 ⑥, 관제 2026-11-09 08:07 E②): a panel dragged a
/// pixel at a time opens another texture once in this far, not at every
/// pixel.
const int _screenSideStep = 512;

/// THE TEXTURE A BOX OF THE ENGINE'S PIXELS IS SHOWN THROUGH: opened once
/// the app's engine is open ([appGpuEngineOpen]) and the box [asks] for one,
/// its sides rounded up from what is [want]ed, and opened again where that
/// outgrows it — the one it replaces freed once it is shown no more.
final class EngineScreenTexture {
  /// A texture for a box that [asks] for one, [opened] telling that one has
  /// just been opened on an engine.
  EngineScreenTexture({
    required bool Function() asks,
    required void Function(GpuEngine engine) opened,
  }) : _asks = asks,
       _opened = opened;

  final bool Function() _asks;
  final void Function(GpuEngine engine) _opened;

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

  void start() => appGpuEngineOpen.addListener(open);

  void stop() {
    _stopped = true;
    appGpuEngineOpen.removeListener(open);
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
    if (_stopped || _opening != asked) {
      await opened.free();
      return;
    }
    _opening = null;
    _texture = opened;
    _opened(engine);
    await held?.free();
  }
}
