import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/rendering.dart' show Layer, TextureLayer;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
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

/// Where a box lays the frame up on its texture
/// ([EngineScreenTexture.presented], [EngineScreenTexture.standing]): its
/// corner [from] what that frame was drawn for
/// ([ScreenTexture.shownFor]; null where none is up), one texel a device
/// pixel of [devicePixelRatio].
typedef FramePlace = ({
  Offset Function(Object? shownFor) from,
  double devicePixelRatio,
});

/// THE TEXTURE A BOX OF THE ENGINE'S PIXELS IS SHOWN THROUGH: opened once
/// the app's engine is open ([appGpuEngineOpen]) and the box [asks] for one,
/// its sides rounded up from what is [want]ed, and opened again where that
/// outgrows it — the one it replaces handed on or freed.
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
  /// newest asked for meanwhile where it is [behind]. Its sides are rounded
  /// up a [sideStep]; one it outgrows is handed to [replaced] where that
  /// shows a frame, else freed once it is shown no more.
  EngineScreenTexture({
    required bool Function() asks,
    required void Function(GpuEngine engine) opened,
    required void Function() letGo,
    required void Function({required bool behind}) putUp,
    int? sideStep,
    void Function(ScreenTexture outgrown)? replaced,
  }) : _asks = asks,
       _opened = opened,
       _letGo = letGo,
       _putUp = putUp,
       _replaced = replaced,
       sideStep = sideStep ?? _screenSideStep;

  final bool Function() _asks;
  final void Function(GpuEngine engine) _opened;
  final void Function() _letGo;
  final void Function({required bool behind}) _putUp;
  final void Function(ScreenTexture outgrown)? _replaced;

  /// The step the texture's sides are rounded up to, in device pixels.
  final int sideStep;

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

  /// [draw] presented on the texture open, [draw] told its size, as drawn
  /// for [drawnFor] — and the layer of the frame up on it, laid at [place]:
  /// the one drawn, once the GPU has finished it — put up as [upTogether]
  /// says ([ScreenTexture.present]).
  Layer presented(
    void Function(GpuSurface next, (int, int) size) draw, {
    required Object drawnFor,
    required FramePlace place,
    Future<void> Function(Future<void> done)? upTogether,
  }) {
    final texture = _texture!;
    texture.present(
      (next) => draw(next, (texture.width, texture.height)),
      drawnFor: drawnFor,
      upTogether: upTogether,
    );
    // After it is presented: a frame that failed, or is still being drawn,
    // stands as it stood.
    return layerOf(texture, place);
  }

  /// The frame the texture open shows already, nothing drawn, by a layer
  /// as [presented]'s: null where none has been presented on it.
  Layer? standing(FramePlace place) {
    final texture = _texture;
    return texture == null || !texture.showsAFrame
        ? null
        : layerOf(texture, place);
  }

  /// A rect as big as [texture] around [shown], on device pixels: what it
  /// spares of the texture half to either side, on an axis where it spares
  /// any — from its start where it is the bigger.
  static Rect windowOf(ScreenTexture texture, Rect shown) {
    double startOf(double from, double to, int side) =>
        from - (math.max(side - (to - from), 0) / 2).floorToDouble();

    return Rect.fromLTWH(
      startOf(shown.left, shown.right, texture.width),
      startOf(shown.top, shown.bottom, texture.height),
      texture.width.toDouble(),
      texture.height.toDouble(),
    );
  }

  /// What [texture] shows now, laid at [place] — a box's own, or the
  /// picture another left up for it ([PicturesLeftUp]).
  static Layer layerOf(
    ScreenTexture texture,
    FramePlace place,
  ) => debugLayerOfScreen(
    rect:
        place.from(texture.shownFor) &
        Size(
          texture.width / place.devicePixelRatio,
          texture.height / place.devicePixelRatio,
        ),
    textureId: texture.textureId.value,
    filterQuality: FilterQuality.none,
  );

  /// Hears of the app's engine from here on — again after a [stop]: a box
  /// taken off and put back asks for its texture again ([open]).
  ///
  /// 🚨frame-timing-overlay-hides-the-canvas (검증 2026-11-15: 「캔버스 자리가
  /// 통째로 어둡다 … 새 프로젝트를 열면 다시 그려진다」): a tree moved under
  /// another parent — the app rebuilt round it as the frame timing overlay
  /// is turned on — detaches its boxes and attaches them again. ↩️This only
  /// heard again: [stop] had marked the texture stopped for good, every
  /// open after it freed what it opened, and the canvas stayed dark till its
  /// boxes were made anew.
  void start() {
    _stopped = false;
    _onTheEngine.start();
  }

  /// Hears no more, and lets go of the texture — and of one on its way,
  /// which is freed as it comes.
  void stop() {
    _stopped = true;
    _opening = null;
    _onTheEngine.stop();
    _freed();
  }

  /// [stop], keeping the texture where it shows a frame: what the box
  /// showed last, the caller's now — left up for the screen that takes the
  /// box's place ([PicturesLeftUp]). Null where it showed none.
  ScreenTexture? stopLeavingItsFrame() {
    final texture = _texture;
    final up = texture != null && texture.showsAFrame;
    if (up) {
      _texture = null;
    }
    stop();
    return up ? texture : null;
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

  int _steppedUp(int side) => (side + sideStep - 1) ~/ sideStep * sideStep;

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

  /// Opens the texture [_toOpen] says; the one it replaces is handed on
  /// ([replaced]) or freed once it is shown no more.
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
    // What the outgrown one shows stands till the new one shows its own.
    final handedOn = held != null && held.showsAFrame ? _replaced : null;
    handedOn?.call(held!);
    _opened(engine);
    if (handedOn == null) {
      await held?.free();
    }
  }
}

/// 🚨★★★THE CANVAS'S PICTURE STANDS TILL THE SCREEN THAT TAKES ITS PLACE
/// PUTS ONE UP — the screen's own law ([ScreenTexture.present]: the last
/// frame put up stands meanwhile) across a screen made anew.
///
/// 🗣️F-365-Q2 (유저 2026-10-15): 「컷을 넘을 때도 직전 그림을 남기고」, and
/// F-599 (유저 2026-11-16): the conte's run showed a black frame on the
/// canvas at every cut it crossed. 🔬Measured on the Surface Pro 11 (S5 cut
/// 352 into 353): the film's unit of the cut coming in is a screen of its
/// own, and for its first paints it had nothing up — no texture yet, then
/// none of its frames finished — so the stage's floor showed through. The
/// same at Play and at Stop, where the editing canvas's screen and the
/// film's take each other's place.
///
/// The picture handed on is the canvas's own, on its paper
/// ([DemandedPicture.paintPaper]): the editing canvas's frame and the film's
/// stage — never the ghosts laid over it, nor a track over the stage. A
/// screen let go of leaves what it showed last here, and one that has put
/// none up yet stands on it till it has; what no screen takes in the frame
/// it was left in is freed after it. ⚠️Where two were left in one frame,
/// which stands for which is not known: neither is taken, and the screens
/// that come show their floor till they are up, as they did.
final class PicturesLeftUp {
  final List<({ScreenTexture texture, GpuEngine? engine})> _left = [];
  bool _sweepAsked = false;

  /// [texture] — up on a screen of the canvas's picture let go of — kept
  /// for the screen that takes its place, till this frame is over.
  void left(ScreenTexture texture) {
    texture.putUp = null;
    _left.add((texture: texture, engine: appGpuEngineOpen.value));
    if (_sweepAsked) {
      return;
    }
    _sweepAsked = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _sweep());
  }

  /// The picture left up this frame for a screen of the canvas's picture
  /// that has none up, now that screen's to free — null where none was, or
  /// more than one, or it was left on an engine the app has let go.
  ScreenTexture? take() {
    if (_left.length != 1 ||
        !identical(_left.single.engine, appGpuEngineOpen.value)) {
      return null;
    }
    return _left.removeLast().texture;
  }

  void _sweep() {
    _sweepAsked = false;
    for (final (:texture, engine: _) in _left) {
      unawaited(texture.free());
    }
    _left.clear();
  }
}
