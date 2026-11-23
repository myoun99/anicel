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

/// 🔬What a frame of a screen took on its way up, in microseconds
/// ([ScreenTexture.upMicros]): its [draw] — handing it to the engine, on the
/// thread that builds the app's frames —, the GPU [finish]ing it and this
/// isolate hearing so, and its [show] — the hand to Flutter, on that
/// thread again. ↩️On Android that thread waited in the draw for the
/// window's next image and in the show for the present, on the way builds
/// 1095 to 1097 showed a window by (rust/src/platform/android.rs).
typedef ScreenUp = ({int draw, int finish, int show});

/// What the canvas view shows the engine's screen on: a texture of the
/// view's size in device pixels, and the way a frame drawn on it reaches
/// Flutter (screen-on-the-engine c6) — two surfaces, each a texture of its
/// own, alternated, on every platform. The frame grids show their tiles
/// through one already (`TimelineGridScreenHost`, grid-on-the-engine ④).
///
/// ↩️TILL 2026-11-23 ANDROID ALONE SHOWED A SURFACEPRODUCER'S WINDOW —
/// one texture id for its life, a frame copied whole onto the window's
/// next image as it was put up. 🗣️유저 2026-11-23 「통일을 말한게
/// 언제적인데 아직도 안하고있냔얘기야」 (card
/// the-galaxy-tab-canvas-went-slow-on-build-1095, 길 A): one way. The
/// window also placed a frame's picture a frame apart from where the
/// layer tree put it — the raster took the window's newest image, the
/// tree the place of the frame before (card
/// panning-then-pen-jumps-the-android-canvas-a-frame, H68): a texture's
/// picture changes here by its id alone.
sealed class ScreenTexture {
  ScreenTexture(
    this.width,
    this.height, {
    required int surfaces,
    required Future<void> Function()? done,
    GpuEngine? engine,
  }) : _bytes = width * height * 4 * surfaces,
       _done = done,
       _engine = engine {
    _liveBytes += _bytes;
  }

  /// What every screen open holds, in bytes, for the memory census
  /// (`every_counted_byte_is_censused`, 관제 2026-11-09 08:07 E①).
  static int get liveBytes => _liveBytes;
  static int _liveBytes = 0;

  final int _bytes;

  /// 🔬What the newest frames of every screen took from their draw to
  /// being put up, part by part ([ScreenUp]), oldest first, [upsKept] of
  /// them at the most; how many frames have been put up in all
  /// ([upsCounted]), and how many of those with a newer one asked for
  /// meanwhile ([upsBehindCounted]) — a screen behind what is asked of it.
  /// Flutter's own frame times say nothing of these: a screen's frame is
  /// the engine's work, on no thread of Flutter's. The frame statistics
  /// read them (`FrameStats`, Settings ▸ Debug).
  ///
  /// 🗣️유저 2026-11-21, on a Galaxy Tab out of this machine's reach (card
  /// the-galaxy-tab-canvas-went-slow-on-build-1095): 「캔버스조작, 즉
  /// 팬이나 줌이나 스트로크가 너무 느려졋어」 — and nothing the app showed
  /// said which were the slow ones, its screens' frames or Flutter's; nor,
  /// with one figure a frame (build 1096), which part of a screen's frame
  /// — and a build is a day's turn of that tablet.
  static List<ScreenUp> get upMicros => List.unmodifiable(_upMicros);
  static final List<ScreenUp> _upMicros = [];

  /// How many frames [upMicros] keeps: seconds of them, at a screen's rate.
  static const int upsKept = 240;

  static int get upsCounted => _upsCounted;
  static int _upsCounted = 0;

  static int get upsBehindCounted => _upsBehindCounted;
  static int _upsBehindCounted = 0;

  /// 🔬The way the newest screen opened reaches Flutter's screen
  /// ([GpuEngine.screenSaid]: on Android `ahb`, or `ahb no — ` and what
  /// stands in the way) and, where it could not open, why — the last
  /// refusal's own words: empty where none has been opened, as in
  /// `flutter test`. The frame statistics show it (Settings ▸ Debug).
  ///
  /// 🗣️유저 2026-11-23 (card the-galaxy-tab-canvas-went-slow-on-build-1095
  /// ⓑ): 「몇번을 임시빌드로 … 모든가능성 철저하게 검사해서 디버그화면
  /// 만들면되지」 — which way a device's screen went, and why not the other,
  /// read off the device instead of asked of a build.
  static String get path => switch (_refused) {
    null => _said,
    final why => '$_said  refused: $why',
  };
  static String _said = '';
  static String? _refused;

  /// The engine the newest screen was opened on, [path]'s, while it is
  /// live and not gone: what the debug screen checks the way on
  /// (`ScreenCheck`). Held weakly — the app lets an engine go.
  static GpuEngine? get engineOfThePath => switch (_pathsEngine?.target) {
    final engine? when !engine.isClosed && !engine.isGone => engine,
    _ => null,
  };
  static WeakReference<GpuEngine>? _pathsEngine;

  /// Test seam: a screen opened [said] that way — refused for [refused],
  /// where named.
  @visibleForTesting
  static void debugPathIs(String said, {String? refused}) {
    _said = said;
    _refused = refused;
  }

  /// 🔬Who is told what each place of a screen's engine took of each frame
  /// as it goes up ([GpuEngine.took]: since the frame before it went up,
  /// on whatever screen of that engine) — and while anyone is, each
  /// screen's engine is timed as its next frame is drawn
  /// ([GpuEngine.timesItsPlaces]), and no longer once no one is. The
  /// frame statistics' stages (`EngineStages`, Settings ▸ Debug).
  ///
  /// A timed engine waits for nothing to be timed (rust/src/took.rs): its
  /// frames are an untimed one's.
  static void Function(ScreenUp up, List<GpuPlaceTook> took)? tookAsItWentUp;

  /// The engine this screen's frames are drawn on: the one timed
  /// ([tookAsItWentUp]). None where a test reads a surface back with no
  /// engine named ([debugOnSurface]).
  final GpuEngine? _engine;

  static void _wentUp(ScreenUp up) {
    _upsCounted += 1;
    _upMicros.add(up);
    if (_upMicros.length > upsKept) {
      _upMicros.removeAt(0);
    }
  }

  /// Test seam: a frame put up as [up] says — [behind], with a newer one
  /// asked for meanwhile.
  @visibleForTesting
  static void debugWentUp(ScreenUp up, {bool behind = false}) {
    _wentUp(up);
    if (behind) {
      _upsBehindCounted += 1;
    }
  }

  /// Test seam: no frame put up yet.
  @visibleForTesting
  static void debugForgetUps() {
    _upMicros.clear();
    _upsCounted = 0;
    _upsBehindCounted = 0;
  }

  /// A texture of [width] × [height] device pixels on [engine] — and the
  /// way it reaches Flutter's screen, or why it could not, told [path].
  static Future<ScreenTexture> open(
    GpuEngine engine,
    int width,
    int height,
  ) async {
    _said = engine.screenSaid;
    _pathsEngine = WeakReference(engine);
    try {
      final opened = await _AlternatedTextures.open(engine, width, height);
      _refused = null;
      return opened;
    } on GpuRefused catch (refused) {
      _refused = refused.message;
      rethrow;
    }
  }

  /// Whether this platform's screens are laid BGRA, RGBA else: Apple's
  /// Flutter shows 32BGRA alone among RGB layouts
  /// (rust/src/platform/apple.rs), Linux's GL texture is GL_RGBA8 alone
  /// (rust/src/platform/linux.rs), Android's AHardwareBuffer is RGBA
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
  static GpuSurface surfaceOf(
    GpuEngine engine,
    int width,
    int height, {
    bool asTheDriverChooses = false,
  }) => engine.surface(
    width,
    height,
    bgra: bgra,
    asTheDriverChooses: asTheDriverChooses,
  );

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
    GpuEngine? engine,
  }) =
      _SurfaceTexture;

  final int width;
  final int height;

  /// The id a `Texture` widget shows the frame last put up by.
  ValueListenable<int> get textureId;

  /// What the frame put up was drawn for ([present]).
  Object? get shownFor => _frames.shown?.drawnFor;

  /// What the frame drawn last was drawn for — the one the GPU has still
  /// to finish, else the one up: null where none has been drawn, or the
  /// one drawn was never finished and none is up.
  Object? get drawnLastFor => (_frames.laying ?? _frames.shown)?.drawnFor;

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

  /// Since the draw of the frame begun last began, and how long that draw
  /// took ([upMicros]).
  final Stopwatch _sinceItsDraw = Stopwatch();
  int _itsDrawMicros = 0;

  /// The target the frame begun last was drawn on: the one a frame the
  /// GPU did not finish leaves holding nothing known ([GpuTarget.kept]).
  /// Frames are drawn one at a time ([_frames]), so it is that frame's
  /// till the next is begun.
  GpuTarget? _drawnOnLast;

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
  /// none of it ([GpuScreen.show], [GpuGridLay.lay]). Asked while one is
  /// being drawn, it draws nothing: the newest asked is drawn once that one
  /// is up, where it is presented again.
  ///
  /// 🚨A frame that cannot be drawn or finished — the GPU past the
  /// engine's limit (`Engine::wait`), the device gone — leaves Flutter
  /// showing what it showed and is reported by name, and whatever is
  /// painting goes on. 🗣️관제 2026-11-08, after a pin stood 13 minutes in
  /// that wait: 「멈춘 화면보다 이름 있는 실패」.
  ///
  /// When the frame finished goes up, [upTogether] says, told the GPU's
  /// done — as soon as it is, where none is named: what puts up the
  /// pictures of one canvas together (`PicturesUpTogether`).
  void present(
    void Function(GpuTarget next) draw, {
    Object? drawnFor,
    Future<void> Function(Future<void> done)? upTogether,
  }) {
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
    final finished = done();
    unawaited(
      (upTogether?.call(finished) ?? finished).then(
        (_) {
          if (_freed) {
            return;
          }
          _putUp();
          final behind = _frames.behind;
          if (behind) {
            _upsBehindCounted += 1;
          }
          putUp?.call(behind: behind);
        },
        onError: (Object error, StackTrace stack) {
          _report(error, stack);
          // What the GPU did of a frame it did not finish is not known:
          // the next drawn on its target is drawn whole.
          _drawnOnLast?.kept = null;
          if (_freed) {
            return;
          }
          // Given up whether or not anyone is told: a call on no one runs
          // none of its arguments, and the frame stayed the one being
          // drawn — nothing after it began (2026-11-22).
          final behind = _frames.layingGivenUp();
          putUp?.call(behind: behind);
        },
      ),
    );
  }

  _Frame _begin(int asked) {
    final (:draw, :drawnFor) = _beginning!;
    _engine?.timesItsPlaces(tookAsItWentUp != null);
    _sinceItsDraw
      ..reset()
      ..start();
    _draw((next) {
      _drawnOnLast = next;
      draw(next);
      // What the frame wrote, handed over where Flutter shows another
      // texture than the one drawn on ([GpuTarget.settle]) — before the
      // done the frame goes up by.
      next.settle();
    });
    _itsDrawMicros = _sinceItsDraw.elapsedMicroseconds;
    return (asked: asked, drawnFor: drawnFor);
  }

  void _putUp() {
    // Never let go of unseen: each frame is asked for by a number of its
    // own, so what is up is never of the one asked for last.
    if (_frames.laid() == null) {
      return;
    }
    final heard = _sinceItsDraw.elapsedMicroseconds;
    _show();
    _showsAFrame = true;
    final up = (
      draw: _itsDrawMicros,
      finish: heard - _itsDrawMicros,
      show: _sinceItsDraw.elapsedMicroseconds - heard,
    );
    _wentUp(up);
    final (told, engine) = (tookAsItWentUp, _engine);
    if (told != null && engine != null) {
      told(up, engine.took());
    }
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

  /// Test seam: how many frames have been drawn on this screen, where a
  /// test reads it back ([debugOnSurface]) — null on the app's own.
  @visibleForTesting
  int? get debugFramesDrawn => null;

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
  /// What is made before a refusal is let go of: a screen half made is
  /// none.
  static Future<_AlternatedTextures> open(
    GpuEngine engine,
    int width,
    int height,
  ) async {
    final surfaces = <GpuSurface>[];
    final textures = <SharedTexture>[];
    try {
      for (var i = 0; i < 2; i++) {
        surfaces.add(engine.surface(width, height, bgra: ScreenTexture.bgra));
      }
      for (final surface in surfaces) {
        textures.add(await SharedTexture.register(surface));
      }
    } on Object {
      for (final texture in textures) {
        texture.unregister();
      }
      for (final surface in surfaces) {
        surface.free();
      }
      rethrow;
    }
    return _AlternatedTextures._(surfaces, textures, width, height, engine);
  }

  _AlternatedTextures._(
    this._surfaces,
    this._textures,
    int width,
    int height,
    GpuEngine engine,
  ) : _shown = ValueNotifier(_textures.first.id),
      super(
        width,
        height,
        surfaces: _surfaces.length,
        done: engine.done,
        engine: engine,
      );

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
    super.engine,
  }) : _id = ValueNotifier(id),
       _nextId = nextId ?? id,
       super(_surface.width, _surface.height, surfaces: 1);

  final GpuSurface _surface;
  final ValueNotifier<int> _id;
  final int _nextId;

  @override
  ValueListenable<int> get textureId => _id;

  @override
  int? get debugFramesDrawn => _framesDrawn;
  int _framesDrawn = 0;

  @override
  void _draw(void Function(GpuTarget next) draw) {
    _framesDrawn += 1;
    draw(_surface);
  }

  @override
  void _show() => _id.value = _nextId;

  @override
  Future<void> _free() async => _id.dispose();
}
