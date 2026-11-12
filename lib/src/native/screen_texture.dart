import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show
        ErrorDescription,
        FlutterError,
        FlutterErrorDetails,
        ValueListenable,
        ValueNotifier,
        visibleForTesting;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:gpu_engine/gpu_engine.dart';

import '../core/laid_whole.dart';

/// A frame of a screen, by the number it was asked for by, and what it was
/// drawn for ([ScreenTexture.present]).
typedef _Frame = ({int asked, Object? drawnFor});

/// What the canvas view shows the engine's screen on: a texture of the
/// view's size in device pixels, and the way a frame drawn on it reaches
/// Flutter (screen-on-the-engine c6) — two surfaces, each a texture of its
/// own, alternated, on Windows, iOS, macOS and Linux; a SurfaceProducer's
/// window on Android. The frame grids show their tiles through one already
/// (`TimelineGridScreenHost`, grid-on-the-engine ④).
sealed class ScreenTexture {
  ScreenTexture(
    this.width,
    this.height, {
    required int surfaces,
    required Future<void> Function()? done,
  }) : _bytes = width * height * 4 * surfaces,
       _done = done {
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
      ? _WindowTexture(
          await engine.window(width, height),
          width,
          height,
          engine,
        )
      : _AlternatedTextures(engine, width, height);

  /// Whether this platform's screens are laid BGRA, RGBA else: Apple's
  /// Flutter shows 32BGRA alone among RGB layouts
  /// (rust/src/platform/apple.rs), Linux's GL texture is GL_RGBA8 alone
  /// (rust/src/platform/linux.rs), Android's window is RGBA
  /// (rust/src/platform/android.rs), and on Windows the screen's bytes
  /// matched the GPU's in BGRA and not in RGBA (gpu-engine-feasibility ⑤,
  /// three runs: BGRA MATCH 3ed77c11, RGBA MISMATCH e20eea22).
  ///
  /// One fact for the screens and for the kernels compiled ahead of them
  /// (`appGpuCompositeKernels`, `appGpuGridKernels`): a pass that shows on
  /// a screen is compiled per layout, so a second answer is a second
  /// compile where the first screen is shown (🗣️관제 2026-11-10 18:14,
  /// gpu-canonical-store ⑦).
  static final bool bgra = !Platform.isLinux && !Platform.isAndroid;

  /// A surface of [width] × [height] on [engine], laid as this platform's
  /// screens are: what a picture for a file is shown on and read back from.
  static GpuSurface surfaceOf(GpuEngine engine, int width, int height) =>
      engine.surface(width, height, bgra: bgra);

  /// [surface] alone, presented onto and shown by no texture Flutter
  /// knows: what a test reads a screen back from ([GpuSurface.fingerprint])
  /// — `flutter test` registers no texture. The surface stays the test's;
  /// [id] is the texture id its layer names, and [nextId] the one a frame
  /// presented goes on to show by, [id] again unless named.
  ///
  /// A frame drawn on it is shown as soon as it is drawn, where no [done]
  /// is named: a test reads the surface back, and a read waits for the GPU
  /// as a read does. Named, a frame is shown once [done] has ended — the
  /// way the app's textures show it ([GpuEngine.done]).
  @visibleForTesting
  factory ScreenTexture.debugOnSurface(
    GpuSurface surface, {
    int id,
    int? nextId,
    Future<void> Function()? done,
  }) =
      _SurfaceTexture;

  final int width;
  final int height;

  /// The id a `Texture` widget shows the frame last put up by.
  ValueListenable<int> get textureId;

  /// What the frame put up was drawn for ([present]).
  Object? get shownFor => _frames.shown?.drawnFor;

  /// Ends once the GPU has finished what a frame submitted: null where a
  /// frame is shown as soon as it is drawn ([debugOnSurface]).
  final Future<void> Function()? _done;

  /// 🚨★★★A FRAME IS PUT UP ONCE THE GPU HAS FINISHED IT, and the last one
  /// put up stands meanwhile ([LaidWhole] — the shape tool's law, I-69-Q4ⓒ):
  /// the frames asked for, the one being drawn and the one Flutter shows.
  ///
  /// 🗣️a-float-in-hand-draws-the-frame-as-it-stands-Q2 (유저 2026-11-12):
  /// 「z로 직선 그을때나 같은 규칙. ui로서는 바로 작동하지만 정확함을 요구하는
  /// 그림은 끝나는대로 준비함 … 어긋나는거 ok」 — the box, its handles and the
  /// cursor follow the pen, drawn by Flutter; under them the screen shows
  /// the frame the GPU finished last. ↩️[present] waited for the GPU on the
  /// thread that builds the app's frames, every frame: 🔬on the Surface Pro
  /// 11 ≈19 ms of a frame's 22 while a float was dragged over the whole of
  /// S5 cut 352 — UI, input and every other paint held up with it.
  late final LaidWhole<int, _Frame> _frames = LaidWhole(
    begin: _begin,
    holds: (laid, asked) => laid.asked == asked,
  );
  int _asked = 0;

  /// The frame being begun: its draw, and what it is drawn for.
  ({void Function(GpuTarget next) draw, Object? drawnFor})? _beginning;

  /// Told once a frame the GPU finished is up — and whether another was
  /// asked for meanwhile: that one is drawn where it is asked for again
  /// ([present]), at a paint, as every frame is.
  void Function({required bool behind})? putUp;

  bool _freed = false;

  /// [draw]s the next frame onto what Flutter is not showing — what it was
  /// drawn for told by [drawnFor] — and puts it up once the GPU has
  /// finished it, telling [putUp]. [draw] submits its work and waits for
  /// none of it ([GpuScreen.show]). Asked while one is being drawn, it
  /// draws nothing: the newest asked is drawn once that one is up, where it
  /// is presented again.
  ///
  /// 🚨A frame that cannot be drawn or finished — the GPU past the
  /// engine's limit (`Engine::wait`), the device gone — leaves Flutter
  /// showing what it showed and is reported by name, and whatever is
  /// painting goes on. 🗣️관제 2026-11-08, after a pin stood 13 minutes in
  /// that wait: 「멈춘 화면보다 이름 있는 실패」.
  void present(void Function(GpuTarget next) draw, {Object? drawnFor}) {
    _beginning = (draw: draw, drawnFor: drawnFor);
    final bool began;
    try {
      began = _frames.ask(++_asked);
    } on StateError catch (error, stack) {
      _report(error, stack);
      return;
    } finally {
      _beginning = null;
    }
    if (!began) {
      return;
    }
    final done = _done;
    if (done == null) {
      // Up in the paint that drew it, which shows it: nobody to tell.
      _putUp();
      return;
    }
    unawaited(
      done().then(
        (_) {
          if (_freed) {
            return;
          }
          _putUp();
          putUp?.call(behind: _frames.behind);
        },
        onError: (Object error, StackTrace stack) {
          _report(error, stack);
          if (_freed) {
            return;
          }
          putUp?.call(behind: _frames.layingGivenUp());
        },
      ),
    );
  }

  _Frame _begin(int asked) {
    final (:draw, :drawnFor) = _beginning!;
    _draw(draw);
    return (asked: asked, drawnFor: drawnFor);
  }

  void _putUp() {
    // Never let go of unseen: each frame is asked for by a number of its
    // own, so what is up is never of the one asked for last.
    if (_frames.laid() == null) {
      return;
    }
    _show();
    _showsAFrame = true;
  }

  static void _report(Object error, StackTrace stack) =>
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'screen texture',
          context: ErrorDescription('drawing the next frame of a screen'),
        ),
      );

  /// [draw] onto what Flutter is not showing.
  void _draw(void Function(GpuTarget next) draw);

  /// What was drawn last is what Flutter shows.
  void _show();

  /// Whether a frame has been presented: till one is, [textureId] shows
  /// nothing drawn.
  bool get showsAFrame => _showsAFrame;
  bool _showsAFrame = false;

  /// Frees the texture, once Flutter shows it no more — a frame the GPU
  /// is still drawing put up nowhere, though where the GPU fails it that
  /// is reported by name as ever ([present]).
  Future<void> free() {
    _freed = true;
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
        engine.surface(width, height, bgra: ScreenTexture.bgra),
    ];
    final textures = [
      for (final surface in surfaces) SharedTexture.register(surface),
    ];
    return _AlternatedTextures._(surfaces, textures, width, height, engine);
  }

  _AlternatedTextures._(
    this._surfaces,
    this._textures,
    int width,
    int height,
    GpuEngine engine,
  ) : _shown = ValueNotifier(_textures.first.id),
      super(width, height, surfaces: _surfaces.length, done: engine.done);

  final List<GpuSurface> _surfaces;
  final List<SharedTexture> _textures;
  final ValueNotifier<int> _shown;

  /// The surface the next frame is drawn on: the one not shown.
  int _next = 0;

  @override
  ValueListenable<int> get textureId => _shown;

  @override
  void _draw(void Function(GpuTarget next) draw) => draw(_surfaces[_next]);

  @override
  void _show() {
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
  _SurfaceTexture(
    this._surface, {
    int id = 0,
    int? nextId,
    super.done,
  }) : _id = ValueNotifier(id),
       _nextId = nextId ?? id,
       super(_surface.width, _surface.height, surfaces: 1);

  final GpuSurface _surface;
  final ValueNotifier<int> _id;
  final int _nextId;

  @override
  ValueListenable<int> get textureId => _id;

  @override
  void _draw(void Function(GpuTarget next) draw) => draw(_surface);

  @override
  void _show() => _id.value = _nextId;

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
  _WindowTexture(this._window, int width, int height, GpuEngine engine)
    : _id = ValueNotifier(_window.textureId),
      super(width, height, surfaces: 2, done: engine.done);

  final GpuWindow _window;
  final ValueNotifier<int> _id;

  @override
  ValueListenable<int> get textureId => _id;

  @override
  void _draw(void Function(GpuTarget next) draw) => draw(_window);

  @override
  void _show() => _window.present();

  @override
  Future<void> _free() async {
    _id.dispose();
    await _window.free();
  }
}
