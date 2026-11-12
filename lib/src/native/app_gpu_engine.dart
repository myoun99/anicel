import 'dart:async' show FutureOr;
import 'dart:ui' show RootIsolateToken;

import 'package:flutter/foundation.dart'
    show ChangeNotifier, ValueListenable, visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import 'gpu_adapter_choice.dart';
import 'screen_texture.dart';

/// The app's one GPU engine, opened the first time anything asks — so a
/// test file that never asks opens no device (보드/인프라 2026-11-07: 0.6–1.2
/// s a device, eighteen test files at once on the machine's line) — on the
/// adapter [debugGpuAdapterChoice] names. ⛔No fallback: a test that needs
/// the engine and gets none fails.
// The app opens it after its first frame ([openAppGpuEngine], main.dart),
// for the frame grids' tiles (grid-on-the-engine ⑤); ⏳the tile ledger
// (`EngineTileLedger.instance`) asks once the screen asks it
// (screen-on-the-engine c6).
GpuEngine get appGpuEngine => _its.engine ??= _opener()();

/// One engine of the app's, from before it is opened till the app lets it
/// go ([letTheGoneAppGpuEngineGo]): the engine, the opening of it under
/// way, and — by being this object — what everything kept on it is kept
/// for ([KeptOnTheAppsEngine]). ONE fact, so no two of the three can speak
/// of different engines.
final class _AppsEngine {
  GpuEngine? engine;
  Future<GpuEngine>? opening;
}

_AppsEngine _its = _AppsEngine();

/// Whether this isolate can have [appGpuEngine]: a worker cannot — the
/// engine, and the tiles its pool holds, are the main isolate's.
bool get appGpuEngineIsHere => RootIsolateToken.instance != null;

/// Whether the app has opened its engine and that device is gone
/// ([GpuEngine.isGone]) — asked without opening one. Every job is refused
/// from then on, whatever the job: one cause, for what tells a refusal
/// (`EngineRefusals`).
bool get appGpuEngineIsGone => _its.engine?.isGone ?? false;

/// Whether [engine] is the one the app has now — asked without opening
/// one: what was made on another is not kept for the next use
/// (`EngineStrokes.giveBack`).
bool isTheAppsEngine(GpuEngine engine) => identical(engine, _its.engine);

/// Lets go of the app's engine, its device gone ([appGpuEngineIsGone]) —
/// of nothing where it is not: the next ask opens another ([appGpuEngine],
/// [openAppGpuEngine]), what was kept on this one is made again on that
/// ([KeptOnTheAppsEngine]), and [appGpuEngineOpen] says none is open till
/// then.
///
/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
/// 유지한다」 — 「장치를 잃으면 앱은 꺼지지 않고 새 장치를 열어 사본으로
/// 되살린다」.
///
/// ⛔NOT CLOSED. A tile this engine made keeps its ledger, the ledger its
/// pool and this engine, and such a tile is read through them once more —
/// as the picture it landed on (`EngineTileLedger`) — and lets its slot go
/// there whenever it is collected; a stamp's picture made here is asked
/// for its bytes the same way. Closed, each of those would be at memory
/// given back (`gpu_engine_close` frees the engine whole). What stays is
/// one engine whose device the driver took, once a loss.
///
/// ⚠️BETWEEN FRAMES: what stands on a screen is told as this returns
/// ([StandsOnTheAppsEngine]) and marks its box to paint, which no phase of
/// a frame may.
///
/// ⏳Nothing in the app asks yet: what shows on a screen still holds what
/// the gone engine made, and lets it go first (관제 2026-11-11 22:35: 「(C3)
/// 는 다섯이 다 선 뒤」).
void letTheGoneAppGpuEngineGo() {
  if (!appGpuEngineIsGone) {
    return;
  }
  _its = _AppsEngine();
  _opened.letGo();
}

/// What stands on a screen of what [appGpuEngine] made — the texture a box
/// is shown through, a stroke on its way, the grids' tiles, the frames'
/// pictures — and is let go of with that engine
/// ([letTheGoneAppGpuEngineGo]). Unlike a cache ([KeptOnTheAppsEngine]) it
/// is told: it has something to lay again, and a box to paint.
///
/// 🚨ONE SEAM, FOR EVERY ONE OF THEM (관제 2026-11-11 22:35: 「`appGpuEngineOpen`
/// 을 듣는 이음매 하나를 두고 다섯이 그것을 쓰게 하라」): [letGo] where the app
/// lets its engine go, [opened] at each engine it opens — the first too.
final class StandsOnTheAppsEngine {
  StandsOnTheAppsEngine({
    required void Function() letGo,
    void Function(GpuEngine engine)? opened,
  }) : _letGo = letGo,
       _opened = opened;

  final void Function() _letGo;
  final void Function(GpuEngine engine)? _opened;

  /// Hears from here on, till [stop].
  void start() => appGpuEngineOpen.addListener(_heard);

  void stop() => appGpuEngineOpen.removeListener(_heard);

  void _heard() {
    final engine = appGpuEngineOpen.value;
    if (engine == null) {
      _letGo();
    } else {
      _opened?.call(engine);
    }
  }
}

/// What was made on [appGpuEngine] and is kept: the app's while that
/// engine is, and kept no longer once the app has let that engine go
/// ([letTheGoneAppGpuEngineGo]). What asks then makes it again, on the
/// engine the app has by then.
///
/// 🚨EVERY CACHE OF WHAT THE ENGINE MADE IS ONE OF THESE — a set of
/// kernels ([AppKernels]), the strokes at rest (`EngineStrokes`), the
/// frame's tools (`appEngineFrameTools`), the tile ledger and its pool
/// (`EngineTileLedger.instance`), the stamps' pictures
/// (`EngineStampPictures`): what one device made, the next refuses.
/// ⛔Not by listening ([appGpuEngineOpen]): a cache that forgot to listen
/// would hand out what the last engine made, and nothing would say so
/// till a job was refused. Asked here, it cannot. What stands on a screen
/// is not a cache and does listen ([StandsOnTheAppsEngine]): it has a
/// picture to lay again.
///
/// ⛔WHAT AN ENGINE LET GO MADE IS LEFT WITH IT, NOT FREED: what else was
/// made there may hold it still and free itself after — a screen its
/// executor (`GpuScreen`: 「before its executor is」), a tile its ledger —
/// and a kernel freed under one would be at memory given back. It stays
/// as that engine stays, once a loss ([forget], asked for, frees).
final class KeptOnTheAppsEngine<T extends Object> {
  /// [free] frees what [forget] lets go; nothing does where null.
  KeptOnTheAppsEngine([this._free]);

  final void Function(T)? _free;
  T? _kept;
  _AppsEngine? _on;

  /// What is kept, null where nothing is.
  T? get orNull {
    if (!identical(_on, _its)) {
      _kept = null;
      _on = null;
    }
    return _kept;
  }

  /// What is kept — [make]'s, kept from now, where nothing is.
  T of(T Function() make) {
    final kept = orNull;
    if (kept != null) {
      return kept;
    }
    _on = _its;
    return _kept = make();
  }

  /// Lets go of what is kept, freed — the memory is tight, or a test
  /// starts as a launch does.
  void forget() {
    final kept = orNull;
    _kept = null;
    _on = null;
    if (kept != null) {
      _free?.call(kept);
    }
  }
}

/// Test seam: the error the app's engine raised that no job has been
/// refused by, taken ([GpuEngine.debugTakeNoted]) — null where there is
/// none, where no engine is open, and where its device is gone, which
/// raises one at every use of what was made on it. What every test is
/// asked as it ends (`flutter_test_config.dart`): till 2026-11-11 such an
/// error ended the process where it was raised, and now it waits for a job
/// that waits.
@visibleForTesting
String? debugTakeAppGpuEngineNoted() {
  final engine = _its.engine;
  return engine == null || engine.isGone ? null : engine.debugTakeNoted();
}

/// A set of kernels on [appGpuEngine], one for the app: compiled here the
/// first time anything asks, if [warm] has not got there first — and
/// again on the next engine, once the app lets this one go
/// ([KeptOnTheAppsEngine]).
final class AppKernels<T extends Object> {
  AppKernels(this._here, this._off, this._free)
    : _kept = KeptOnTheAppsEngine(_free);

  /// Test seam: [warm] compiles on this isolate, as [kept] does. A widget
  /// test's clock is pumped, and lends a compile on another isolate no real
  /// time to finish in (`flutter_test_config.dart`).
  @visibleForTesting
  static bool debugCompileHere = false;

  final T Function(GpuEngine) _here;
  final Future<T> Function(GpuEngine) _off;
  final void Function(T) _free;

  final KeptOnTheAppsEngine<T> _kept;

  T get kept => _kept.of(() => _here(appGpuEngine));

  /// [kept] where it has been compiled, null till then.
  T? get compiled => _kept.orNull;

  /// [kept] where it has been compiled, at once — else once [warm] has
  /// compiled it: what a use that must not compile on this isolate waits
  /// on.
  ///
  /// ⚠️Not [warm]'s future where there is no need: that one is made once
  /// and kept, and a future made under a widget test's faked clock tells
  /// one awaited in real time (`runAsync`) that it is done only when the
  /// faked clock is pumped — an export's frame waited for it for good.
  FutureOr<T> get ready => _kept.orNull ?? warm();

  /// [kept] compiled off this isolate, at once where it is compiled already:
  /// ahead of a first use that would otherwise wait with the app frozen.
  /// One compile, however many ask: what needs the kernels asks as the
  /// launch does, and waits on the same one (🗣️관제 2026-11-10 18:14,
  /// gpu-canonical-store ⑦).
  Future<T> warm() => _warming.of(_warmed);
  final _warming = KeptOnTheAppsEngine<Future<T>>();

  Future<T> _warmed() async {
    if (debugCompileHere) {
      return kept;
    }
    final its = _its;
    final made = _kept.orNull ?? await _off(appGpuEngine);
    if (!identical(its, _its)) {
      // The app let its engine go while this compiled on it: what it made
      // is that engine's, and the app's is asked the same way.
      _free(made);
      return warm();
    }
    // Asked for the other way while this compiled: the app keeps one.
    final one = _kept.of(() => made);
    if (!identical(one, made)) {
      _free(made);
    }
    return one;
  }

  /// Test seam: gone, as at launch — and with it every kernel the engine
  /// keeps ([GpuEngine.debugForgetKernels]), or the set would be made
  /// again of those, with nothing to compile.
  void debugForget() {
    _kept.forget();
    _warming.forget();
    _its.engine?.debugForgetKernels();
  }
}

/// The executor on [appGpuEngine]: one for the frames and the strokes alike.
/// Warmed for the first frame's picture, with the pass that shows on this
/// platform's screens ([ScreenTexture.bgra]): 🔬1.7–6 s cold on the main PC
/// (11-06) and 8.3 s beside a busy test line (11-10).
GpuComposite get appGpuComposite => appGpuCompositeKernels.kept;
final appGpuCompositeKernels = AppKernels<GpuComposite>(
  GpuComposite.new,
  (engine) => GpuComposite.opening(engine, bgra: ScreenTexture.bgra),
  (composite) => composite.free(),
);

/// The export's passes on [appGpuEngine]: what a frame's last picture is
/// laid with, and what turns it into a writer's bytes (gpu-export-path ①),
/// warmed for the first frame a panel or a file is made of: its lay pass
/// compiled off this isolate ([GpuExport.opening]), the conversions where
/// a writer first asks.
GpuExport get appGpuExport => appGpuExportKernels.kept;
final appGpuExportKernels = AppKernels<GpuExport>(
  GpuExport.new,
  (engine) => GpuExport.opening(engine, bgra: ScreenTexture.bgra),
  (export) => export.free(),
);

/// [here]'s answer where a test compiles on this isolate
/// ([AppKernels.debugCompileHere]), [off]'s everywhere else: what the app
/// compiles of its own on its engine — a plug-in's build, opened as a frame
/// first asks for it (`InstalledFxPlugins.runnerFor`) or as it is installed
/// — is compiled off the isolate its frames are built on, as its kernels
/// are ([AppKernels.warm]).
FutureOr<T> compiledHereOrOff<T>(
  T Function() here,
  Future<T> Function() off,
) => AppKernels.debugCompileHere ? here() : off();

/// A frame not laid: its plan names an effect chain whose kernels are still
/// to be compiled, and a plan run compiles them where it is run — the thread
/// the app's frames are built on (🗣️관제 2026-11-10 18:14,
/// gpu-canonical-store ⑦: 「선 = UI 스레드가 직접 하는 커널 컴파일 0개」;
/// 🔬the seven were 6.5 s of a stopped UI as S5 opened, Surface Pro 11).
/// Thrown in place of that run, the compile under way off this isolate
/// ([compiled]): what was laying the frame lays it again once that is done
/// — a route that can wait by waiting (`FxPluginStages.recordedThrough`), a
/// screen in its paint by staying on the picture it showed
/// (`FramePictureView`). A plug-in still opening is one more such compile
/// ([FrameKernelsToCome.forAPlugin]).
final class FrameKernelsToCome implements Exception {
  FrameKernelsToCome._(this.compiled);

  /// The compile, off this isolate: one, however many wait.
  final Future<void> compiled;

  /// Throws one where [plan], about to be run on [composite], names a chain
  /// whose kernels are still to come. Never where a test compiles on this
  /// isolate ([AppKernels.debugCompileHere]): the run compiles them there,
  /// as it always did.
  static void throwIfNamedBy(GpuPlan plan, GpuComposite composite) {
    if (plan.namesAChain &&
        composite.chainsAreToCome &&
        !AppKernels.debugCompileHere) {
      throw FrameKernelsToCome._(composite.compileChains());
    }
  }

  /// One for a step of a plug-in whose build is still being opened off this
  /// isolate ([compiled] — `FxPluginRunner.toCome`): it waits for that, as
  /// a chain does for its kernels.
  ///
  /// 🗣️관제 2026-11-12 22:25 (an-endless-plugin-stalls-the-app ④): 「새
  /// 상태 없이 FrameKernelsToCome 법에 태운다」 — 🔬the open stopped the UI
  /// at a plugin's first frame for its check and its device's compile
  /// (Surface Pro 11: a check of 2,000 statements 79 ms, of 8,000 934 ms,
  /// 11-12; a compile 0.7–11.7 s, 11-08). None is under way where a test
  /// compiles on this isolate: a plugin opens as it is asked there.
  FrameKernelsToCome.forAPlugin(this.compiled);

  @override
  String toString() =>
      'FrameKernelsToCome: a frame whose effect chains wait for their '
      'kernels to be compiled';
}

/// The frame grids' two passes on [appGpuEngine], for every grid: the one
/// that draws a tile and the one that lays tiles on a screen. Warmed before
/// a row lays on a screen (`TimelineGridScreenHost`), so the first one
/// compiles nothing on the thread the app's frames are built on (🗣️관제
/// 2026-11-10 18:14, gpu-canonical-store ⑦ — 🔬the lay pass's two entries
/// were the first 2.9–3.5 s of a stopped UI at launch on the Surface Pro
/// 11).
///
/// Behind what the app compiles ahead for a hand
/// ([GpuEngine.compilesApartLetGo]): no row waits for them, each drawing
/// its cells itself till they are there. 🔬Asked for by the first screen
/// as the engine opened, they stood ahead of a stroke's — 0.43–0.59 s of
/// the lay pass before the first of them on the Surface Pro 11
/// (2026-11-11 06:41), 3.2 s of it on the main PC.
final appGpuGridKernels = AppKernels<({GpuGrid tiles, GpuGridLay lay})>(
  (engine) => (tiles: GpuGrid(engine), lay: GpuGridLay(engine)),
  (engine) async {
    await engine.compilesApartLetGo();
    return (
      tiles: await GpuGrid.opening(engine),
      lay: await GpuGridLay.opening(engine, bgra: ScreenTexture.bgra),
    );
  },
  (kernels) {
    kernels.tiles.free();
    kernels.lay.free();
  },
);

/// What lands a stamp on [appGpuEngine]. Warmed for the first fill or paste.
GpuStampLanding get appGpuStampLanding => appGpuStampLandingKernels.kept;
final appGpuStampLandingKernels = AppKernels<GpuStampLanding>(
  GpuStampLanding.new,
  GpuStampLanding.opening,
  (landing) => landing.free(),
);

/// How [debugGpuAdapterChoice] opens the engine — read on this isolate:
/// one [GpuEngine.opening] runs has its own, at the choice's default.
GpuEngine Function() _opener() => switch (debugGpuAdapterChoice) {
  GpuAdapterChoice.flutters => GpuEngine.onFlutterAdapter,
  GpuAdapterChoice.first => GpuEngine.onFirstAdapter,
};

/// [appGpuEngine] once [openAppGpuEngine] has opened it, null till then —
/// and again from the app letting one go till the next is open
/// ([letTheGoneAppGpuEngineGo]): what the app's screens on the engine wait
/// for, drawing as they did before it till it is there (grid-on-the-engine
/// ④, 관제 2026-11-08 20:54: 「열리기 전엔 모든 스팬이 지금의 차가운 스팬처럼
/// 클래식 — 없다가 생기는 것 없음 · 장치는 첫 프레임 뒤에」).
ValueListenable<GpuEngine?> get appGpuEngineOpen => _opened;
final _Open _opened = _Open();

/// [appGpuEngineOpen]'s word: told of each engine opened, and of each let
/// go — one never said to be open too. [appGpuEngine] opens one without a
/// word, and what stands on it is let go of all the same
/// ([StandsOnTheAppsEngine]); a value that goes from null to null tells no
/// one.
final class _Open extends ChangeNotifier
    implements ValueListenable<GpuEngine?> {
  @override
  GpuEngine? get value => _value;
  GpuEngine? _value;

  void opened(GpuEngine engine) {
    _value = engine;
    notifyListeners();
  }

  void letGo() {
    _value = null;
    notifyListeners();
  }
}

/// Opens [appGpuEngine] off this isolate ([GpuEngine.opening]) — at once
/// where it is open already — and tells [appGpuEngineOpen]. The app asks
/// after its first frame; a test that shows the engine's screens asks for
/// itself.
Future<GpuEngine> openAppGpuEngine() {
  final its = _its;
  return its.opening ??= () async {
    final opened = its.engine ?? await GpuEngine.opening(_opener());
    // Asked the other way while this one opened: the app keeps one.
    final engine = its.engine ??= opened;
    if (!identical(engine, opened)) {
      opened.close();
    }
    // Let go while it opened, its device gone: not the app's to tell of.
    if (identical(its, _its)) {
      _opened.opened(engine);
    }
    return engine;
  }();
}
