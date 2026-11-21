/// Anicel's GPU engine: one wgpu device on the adapter Flutter draws with,
/// the pool the app's tiles are stored in, and its kernels
/// (gpu-engine-skeleton, screen-on-the-engine).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, visibleForTesting;
import 'package:flutter/services.dart';

import 'src/engine_ffi.dart' as rust;
import 'src/texture_shim.dart' as shim;

/// The Android plugin (android/src/main/kotlin/.../GpuEnginePlugin.kt).
const _plugin = MethodChannel('gpu_engine');

/// What [compile] makes on [engine], off this isolate, which goes on
/// meanwhile: seconds of it on some devices (`Engine::compiling` has what
/// was measured). A static for [compile], or what a static made of plain
/// values, so only those and the engine's address cross.
Future<Pointer<T>> _compiledOff<T extends NativeType>(
  GpuEngine engine,
  Pointer<T> Function(Pointer<rust.Engine> on) compile,
) async {
  final on = engine._engine.address;
  final made = await Isolate.run(
    () => compile(Pointer.fromAddress(on)).address,
  );
  return Pointer.fromAddress(made);
}

/// How many kernels the thread that asks has waited for the compile of
/// (rust/src/kernels/shared/mod.rs, `gpu_engine_kernels_built_here`): what
/// a test holds at none on the thread an app's frames are built on
/// (🗣️관제 2026-11-10 18:14, gpu-canonical-store ⑦).
int get debugKernelsCompiledHere => rust.kernelsBuiltHere();

/// How many waits for the GPU the thread that asks has made
/// (rust/src/device.rs, `gpu_engine_waits_here`): what a test holds at
/// none on the thread an app's frames are built on, over work that is to
/// wait there for nothing (🗣️관제 2026-11-12,
/// a-lost-gpu-device-keeps-the-unsaved-tiles: 「UI(또는 래스터) 스레드를
/// 붙잡는가? 붙잡으면 (B) 안에서 엔진 스레드 비동기로 옮긴 뒤 착지한다」).
int get debugWaitsHere => rust.waitsHere();

/// How many times the thread that asks has taken an engine's device in
/// hand (rust/src/device.rs, `gpu_engine_device_entered_here`): what a
/// test holds at none on the thread an app's frames are built on — a
/// verb's body runs on the engine's thread, whatever thread calls it
/// (🗣️유저 2026-11-13, H57-Q1: 「C · 합성 전체를 엔진 스레드로」).
int get debugDeviceEnteredHere => rust.deviceEnteredHere();

/// A job the engine would not do — a C entry answered that it failed, or
/// Flutter gave it no adapter or texture to do it with —, carrying the
/// engine's last error. ⛔Everything this library throws of the device's
/// is one, never a bare [StateError]: named, so an app can tell a job its
/// graphics device refused from what its own code threw, and say so
/// (🗣️gpu-canonical-store-Q14, 유저 2026-11-11: 「공통 알림 창으로 한 번
/// 알린다」).
///
/// Sent as it is from an isolate a kernel is compiled on
/// ([GpuEngine.opening]): it holds its message alone.
base class GpuRefused extends StateError {
  GpuRefused(super.message);

  /// Whether it was refused because the device of the engine that refused
  /// it is gone ([GpuEngine.isGone]) — whichever engine that was: one the
  /// app has let go of refuses so as well, for a job that ends after.
  ///
  /// 🚨READ FROM ITS WORDS, NOT A FIELD (board
  /// a-late-refusal-of-a-let-go-engine-shows-the-restart-window,
  /// 2026-11-17): a refusal reaches the app as its message alone — from a
  /// caller's last error, a body handed over unwaited, a done, and an
  /// isolate's send — and the engine says a gone device in one place, in
  /// these words (rust/src/device.rs, `Refusals::told`), which each of
  /// those carries on.
  bool get ofAGoneDevice => message.contains(_aGoneDevice);
}

/// What the engine says of a device that is gone, wherever it says it
/// ([GpuRefused.ofAGoneDevice]).
const _aGoneDevice = 'the graphics device is gone';

/// A refusal a thread of the engine's told this isolate with no word of
/// its own — a body handed over unwaited tells only whether it worked —:
/// [what], and that the device is gone where [engine]'s is, in the
/// engine's words ([GpuRefused.ofAGoneDevice] reads them).
GpuRefused _toldRefused(GpuEngine engine, String what) =>
    GpuRefused(engine.isGone ? '$what: $_aGoneDevice' : what);

/// WHY A DEVICE WENT, as far as its engine can tell ([GpuEngine.wentBy]):
/// what the app says of it to the person once it stands on another.
///
/// 🗣️유저 2026-11-11 (a-lost-gpu-device-keeps-the-unsaved-tiles): 「그래픽
/// 장치가 왜 다시시작되었는지는 알수있게. 사용자는 앱 원인인지 다른건지
/// 모르니까 어느정도는 투명하게. 물론 확실하게 모를 가능성 높으니 그 경우
/// 가능성높은 원인을 알려주도록」.
///
/// ⚠️In the engine's order (rust/src/platform/mod.rs, `WENT_*`): the
/// number it answers is the place here.
enum GpuDeviceWent {
  /// Nothing says: Vulkan and Metal name no cause, and D3D12 none for a
  /// device its driver did not take.
  unsaid,

  /// For want of video memory.
  memory,

  /// Over what this app sent it: a job the driver stopped responding
  /// over, or a call it would not take.
  thisApp,

  /// Removed or turned off, or its driver upgraded.
  removal,

  /// Reset over a command badly formed — whose, nothing says.
  reset,

  /// Reset by its driver, which failed.
  driver;

  /// The cause the engine names by [code] — unsaid for one this library
  /// does not know.
  static GpuDeviceWent of(int code) =>
      code >= 0 && code < values.length ? values[code] : unsaid;
}

String _lastError() => using((arena) {
  const capacity = 1024;
  final buffer = arena<Uint8>(capacity);
  final length = rust.lastError(buffer, capacity);
  final count = length < capacity ? length : capacity;
  return utf8.decode(buffer.asTypedList(count), allowMalformed: true);
});

/// The entries an array of [count] is allocated, for the C ABI to read
/// [count] of: one at least, since a calloc of nothing may answer null
/// (POSIX), which ffi's allocator throws on.
int _held(int count) => count == 0 ? 1 : count;

/// [bytes] as bytes of [arena]'s, for a call that reads them there.
Pointer<Uint8> _bytes(Arena arena, List<int> bytes) =>
    arena<Uint8>(_held(bytes.length))
      ..asTypedList(bytes.length).setAll(0, bytes);

/// What a C entry answered — an index, a count —, or its last error thrown
/// where it answered -1.
int _checked(int answer) {
  if (answer < 0) {
    throw GpuRefused(_lastError());
  }
  return answer;
}

/// [rect] — [left, top, right, bottom) — as four words of [arena]'s.
Pointer<Int32> _rect(Arena arena, (int, int, int, int) rect) {
  final (left, top, right, bottom) = rect;
  return arena<Int32>(4)..asTypedList(4).setAll(0, [left, top, right, bottom]);
}

/// [_rect]'s, or null for none.
Pointer<Int32> _rectOrNull(Arena arena, (int, int, int, int)? rect) =>
    rect == null ? nullptr : _rect(arena, rect);

/// [values] as doubles of [arena]'s.
Pointer<Double> _doubles(Arena arena, List<double> values) =>
    arena<Double>(_held(values.length))
      ..asTypedList(values.length).setAll(0, values);

/// [matrix], checked to be `ColorFilter.matrix`'s twenty.
List<double> _twenty(List<double> matrix) {
  if (matrix.length != 20) {
    throw ArgumentError('a colour matrix of ${matrix.length}, not 20');
  }
  return matrix;
}

/// A kernel's submit-to-done time from its C ABI, which gives -1 on
/// failure.
Duration _ran(int nanos) {
  if (nanos < 0) {
    throw GpuRefused(_lastError());
  }
  return Duration(microseconds: nanos ~/ 1000);
}

/// 🚨WHAT ONE ENGINE MADE IS NAMED TO NO OTHER'S JOB. Each engine has a
/// wgpu instance of its own, and wgpu looks what a job names up in the
/// instance the job is on: a buffer of another's is no error it raises —
/// it panics, which ends the process, or, where the two instances' numbers
/// happen to meet, takes another buffer for it (🔬2026-11-13: `Cannot get
/// BufferId(2,2), found other resource BufferId(2,1)` — a picture made on
/// an engine the app had let go, its device gone, carried by the kernels
/// of the one it opened next; 🗣️gpu-canonical-store-Q11, 유저 2026-11-10:
/// 「장치를 잃으면 앱은 꺼지지 않고 새 장치를 열어 사본으로 되살린다」 — an
/// app that opens a second engine in its life is where two meet).
///
/// So what holds something a device made is of ONE engine, this one, and a
/// job names what another object holds through the engine the job is on
/// alone ([GpuEngine._its]), which refuses another's by name. No read of
/// another object's pointer is written any other way
/// (`test/architecture/a_job_names_what_its_own_engine_made_test.dart`).
///
/// ⛔Not one wgpu instance for every engine, which would make of a mixed
/// job an error wgpu raises (↩️weighed 2026-11-13): an adapter whose
/// driver was updated — the commonest loss, and a harmless one — is seen
/// by a DXGI factory made after the update and by none made before
/// (Microsoft Learn, `IDXGIFactory1::IsCurrent`, read that day; ⚠️read,
/// not measured — no test updates a driver), and an engine opened anew
/// makes its instance anew (rust/src/platform).
abstract interface class _OfAnEngine {
  /// The engine what it holds was made on.
  GpuEngine get _engine;
}

/// One wgpu device on the adapter Flutter draws with.
class GpuEngine {
  GpuEngine._(this._engine, this.adapterLuid);

  /// Opens on Flutter's own adapter, so what the engine writes lives on
  /// the GPU that shows it: on Windows the one Flutter names by LUID;
  /// elsewhere Flutter names none to a plugin, so the only one there is
  /// (rust/src/device.rs, `open_sole`).
  factory GpuEngine.onFlutterAdapter() {
    if (!Platform.isWindows) {
      return GpuEngine._(_opened(rust.engineOpenSole()), null);
    }
    final luid = shim.flutterAdapterLuid();
    if (luid == 0) {
      throw GpuRefused('Flutter gave no graphics adapter');
    }
    return GpuEngine._(_opened(rust.engineOpen(luid)), luid);
  }

  /// Opens on the platform's first adapter — `flutter test`'s, where no
  /// Flutter names one (rust/src/device.rs, `open_first`).
  factory GpuEngine.onFirstAdapter() =>
      GpuEngine._(_opened(rust.engineOpenFirst()), null);

  /// [open] — one of the factories above — run on an isolate of its own,
  /// the engine coming back by its address, so the caller's isolate goes
  /// on while a device opens (0.6–1.2 s, 보드/인프라 2026-11-07). The device
  /// opens on a thread of the engine's own either way (rust/src/device.rs,
  /// `opened`), but the isolate that asks waits for that thread
  /// (grid-on-the-engine, 관제 2026-11-08 20:54: 「장치는 첫 프레임 뒤에」).
  static Future<GpuEngine> opening(GpuEngine Function() open) async {
    final (address, luid) = await Isolate.run(() {
      final engine = open();
      return (engine._engine.address, engine.adapterLuid);
    });
    return GpuEngine._(Pointer.fromAddress(address), luid);
  }

  static Pointer<rust.Engine> _opened(Pointer<rust.Engine> engine) {
    if (engine == nullptr) {
      throw GpuRefused(_lastError());
    }
    return engine;
  }

  /// Names [folder] as where each engine opened from now on keeps the
  /// shaders it compiles, for the next launch to hand its driver instead
  /// of compiling them again — on Windows what DXC made, and what the
  /// driver made of each pipeline on it (rust/vendor/wgpu-hal,
  /// compile_cache.rs). 🗣️유저 2026-11-13,
  /// the-wait-window-stands-seven-seconds-on-the-surface-Q1 「디스크 캐시」.
  static void keepShadersIn(String folder) => using((arena) {
    final bytes = utf8.encode(folder);
    rust.keepShadersIn(_bytes(arena, bytes), bytes.length);
  });

  final Pointer<rust.Engine> _engine;

  /// Whether [close] has freed it ([_whyNotDone]).
  bool _closed = false;

  /// The adapter's LUID where Flutter names its adapter by one (Windows).
  final int? adapterLuid;
  Pointer<rust.Fill>? _fill;

  Pointer<rust.Fill> get _fillKernel => _fill ??= rust.fillNew(_engine);

  /// [made], for a job on this engine to name — refused by name where
  /// another engine made it ([_OfAnEngine]).
  T _its<T extends _OfAnEngine>(T made) {
    if (!identical(made._engine, this)) {
      throw GpuRefused('a job on one engine named what another engine made');
    }
    return made;
  }

  String get adapterName => using((arena) {
    const capacity = 256;
    final buffer = arena<Uint8>(capacity);
    final length = rust.engineAdapterName(_engine, buffer, capacity);
    final count = length < capacity ? length : capacity;
    return utf8.decode(buffer.asTypedList(count), allowMalformed: true);
  });

  /// This process's use of the adapter's memory, as the OS says it
  /// ([GpuVideoMemory]).
  GpuVideoMemory get videoMemory => using((arena) {
    final report = arena<rust.VideoMemoryReport>();
    rust.engineVideoMemory(_engine, report);
    final said = report.ref;
    int? where(int bit, int bytes) => said.flags & bit == 0 ? null : bytes;
    return (
      integrated: said.flags & rust.videoMemoryIntegrated != 0,
      used: where(rust.videoMemoryUsedSaid, said.used),
      budget: where(rust.videoMemoryBudgetSaid, said.budget),
      inSystem: where(rust.videoMemoryInSystemSaid, said.inSystem),
      total: where(rust.videoMemoryTotalSaid, said.total),
    );
  });

  /// The bytes the engine keeps for pictures that are no picture's. Every
  /// [GpuScreen]'s canvas lies in slots of one pool of the engine's, as a
  /// cel's tiles do in a [GpuPool]'s, and a page of it stays made for the
  /// next picture: its slots nobody holds are these —
  /// and the composite's work buffer, kept from one run to the next, and
  /// the buffers its composes run in, kept from one compose to the next
  /// while a hand is at work and none at rest ([restsAfter]). Till they
  /// are given back ([givePicturesBackPast]).
  int get idlePictureBytes => rust.picturesIdleBytes(_engine);

  /// The bytes of the tiles the engine's pictures hold that none of them
  /// weighs. Screens composed of the same hold one tile for it, weighed by
  /// the screen that made it ([GpuScreen.bytes]); that one let go while
  /// others hold the tile, none of them weighs it — these, till the last
  /// of them lets it go, each as it lies ([GpuScreen.bytes]). What a
  /// budget and the memory census count beside the screens' own bytes;
  /// read off no lock, on any thread.
  int get unownedPictureBytes => rust.picturesUnownedBytes(_engine);

  /// Gives back what the engine keeps for pictures nobody holds till it is
  /// [mostIdle] bytes: the pages of their pool with every slot free, the
  /// last first, then the buffers a compose's rows run first are made in
  /// and then the composite's work buffer — what only makes the next
  /// picture cheaper, as a [GpuPool]'s free pages are
  /// ([GpuPool.giveBackPast]). A page a picture is on stays.
  void givePicturesBackPast(int mostIdle) =>
      rust.picturesGiveBack(_engine, mostIdle);

  /// How long after the last compose handed to an engine the hand is
  /// taken to rest: the engine then lets go of the buffers its composes
  /// ran in and kept for the next (rust/src/kernels/composite/spares.rs,
  /// `gpu_engine_pictures_rest`). Null where no launch said so — a
  /// test's engine arms no timer, which a widget test's clock would not
  /// end (as the app's `EngineTileLedger.copiesAtRest`).
  ///
  /// 🗣️유저 2026-11-20 23:20 (a-transform-drag-over-folder-rows-draws-a-
  /// frame-in-a-third-of-a-second-Q1 = b): 「손을 떼면 바로 놓는다」 —
  /// 「들고있는게 너무 비효율적인거같은데」. What a drag takes again from
  /// one compose to the next is kept through no rest.
  static Duration? restsAfter;

  /// What lets go once the hand rests ([_composed]).
  Timer? _atRest;

  /// A compose was handed over — [GpuComposite.run], [GpuComposite.show],
  /// [GpuScreen.compose], [GpuScreen.composeOver] —: a hand is at work,
  /// and rests once none is for [restsAfter]. The engine takes the rest
  /// in turn behind what it was handed before, this isolate waiting for
  /// none of it.
  void _composed() {
    final rest = restsAfter;
    if (rest == null) {
      return;
    }
    _atRest?.cancel();
    _atRest = Timer(rest, _rests);
  }

  /// The hand rests ([_composed]): the engine lets go of what its
  /// composes kept and folds its pictures' tiles, and tells this isolate
  /// once those folds are through ([_rested]).
  void _rests() =>
      rust.picturesRest(_engine, _rested.told, _rested.kept(this));

  /// The rests on their way ([_rests]), each told by its number once its
  /// folds are through, and whether the engine's pictures were weighed
  /// again by then — not where a hand at work ended the folds, nor where
  /// none ran (rust/src/kernels/pool/mod.rs, `Pictures::rests`).
  static final _rested = _Told<GpuEngine>((_, _, weighed) {
    if (weighed) {
      _picturesWeighedAgain.tick();
    }
  });

  static final _picturesWeighedAgain = _Ticks();

  /// Ticks each time a rest has weighed an engine's pictures again, each
  /// tile as it lies ([GpuScreen.bytes]) — any engine's of this isolate.
  ///
  /// WHAT THE PICTURES WEIGH IS THE ROOM THEIR KEEPERS HAVE: a screen's
  /// bytes are read, not heard, and folded at a rest they read lighter
  /// with nothing told — one that keeps pictures within a line, and rests
  /// for want of room, looks again by this (the app's playback line).
  static Listenable get picturesWeighedAgain => _picturesWeighedAgain;

  /// Test seam: whether anyone hears [picturesWeighedAgain] — what a
  /// keeper let go of must not: the ticks outlive every keeper.
  @visibleForTesting
  static bool get debugPicturesWeighedAgainIsHeard =>
      _picturesWeighedAgain.isHeard;

  /// Test seam: whether a rest is on its way ([_composed]).
  @visibleForTesting
  bool get debugRestOnItsWay => _atRest?.isActive ?? false;

  /// Whether the device is gone — the driver took it away (a reset, an
  /// update, a wake from sleep), or the engine's thread ended under it
  /// (rust/src/device.rs, `Refusals`): every job that waits for it is
  /// refused from then on ([GpuRefused]), and nothing made on this engine
  /// is of use again. Known once a job has waited — the word that a
  /// device is lost comes inside a wait.
  ///
  /// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
  /// 유지한다」 — a lost device is not the app's end.
  bool get isGone => rust.engineGone(_engine);

  /// Why the device went, as far as anything says ([GpuDeviceWent]) —
  /// unsaid while it is there.
  GpuDeviceWent get wentBy => GpuDeviceWent.of(rust.engineWentBy(_engine));

  /// What this engine submitted that the GPU has not said it finished, the
  /// oldest first, after the newest it has — a line each:
  /// `submit #N at MICROS FILE:LINE dispatches=N groups=N STATE`, STATE
  /// `unfinished` or `last-done` — its MICROS on the clock [DateTime.now]'s
  /// `microsecondsSinceEpoch` reads.
  /// Asks nothing of the engine's thread or the device: what the app
  /// writes down as a device goes (H63).
  String get unfinishedSubmits => using((arena) {
    const capacity = 16384;
    final buffer = arena<Uint8>(capacity);
    final length = rust.engineUnfinished(_engine, buffer, capacity);
    final count = length < capacity ? length : capacity;
    return utf8.decode(buffer.asTypedList(count), allowMalformed: true);
  });

  /// Test seam: the error the device raised that no job has been refused
  /// by yet, or null — taken, so no job is refused by it after. An error
  /// on a way that never waits is told to no one, and a test asks as it
  /// ends.
  String? debugTakeNoted() => using((arena) {
    const capacity = 1024;
    final buffer = arena<Uint8>(capacity);
    final length = rust.engineNoted(_engine, buffer, capacity);
    if (length == 0) {
      return null;
    }
    final count = length < capacity ? length : capacity;
    return utf8.decode(buffer.asTypedList(count), allowMalformed: true);
  });

  /// Test seam: the device destroyed — the nearest a test comes to a
  /// driver taking it away, which no test does. [isGone] says so once a
  /// job has waited — at once where it went [forMemory], the one cause a
  /// test can name ([wentBy]).
  void debugLose({bool forMemory = false}) =>
      rust.engineLose(_engine, forMemory);

  /// Test seam: the engine's thread stands still for [time] in its turn,
  /// this isolate waiting for none of it — what a test does meanwhile
  /// meets what is handed over behind it before it has run.
  void debugStandStill(Duration time) =>
      rust.engineStandStill(_engine, time.inMilliseconds);

  /// Ends once the GPU has finished all that was submitted on this engine,
  /// with no wait on this isolate, which goes on meanwhile: the engine's
  /// thread for waits does (rust/src/device.rs, `gpu_engine_done_then`) —
  /// and no job of this or any isolate stands behind it. Fails by a
  /// [GpuRefused] naming why where it did not finish — past the engine's
  /// limit, or the device gone — as a wait does; and where a body handed
  /// over unwaited from this isolate's thread since its last done failed,
  /// by the first of those ([GpuScreen.compose], [GpuScreen.show]) —
  /// asked of the GPU behind each of them (rust/src/device.rs,
  /// `Engine::done_then`). One asked in the turn a body is handed over is
  /// told of that body.
  ///
  /// 🗣️유저 2026-11-12 (a-float-in-hand-draws-the-frame-as-it-stands-Q2):
  /// a screen's frame is put up as the GPU finishes it, the thread that
  /// builds the app's frames waiting for none of it ([debugWaitsHere]).
  ///
  Future<void> done() {
    final ended = Completer<void>();
    rust.doneThen(
      _engine,
      _waits.told,
      _waits.kept((ended: ended, engine: this)),
    );
    return ended.future;
  }

  /// The waits on their way ([done]), and how a thread of the engine's
  /// tells this isolate one has ended: by its number, and whether the GPU
  /// finished.
  static final _waits = _Told<({Completer<void> ended, GpuEngine engine})>((
    wait,
    asked,
    finished,
  ) {
    if (finished) {
      asked.ended.complete();
    } else {
      asked.ended.completeError(GpuRefused(asked.engine._whyNotDone(wait)));
    }
  });

  /// Why the wait [wait] did not end with the GPU done — taken. 🚨Of an
  /// engine closed meanwhile nothing is read: its thread tells the waits
  /// still on their way as it goes, and they come here after it has.
  String _whyNotDone(int wait) {
    if (_closed) {
      return 'the engine was closed before the GPU had finished';
    }
    return using((arena) {
      const capacity = 1024;
      final buffer = arena<Uint8>(capacity);
      final length = rust.doneFailure(_engine, wait, buffer, capacity);
      final count = length < capacity ? length : capacity;
      return utf8.decode(buffer.asTypedList(count), allowMalformed: true);
    });
  }

  /// A texture of [width] × [height] 8-bit texels, BGRA when [bgra].
  GpuSurface surface(int width, int height, {required bool bgra}) {
    final surface = rust.surfaceNew(_engine, width, height, bgra);
    if (surface == nullptr) {
      throw GpuRefused(_lastError());
    }
    return GpuSurface._(this, surface, width, height, bgra);
  }

  /// A Flutter texture of [width] × [height] RGBA texels that the engine
  /// presents into — Android's way to the screen.
  Future<GpuWindow> window(int width, int height) async {
    final made = (await _plugin.invokeMapMethod<String, int>('window', {
      'width': width,
      'height': height,
    }))!;
    final textureId = made['textureId']!;
    final window = rust.windowNew(
      _engine,
      Pointer.fromAddress(made['window']!),
      width,
      height,
    );
    if (window == nullptr) {
      final error = _lastError();
      await _plugin.invokeMethod<void>('release', {'textureId': textureId});
      throw GpuRefused(error);
    }
    return GpuWindow._(this, window, textureId);
  }

  /// Test seam: the engine keeps none of its kernels, as a launch finds it
  /// (rust/src/device.rs, `Kernels`) — what holds one keeps it, and the
  /// next asked for is compiled.
  void debugForgetKernels() => rust.kernelsForget(_engine);

  /// [ahead], what the engine compiles apart — a composite's own passes,
  /// which no one waits for — waiting till it is through, however it ends:
  /// the compiler is one, and a pass asked for meanwhile takes a second of
  /// it between two of the kernels [ahead] compiles (rust/src/device.rs,
  /// `Apart`).
  ///
  /// ⛔No hold without its letting go (🗣️관제 2026-11-11 06:07: 「잡은 것은
  /// 모든 길에서 놓여야 한다」): a hold left on, no plan would ever run on a
  /// pass of its own. The last let go is what [compilesApartLetGo] waits
  /// for.
  Future<T> whileCompilesApartWait<T>(Future<T> Function() ahead) async {
    rust.apartHold(_engine);
    try {
      return await ahead();
    } finally {
      rust.apartLet(_engine);
      if (rust.apartHeld(_engine) == 0) {
        _apartLetGo?.complete();
        _apartLetGo = null;
      }
    }
  }

  /// Completes once nothing holds what the engine compiles apart
  /// ([whileCompilesApartWait]): where what this isolate has compiled off
  /// it with no one waiting for it — the frame grids' kernels, each row
  /// drawing itself till they are there — stands before it asks for the
  /// compiler.
  ///
  /// 🚨★★★A WAIT FOR A HOLD IS MADE WHERE THE HOLD IS LET GO — on this
  /// isolate, never on a worker. 🐞the-windows-app-stays-after-its-window-
  /// closes (관제 2026-11-16 00:46, the build round's smoke): this waited on
  /// a worker ([Isolate.run]) in the engine (`Apart::wait`), and the app
  /// closed while it compiled ahead what a hand needs never ended — the
  /// isolate that would let go went down first, and the VM waited for the
  /// worker for good. 🔬A release with each worker named, closed 15 s into a
  /// launch of a fresh profile: `waiting for isolate gpu_engine:477 to
  /// check in` past 40 s; closed at 60 s, gone in 0.5 s (공통 2026-11-16).
  /// ⛔So the engine has no verb that waits for a hold: a worker cannot
  /// stand for what only the app's isolate does.
  ///
  /// ⚠️Holds made through this [GpuEngine] are the ones that wake it: the
  /// app holds and waits on its own isolate (`compileAppKernelsAhead`).
  Future<void> compilesApartLetGo() async {
    // A turn of this isolate first: who holds as the engine is told open
    // holds within that turn, and is seen here.
    await Future<void>.delayed(Duration.zero);
    if (rust.apartHeld(_engine) == 0) {
      return;
    }
    await (_apartLetGo ??= Completer<void>()).future;
  }

  /// What [compilesApartLetGo] waits for while a hold is on: completed as
  /// the last is let go ([whileCompilesApartWait]).
  Completer<void>? _apartLetGo;

  /// Test seam: how many hold what the engine compiles apart
  /// ([whileCompilesApartWait]).
  int get debugCompilesApartHeld => rust.apartHeld(_engine);

  /// Frees the device; every surface must be freed first.
  void close() {
    _closed = true;
    // A rest on its way would be taken on an engine freed.
    _atRest?.cancel();
    final fill = _fill;
    if (fill != null) {
      rust.fillFree(fill);
    }
    rust.engineClose(_engine);
  }
}

/// What a kernel writes for the screen to show: a [GpuSurface] Flutter
/// shows through a [SharedTexture], or a [GpuWindow]'s next image — one
/// kernel entry for both (rust/src/kernels/mod.rs).
sealed class GpuTarget implements _OfAnEngine {
  GpuTarget(this._engine);

  @override
  final GpuEngine _engine;

  /// The texture the kernel writes.
  Pointer<rust.Texture> get _texture;

  /// Fills the target with the pattern for [seed] and waits for the GPU;
  /// returns the submit-to-done time.
  Duration fill(int seed) => _ran(
    rust.fillRun(_engine._fillKernel, _engine._engine, _texture, seed),
  );
}

/// A texture the compute pass fills and Flutter shows.
class GpuSurface extends GpuTarget {
  GpuSurface._(
    super._engine,
    this._surface,
    this.width,
    this.height,
    this.bgra,
  );

  final Pointer<rust.Surface> _surface;
  final int width;
  final int height;
  final bool bgra;

  Pointer<Void> get _handle => rust.surfaceHandle(_surface);

  @override
  Pointer<rust.Texture> get _texture => rust.surfaceTexture(_surface);

  /// The CRC-32 of the surface's bytes, read back from the GPU — the
  /// fingerprint the ledger `test/fixtures/fingerprints.json` pins.
  int fingerprint() => using((arena) {
    final hash = arena<Uint32>();
    if (!rust.surfaceFingerprint(_engine._engine, _surface, hash)) {
      throw GpuRefused(_lastError());
    }
    return hash.value;
  });

  /// The surface's pixels read back from the GPU: straight from its
  /// texture, premultiplied, RGBA whichever way it is laid, row after row
  /// with nothing between.
  ///
  /// The engine writes them where the list keeps them, freed with it: no
  /// stage zeroed first, no copy after. 🔬2026-11-17, main PC, the float
  /// landing test's file — a test's screen is read as each frame of it is
  /// laid — 28 s of its 487 zeroing a 63 MB stage and 25 s copying it out
  /// (board ci-heaviest-files-draw-on-the-cpu).
  Uint8List read() {
    final count = width * height * 4;
    final bytes = malloc<Uint8>(_held(count));
    if (!rust.surfaceRead(_engine._engine, _surface, bytes, count)) {
      malloc.free(bytes);
      throw GpuReadFailed(_lastError());
    }
    final pixels = bytes.asTypedList(count, finalizer: malloc.nativeFree);
    if (bgra) {
      for (var at = 0; at < count; at += 4) {
        final blue = pixels[at];
        pixels[at] = pixels[at + 2];
        pixels[at + 2] = blue;
      }
    }
    return pixels;
  }

  /// What a D3D11 device of Flutter's adapter sees when it opens the
  /// handle, as ANGLE will; null when it cannot open it, and off Windows,
  /// where Flutter draws with no ANGLE.
  ({int format, int bindFlags, int miscFlags})? inspect() => using((arena) {
    if (!Platform.isWindows) {
      return null;
    }
    final format = arena<Uint32>();
    final bindFlags = arena<Uint32>();
    final miscFlags = arena<Uint32>();
    if (!shim.inspectShared(_handle, format, bindFlags, miscFlags)) {
      return null;
    }
    return (
      format: format.value,
      bindFlags: bindFlags.value,
      miscFlags: miscFlags.value,
    );
  });

  /// Frees the surface; Flutter must no longer show it.
  void free() => rust.surfaceFree(_surface);
}

/// The side of the tiles a [GpuPool] stores, in texels: a tile is that
/// square of straight RGBA8, [gpuTileBytes] long.
final int gpuTileSide = rust.tileSide();

/// The bytes of a tile a [GpuPool] stores.
final int gpuTileBytes = gpuTileSide * gpuTileSide * 4;

/// Where a [GpuPool] keeps a tile: a slot of one of its pages.
typedef GpuTile = ({int page, int slot});

/// What the OS says of this process's use of an engine's adapter, in
/// bytes: of its local video memory (`used`), the budget it gives the
/// process there (`budget`), what of its video memory lies in the
/// system's RAM (`inSystem`) and all the adapter's own memory (`total`)
/// — each null where the OS says none (Android and Linux say nothing;
/// Apple, no budget, no RAM apart and no memory of its own) — and whether
/// the adapter is one that shares the system's RAM (`integrated`).
typedef GpuVideoMemory = ({
  bool integrated,
  int? used,
  int? budget,
  int? inSystem,
  int? total,
});

/// A tile with nothing on it, as a tile set names one.
const _noTile = 0xFFFFFFFF;

/// [tiles] — a tile set's [columns] × [rows], row by row, null for one with
/// nothing on it — as the words the C ABI names a set by: `page << 16 |
/// slot` each (`TileAt::word`), [_noTile] for none. A plan's tile sets and
/// the ink scan's cel alike.
Pointer<Uint32> _tileWords(
  Arena arena,
  int columns,
  int rows,
  List<GpuTile?> tiles,
) {
  if (tiles.length != columns * rows) {
    throw ArgumentError('$columns × $rows tiles, not ${tiles.length}');
  }
  final words = arena<Uint32>(_held(tiles.length));
  for (var at = 0; at < tiles.length; at++) {
    final tile = tiles[at];
    words[at] = tile == null ? _noTile : tile.page << 16 | tile.slot;
  }
  return words;
}

/// A read back the engine refused: the tiles' bytes never came. Named so a
/// caller can tell it from what its own work threw — a save, from a file
/// that refused it (`SaveFailureCause.engineRead`).
final class GpuReadFailed extends GpuRefused {
  GpuReadFailed(super.message);
}

/// The engine's pages of tiles (rust/src/kernels/pool): each tile stored
/// lands in a fresh slot of its cel and stays there until let go.
class GpuPool implements _OfAnEngine {
  /// A pool on [engine] that makes no page past [mostBytes] — of pages of
  /// [debugTilesAPage] tiles where a test says so, which fills one with
  /// a few; as large as the engine makes them else
  /// (rust/src/kernels/pool/mod.rs, `gpu_engine_pool_new`, has why a
  /// test asks).
  factory GpuPool(GpuEngine engine, int mostBytes, {int? debugTilesAPage}) {
    final pool = rust.poolNew(
      engine._engine,
      debugTilesAPage == null ? _anyPage : debugTilesAPage * gpuTileBytes,
      mostBytes,
    );
    if (pool == nullptr) {
      throw GpuRefused(_lastError());
    }
    return GpuPool._(engine, pool);
  }

  GpuPool._(this._engine, this._pool);

  /// Past any page: what leaves a pool's pages as large as the engine
  /// makes them.
  static const int _anyPage = 0x7fffffffffffffff;

  @override
  final GpuEngine _engine;
  final Pointer<rust.Pool> _pool;

  /// A cel: the tiles stored under it go to pages of theirs first, then to
  /// any page with room (rust/src/kernels/pool/mod.rs).
  int cel() => rust.poolCel(_pool);

  /// Gives [tiles] fresh slots of [cel] and returns where each goes, in
  /// order: all of them, or the first few where the pool is full at the
  /// next. The bytes of each — [gpuTileBytes] at the pointer [bytesOf]
  /// reads of it — are copied there on the engine's thread, this isolate
  /// waiting for none of it (rust/src/kernels/pool/mod.rs,
  /// `gpu_engine_pool_store`, has why): so [tiles], what keeps their bytes
  /// where [bytesOf] says, are held here till that copy has read them, and
  /// the places of a copy that failed are handed to [onUnwritten].
  List<GpuTile> store<T extends Object>(
    int cel,
    List<T> tiles,
    Pointer<Uint8> Function(T tile) bytesOf,
  ) {
    return using((arena) {
      final count = tiles.length;
      final at = arena<Pointer<Uint8>>(_held(count));
      for (var tile = 0; tile < count; tile++) {
        at[tile] = bytesOf(tiles[tile]);
      }
      final pages = arena<Uint16>(_held(count));
      final slots = arena<Uint16>(_held(count));
      // 🚨A REAL HOLD, in what is kept till its copy is told of: a pointer
      // [bytesOf] read keeps nothing alive, and a tile collected meanwhile
      // hands its block to the next tile made (BitmapTile.readPixels).
      // ⛔No assert: it goes from a release build, and so would the hold.
      final stored = _stores.handing(
        (pool: this, held: tiles),
        (number) => rust.poolStore(
          _pool,
          _engine._engine,
          cel,
          at,
          count,
          pages,
          slots,
          _stores.told,
          number,
        ),
      );
      return [
        for (var tile = 0; tile < stored; tile++)
          (page: pages[tile], slot: slots[tile]),
      ];
    });
  }

  /// Handed the places whose copy the engine's thread could not write
  /// ([store]): theirs to let go, whose tiles are not there.
  void Function(List<GpuTile> unwritten)? onUnwritten;

  /// What the stores on their way hold ([store]) till their copy has read
  /// them, and how the engine's thread tells this isolate one has: by its
  /// number, and whether it wrote them.
  static final _stores = _Told<({GpuPool pool, List<Object> held})>((
    _,
    stored,
    written,
  ) {
    final pool = stored.pool;
    if (written || pool._freed) {
      return;
    }
    final unwritten = pool._unwritten();
    if (unwritten.isNotEmpty) {
      pool.onUnwritten?.call(unwritten);
    }
  });

  /// The places stores handed over held and did not write, taken.
  List<GpuTile> _unwritten() => using((arena) {
    const capacity = 256;
    final pages = arena<Uint16>(capacity);
    final slots = arena<Uint16>(capacity);
    return [
      for (
        var taken = rust.poolUnwritten(_pool, pages, slots, capacity);
        taken > 0;
        taken = rust.poolUnwritten(_pool, pages, slots, capacity)
      )
        for (var at = 0; at < taken; at++) (page: pages[at], slot: slots[at]),
    ];
  });

  /// Lets [tile] go; false where no tile is held there.
  bool release(GpuTile tile) => rust.poolRelease(_pool, tile.page, tile.slot);

  /// Hands the engine's thread a fold of the tiles next to fold — [most]
  /// at most, by [kernels] — and gives them their places once it is told,
  /// this isolate waiting for none of it
  /// (rust/src/kernels/pool/folded.rs): a tile folded keeps the place
  /// that names it, and reads as it was. How many it folded — none
  /// where no tile of the pool's is left to fold as it stands, and none
  /// where the fold failed: its tiles stay as they are, the next fold's
  /// to take again.
  ///
  /// [kernels] are handed in compiled, so no fold compiles where it is
  /// asked (`Pool::folds_unwaited` has why); let go meanwhile, they go
  /// behind the fold on the engine's thread.
  Future<int> fold(GpuFold kernels, int most) async {
    final told = Completer<bool>();
    final handed = _folds.handing(
      told,
      (number) => rust.poolFold(
        _pool,
        _engine._engine,
        _engine._its(kernels)._fold,
        most,
        _folds.told,
        number,
      ),
    );
    if (handed == 0) {
      return 0;
    }
    final folded = await told.future;
    // Freed meanwhile, its books went with it — what was folded too. A
    // fold that failed is settled as well: its tiles are the next's.
    if (!_freed) {
      rust.poolSettle(_pool, _engine._engine);
    }
    return folded ? handed : 0;
  }

  /// The folds on their way ([fold]), each told by its number once its
  /// tiles are folded — or not, which leaves them as they are: the
  /// settle gives a place to what there is.
  static final _folds = _Told<Completer<bool>>(
    (_, told, folded) => told.complete(folded),
  );

  /// Reads [tiles], each held, back into [into] — [gpuTileBytes] each, in
  /// order: waits for the GPU (rust/src/kernels/pool/mod.rs `Pool::read`).
  void read(List<GpuTile> tiles, Pointer<Uint8> into) => using((arena) {
    final words = _tileWords(arena, tiles.length, 1, tiles);
    if (!rust.poolRead(_pool, _engine._engine, words, tiles.length, into)) {
      throw GpuReadFailed(_lastError());
    }
  });

  /// [tiles], each held, on their way back: their bytes as their slots
  /// hold them now — [gpuTileBytes] each, in order —, for a readout to map
  /// with no wait here ([GpuReadout.mapping]) and hand over a tile a row
  /// ([GpuReadout.rows]). Submits the work and waits for none of it: a
  /// slot let go and written over meanwhile is read as it was
  /// (rust/src/kernels/pool/mod.rs `Pool::read_out`).
  GpuReadout readout(List<GpuTile> tiles) => using((arena) {
    final words = _tileWords(arena, tiles.length, 1, tiles);
    final readout = rust.poolReadout(
      _pool,
      _engine._engine,
      words,
      tiles.length,
    );
    if (readout == nullptr) {
      throw GpuReadFailed(_lastError());
    }
    return GpuReadout._(_engine, readout);
  });

  /// Makes no page more past [mostBytes]: the pages made stay — till
  /// [giveBackPast] — and the next is made only within it, but the page
  /// a fold's tiles need ([fold]): a pool at its line folds on, and
  /// comes under it (rust/src/kernels/pool/folded.rs,
  /// `Pool::folded_page_to_come`).
  void makeNoPagePast(int mostBytes) => rust.poolMostBytes(_pool, mostBytes);

  /// Keeps to [bytes] in place of the budget the OS gives this process;
  /// the OS's again where null.
  void keepToInsteadOfTheOs(int? bytes) =>
      rust.poolBudgetInstead(_pool, bytes ?? -1);

  /// Gives back the pages none of whose tiles is held, the last first, till
  /// the pages made hold [mostBytes]; a cel that needs a page again has it
  /// made again (rust/src/kernels/pool/mod.rs).
  void giveBackPast(int mostBytes) =>
      rust.poolGiveBack(_pool, _engine._engine, mostBytes);

  /// The bytes of the pages made, each counted whole — one given back by
  /// the tile's stand-in left in its place.
  int get bytes => rust.poolBytes(_pool);

  /// The bytes of the page made ahead of the store that needs it — none
  /// till it is made. Not among [bytes], which a store's budget counts
  /// (rust/src/kernels/pool/mod.rs).
  int get aheadBytes => rust.poolAheadBytes(_pool);

  /// Frees the pool's pages; before its engine is closed.
  void free() {
    _freed = true;
    rust.poolFree(_pool);
  }

  /// Freed: a store's copy told of after asks the pool nothing.
  bool _freed = false;
}

/// A bitmap dabs read — a tip's or the paper's — kept for the piles that read
/// it, and let go with this object.
final class GpuDabTexture implements Finalizable {
  /// [texels], [side] × [side] on 0..=1 row after row.
  factory GpuDabTexture(Float64List texels, int side) {
    final made = using(
      (arena) => rust.dabTextureNew(_doubles(arena, texels), side),
    );
    if (made == nullptr) {
      throw GpuRefused(_lastError());
    }
    final texture = GpuDabTexture._(made);
    _freed.attach(texture, made.cast());
    return texture;
  }

  GpuDabTexture._(this._texture);

  static final NativeFinalizer _freed = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<rust.DabTexture>)>>(
      rust.dabTextureFree,
    ).cast(),
  );

  final Pointer<rust.DabTexture> _texture;
}

/// A round tip's two tables and how they are read
/// (rust/src/kernels/dab/mod.rs `RoundProfile`).
typedef GpuRoundTip = ({
  Float64List coverage,
  Float64List pile,
  double scale,
  double reach,
  double inner,
  int rowLength,
});

/// A dab as a stroke piles it (rust/src/kernels/dab/mod.rs `Dab`). Its tip
/// is [round] where that is not null, the bitmap [tip] over [-[radius],
/// [radius]] where that is not, else square.
final class GpuDab {
  GpuDab({
    required this.centreX,
    required this.centreY,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.colour,
    required this.opacity,
    required this.flow,
    required this.contrast,
    this.threshold = false,
    this.edgeHeld = false,
    this.erase = false,
    this.second = false,
    this.round,
    this.tip,
    this.radius = 0,
    this.cos = 1,
    this.sin = 0,
    this.roundness = 1,
    this.evening,
    this.density,
    this.mixStep,
  });

  final double centreX;
  final double centreY;

  /// The pixels it may touch, [left, top, right, bottom).
  final int left;
  final int top;
  final int right;
  final int bottom;

  /// Red, green, blue and alpha, from the low byte.
  final int colour;
  final double opacity;
  final double flow;

  /// A contrast about half; 1 leaves the coverage as it is. Not read where
  /// [threshold] cuts it at half.
  final double contrast;
  final bool threshold;
  final bool edgeHeld;
  final bool erase;

  /// Whether it piles on the stroke's second plane.
  final bool second;
  final GpuRoundTip? round;
  final GpuDabTexture? tip;
  final double radius;
  final double cos;
  final double sin;

  /// The tip's minor axis over its major.
  final double roundness;

  /// The table it lays its share through, 1026 entries, or none.
  final Float64List? evening;

  /// How much of the paper it takes, where it meets the paper.
  final double? density;

  /// The mixing step whose colour it lays in place of [colour]
  /// ([GpuMixStep] — the stroke's chain, from 0), or none.
  final int? mixStep;
}

/// A mixing brush's step as the stroke runs it
/// (rust/src/kernels/dab/mix.rs `Step`): where its dab reads the ground
/// — [centreX], [centreY], [radius] — and what the brush's curves and
/// dice made of its paint (`BrushGroundColorMixer`).
final class GpuMixStep {
  const GpuMixStep({
    required this.centreX,
    required this.centreY,
    required this.radius,
    required this.colour,
    required this.refill,
    required this.laid,
    required this.density,
    required this.take,
    required this.share,
    required this.pick,
    required this.dry,
  });

  final double centreX;
  final double centreY;
  final double radius;

  /// The drawing colour: red, green, blue and alpha, from the low byte.
  final int colour;

  /// A loaded brush's refill toward the drawing colour, the share of it
  /// laid over what it carries, and its thickness.
  final double refill;
  final double laid;
  final double density;

  /// A dry brush's pickup.
  final double take;

  /// The share of a whole stamp it is, and what a whole one lifts.
  final double share;
  final double pick;

  /// A brush with no paint of its own.
  final bool dry;
}

/// A pile's mixing ([GpuStroke.pile]): the steps met since the last —
/// [first] the first's place in the stroke's chain —, and the cel they
/// read, [under] telling the cel's tile at each ground tile asked, in
/// the order asked, null where the cel has none — on [pool], copied by
/// [composite].
typedef GpuMixing = ({
  GpuComposite composite,
  GpuPool pool,
  List<GpuMixStep> steps,
  int first,
  List<GpuTile?> Function(List<({int column, int row})> ground) under,
});

/// What a landed tile is beside the one under it
/// (rust/src/kernels/write/mod.rs `Change`).
enum GpuChange { same, inked, cleared }

/// A tile a landing was asked for: its [column] and [row] and the cel's tile
/// there, if it has one.
typedef GpuTileAsk = ({int column, int row, GpuTile? under});

/// What a landing made of a tile asked: what it is, and where it landed.
typedef GpuLanded = ({GpuChange change, GpuTile? tile});

/// [asks] as a landing's call takes them, and what it wrote read back.
List<GpuLanded> _landed(
  List<GpuTileAsk> asks,
  int Function(
    Arena arena,
    Pointer<Int32> asks,
    Pointer<Uint32> under,
    Pointer<Uint32> places,
    Pointer<Uint8> changes,
  )
  call,
) => using((arena) {
  final count = asks.length;
  final (:coordinates, :under) = _asked(arena, asks);
  final places = arena<Uint32>(_held(count));
  final changes = arena<Uint8>(_held(count));
  final landed = call(arena, coordinates, under, places, changes);
  if (landed < 0) {
    throw GpuRefused(_lastError());
  }
  return [
    for (var at = 0; at < landed; at++)
      (
        change: GpuChange.values[changes[at]],
        tile: places[at] == _noTile
            ? null
            : (page: places[at] >> 16, slot: places[at] & 0xFFFF),
      ),
  ];
});

/// [asks] as a landing's call takes them, in [arena]'s: each one's
/// column and row, and the word of the cel's tile under it.
({Pointer<Int32> coordinates, Pointer<Uint32> under}) _asked(
  Arena arena,
  List<GpuTileAsk> asks,
) {
  final count = asks.length;
  final coordinates = arena<Int32>(_held(2 * count));
  final under = arena<Uint32>(_held(count));
  for (var at = 0; at < count; at++) {
    final (:column, :row, under: tile) = asks[at];
    coordinates[2 * at] = column;
    coordinates[2 * at + 1] = row;
    under[at] = tile == null ? _noTile : tile.page << 16 | tile.slot;
  }
  return (coordinates: coordinates, under: under);
}

/// A LANDING FINISHED AND YET TO LAND ([GpuStampLanding.finished],
/// [GpuStampLanding.finishedMask]): what each tile asked is beside the
/// one under it, and the tiles made, kept on the GPU till it is freed —
/// its maker's to land ([landOnItsWay]) and to free.
///
/// 🗣️opening-a-transform-box-holds-the-ui-over-half-a-second (브러시/렌더링
/// 2026-11-20): TWO STEPS, the slots taken at the second. A landing
/// compared gives a slot to the inked alone, and which are inked is the
/// GPU's word, told later; the pool's books are this isolate's, so they
/// are written here once it is told. ⛔Not every tile asked given a slot
/// ahead and the others let go once told: a box of tiles mostly the
/// same would take a page of the pool's for a moment, and a full pool
/// would let go of tiles to make room for slots nothing keeps.
final class GpuFinished {
  GpuFinished._(this._engine, this._finished, this.changes) {
    debugKept += 1;
  }

  /// How many are kept on the GPU, finished and not freed: a test's
  /// count of what a landing leaves behind it.
  static int debugKept = 0;

  final GpuEngine _engine;
  final Pointer<rust.Finished> _finished;

  /// What each tile asked is, in the order they were asked.
  final List<GpuChange> changes;

  /// How many of its tiles take a slot: the inked.
  int get inked => changes.where((one) => one == GpuChange.inked).length;

  /// Gives each inked tile from the [first] inked on a fresh slot of
  /// [cel] of [pool], and hands their putting there to the engine's
  /// thread, this isolate waiting for none of it: the places, in the
  /// inked's order — all, or the first few where [pool] is full at the
  /// next. [unput] is called where they were not put.
  List<GpuTile> landOnItsWay(
    GpuPool pool,
    int cel, {
    int first = 0,
    required void Function() unput,
  }) => using((arena) {
    final places = arena<Uint32>(_held(inked - first));
    final landed = _putsOnTheirWay.handing(
      unput,
      (number) => rust.finishedLandUnwaited(
        _finished,
        _engine._engine,
        _engine._its(pool)._pool,
        cel,
        first,
        places,
        _putsOnTheirWay.told,
        number,
      ),
    );
    return [
      for (var at = 0; at < landed; at++)
        (page: places[at] >> 16, slot: places[at] & 0xFFFF),
    ];
  });

  void free() {
    debugKept -= 1;
    rust.finishedFree(_finished);
  }

  /// The finishes on their way, each told by its number once the GPU has
  /// said what its tiles are — or that it failed —, what it finished
  /// written to [out] first.
  static final _told =
      _Told<
        ({
          Completer<GpuFinished> told,
          GpuEngine engine,
          Pointer<Pointer<rust.Finished>> out,
        })
      >((_, finish, finished) {
        final made = finish.out.value;
        malloc.free(finish.out);
        if (!finished) {
          finish.told.completeError(
            _toldRefused(finish.engine, 'a landing was not finished'),
          );
          return;
        }
        finish.told.complete(
          GpuFinished._(finish.engine, made, _changesOf(made)),
        );
      });

  static List<GpuChange> _changesOf(Pointer<rust.Finished> finished) =>
      using((arena) {
        final count = rust.finishedChanges(finished, nullptr);
        final changes = arena<Uint8>(_held(count));
        rust.finishedChanges(finished, changes);
        return [
          for (var at = 0; at < count; at++) GpuChange.values[changes[at]],
        ];
      });

  /// What [handOver] hands the engine's thread — given where to write
  /// what it finished, by what it is told and under what number; false
  /// where it handed nothing over —, finished: told on this isolate,
  /// which waits for none of it.
  static Future<GpuFinished> _of(
    GpuEngine engine,
    bool Function(
      Pointer<Pointer<rust.Finished>> out,
      Pointer<NativeFunction<Void Function(Uint64, Bool)>> told,
      int number,
    )
    handOver,
  ) {
    final told = Completer<GpuFinished>();
    final out = malloc<Pointer<rust.Finished>>()..value = nullptr;
    final handed = _told.handing(
      (told: told, engine: engine, out: out),
      (number) => handOver(out, _told.told, number) ? 1 : 0,
    );
    if (handed == 0) {
      malloc.free(out);
      throw GpuRefused(_lastError());
    }
    return told.future;
  }
}

/// The blur brush's kernels (rust/src/kernels/dab/blur.rs): one set for
/// every stroke — what a stroke cannot go without; the kernels a dab goes
/// by strips with are the engine's, compiled apart ([compilingStrips]).
final class GpuBlurs implements _OfAnEngine {
  /// Compiled on [engine], the caller waiting.
  factory GpuBlurs(GpuEngine engine) =>
      GpuBlurs._(engine, _made(rust.blursNew(engine._engine)));

  GpuBlurs._(this._engine, this._blurs);

  /// Compiled on [engine] off this isolate, which goes on meanwhile.
  static Future<GpuBlurs> opening(GpuEngine engine) async =>
      GpuBlurs._(engine, await _compiledOff(engine, _compiled));

  static Pointer<rust.Blurs> _compiled(Pointer<rust.Engine> on) =>
      _made(rust.blursNew(on));

  /// The kernels a dab goes by strips with compiled on [engine] off this
  /// isolate, the engine's to keep: a stroke goes a pass a dispatch — the
  /// same pixels, slower — till they are, and by strips from its next dabs
  /// (rust/src/kernels/dab/blur.rs, `Dispatches`).
  static Future<void> compilingStrips(GpuEngine engine) {
    final on = engine._engine.address;
    return Isolate.run(() => _stripsCompiled(on));
  }

  static void _stripsCompiled(int on) {
    if (!rust.blursCompileStrips(Pointer.fromAddress(on))) {
      throw GpuRefused(_lastError());
    }
  }

  static Pointer<rust.Blurs> _made(Pointer<rust.Blurs> blurs) {
    if (blurs == nullptr) {
      throw GpuRefused(_lastError());
    }
    return blurs;
  }

  @override
  final GpuEngine _engine;
  final Pointer<rust.Blurs> _blurs;

  /// Test seam: whether its next stroke goes by strips — the engine has
  /// their kernels ([compilingStrips]).
  bool get debugGoesByStrips => rust.blursByStrips(_blurs);

  /// The bytes it keeps between its strokes.
  int get bytes => rust.blursBytes(_blurs);

  /// Lets go of what it keeps between its strokes.
  void letGo() => rust.blursLetGo(_blurs);

  /// Frees the kernels; before their engine is closed.
  void free() => rust.blursFree(_blurs);
}

/// A blur brush's dab and the box radius it blurs at
/// (`BrushBlurPicture.blurRadiusOf`).
typedef GpuRub = ({GpuDab dab, int radius});

/// [dabs] as the kernel reads them, held by [arena] — a table two share at
/// one address.
Pointer<rust.DabSpec> _specsOf(Arena arena, List<GpuDab> dabs) {
  final tables = Map<Float64List, Pointer<Double>>.identity();
  Pointer<Double> table(Float64List values) =>
      tables.putIfAbsent(values, () => _doubles(arena, values));
  final specs = arena<rust.DabSpec>(_held(dabs.length));
  for (var at = 0; at < dabs.length; at++) {
    final dab = dabs[at];
    final round = dab.round;
    specs[at]
      ..centreX = dab.centreX
      ..centreY = dab.centreY
      ..opacity = dab.opacity
      ..flow = dab.flow
      ..contrast = dab.contrast
      ..radius = dab.radius
      ..cos = dab.cos
      ..sin = dab.sin
      ..roundness = dab.roundness
      ..scale = round?.scale ?? 0
      ..reach = round?.reach ?? 0
      ..inner = round?.inner ?? 0
      ..density = dab.density ?? 0
      ..texture = dab.tip?._texture ?? nullptr
      ..coverage = round == null ? nullptr : table(round.coverage)
      ..pile = round == null ? nullptr : table(round.pile)
      ..evening = dab.evening == null ? nullptr : table(dab.evening!)
      ..entries = round?.coverage.length ?? 0
      ..rowLength = round?.rowLength ?? 0
      ..flags =
          (dab.threshold ? 1 : 0) |
          (dab.edgeHeld ? 2 : 0) |
          (dab.erase ? 4 : 0) |
          (dab.second ? 8 : 0) |
          (dab.density != null ? 16 : 0)
      ..left = dab.left
      ..top = dab.top
      ..right = dab.right
      ..bottom = dab.bottom
      ..colour = dab.colour
      ..mix = dab.mixStep ?? _noStep;
  }
  return specs;
}

/// `DabSpec::mix` of a dab that lays its own colour (abi.rs `NO_STEP`).
const _noStep = 0xFFFFFFFF;

/// [steps] as the stroke reads them, held by [arena].
Pointer<rust.StepSpec> _stepsOf(Arena arena, List<GpuMixStep> steps) {
  final specs = arena<rust.StepSpec>(_held(steps.length));
  for (var at = 0; at < steps.length; at++) {
    final step = steps[at];
    specs[at]
      ..centreX = step.centreX
      ..centreY = step.centreY
      ..radius = step.radius
      ..refill = step.refill
      ..laid = step.laid
      ..density = step.density
      ..take = step.take
      ..share = step.share
      ..pick = step.pick
      ..colour = step.colour
      ..dry = step.dry ? 1 : 0;
  }
  return specs;
}

/// A stroke's tiles on the GPU and what it makes of a cel
/// (rust/src/kernels/dab/stroke.rs).
class GpuStroke {
  /// A stroke of no tiles on [engine], its kernels compiled.
  factory GpuStroke(GpuEngine engine) =>
      GpuStroke._(engine, _compiled(engine._engine));

  /// Compiled on [engine] off this isolate, which goes on meanwhile.
  static Future<GpuStroke> opening(GpuEngine engine) async =>
      GpuStroke._(engine, await _compiledOff(engine, _compiled));

  static Pointer<rust.Stroke> _compiled(Pointer<rust.Engine> on) {
    final stroke = rust.strokeNew(on);
    if (stroke == nullptr) {
      throw GpuRefused(_lastError());
    }
    return stroke;
  }

  GpuStroke._(this._engine, this._stroke);

  final GpuEngine _engine;
  final Pointer<rust.Stroke> _stroke;

  /// The engine its pages are made on.
  GpuEngine get engine => _engine;

  /// The bytes of the pages made.
  int get bytes => rust.strokeBytes(_stroke);

  /// Piles [dabs], in their order, over [paper] — at [paperScale] px a
  /// texel, 高さ where [paperHeight] — with a second tip shown by
  /// [secondMode] at [secondDensity] where the stroke has one. Hands the
  /// work to the engine's thread, waiting for none of it
  /// (rust/src/kernels/dab/abi.rs, `gpu_engine_stroke_pile`, has why): a
  /// pile that fails is told by what reads the stroke next — [land],
  /// [landOnItsWay], [mixed].
  ///
  /// A mixing brush's [mixing] runs first — its steps over the cel, in
  /// their order, the stroke's reservoir carried from the pile before —
  /// and each dab that names a step ([GpuDab.mixStep]) lays the colour
  /// that step resolved ([mixed] reads them back).
  void pile(
    List<GpuDab> dabs, {
    GpuDabTexture? paper,
    double paperScale = 1,
    bool paperHeight = false,
    int? secondMode,
    double secondDensity = 1,
    GpuMixing? mixing,
  }) => using((arena) {
    final ground = mixing == null ? null : _groundOf(arena, mixing);
    final composite = mixing?.composite;
    final pool = mixing?.pool;
    rust.strokePile(
      _stroke,
      _engine._engine,
      _specsOf(arena, dabs),
      dabs.length,
      paper?._texture ?? nullptr,
      paperScale,
      paperHeight,
      secondMode ?? -1,
      secondDensity,
      ground?.steps ?? nullptr,
      mixing?.steps.length ?? 0,
      mixing?.first ?? 0,
      composite == null ? nullptr : _engine._its(composite)._composite,
      pool == null ? nullptr : _engine._its(pool)._pool,
      ground?.coordinates ?? nullptr,
      ground?.under ?? nullptr,
      ground?.count ?? 0,
    );
  });

  /// [mixing]'s steps as the pile hands them over, each ground tile they
  /// read — reckoned here of the steps alone (rust/src/kernels/dab/abi.rs,
  /// `gpu_engine_mix_ground`), no turn of the engine's waited for — and
  /// the cel's tile under each.
  ({
    Pointer<rust.StepSpec> steps,
    Pointer<Int32> coordinates,
    Pointer<Uint32> under,
    int count,
  })
  _groundOf(Arena arena, GpuMixing mixing) {
    final steps = mixing.steps;
    final specs = _stepsOf(arena, steps);
    // A step reads 64 tiles at most.
    final coordinates = arena<Int32>(_held(128 * steps.length));
    final count = steps.isEmpty
        ? 0
        : rust.mixGround(specs, steps.length, coordinates);
    final found = mixing.under([
      for (var at = 0; at < count; at++)
        (column: coordinates[2 * at], row: coordinates[2 * at + 1]),
    ]);
    final under = arena<Uint32>(_held(count));
    for (var at = 0; at < count; at++) {
      final tile = found[at];
      under[at] = tile == null ? _noTile : tile.page << 16 | tile.slot;
    }
    return (
      steps: specs,
      coordinates: coordinates,
      under: under,
      count: count,
    );
  }

  /// The colour each of the stroke's first [count] mixing steps laid,
  /// ARGB — read back: the caller waits for all the GPU was handed.
  List<int> mixed(int count) => using((arena) {
    final out = arena<Uint32>(_held(count));
    if (!rust.strokeMixed(_stroke, _engine._engine, out, count)) {
      throw GpuRefused(_lastError());
    }
    return List.of(out.asTypedList(count));
  });

  /// Rubs [rubs], in their order, into the blur brush's picture on this
  /// stroke, over [paper] as [pile]'s: the tiles their blur reads and the
  /// stroke has not read yet are made first of the cel's, which [under]
  /// tells of — asked of every tile the blur reads, reckoned here of the
  /// rubs alone, in the order asked, null where the cel has none. Hands the
  /// work to the engine's thread, waiting for none of it
  /// (rust/src/kernels/dab/abi.rs, `gpu_engine_stroke_rub`, has why): a rub
  /// that fails is told by what reads the stroke next — [landBlur],
  /// [landBlurOnItsWay].
  void rub(
    GpuBlurs blurs,
    GpuComposite composite,
    GpuPool pool,
    List<GpuRub> rubs, {
    required List<GpuTile?> Function(List<({int column, int row})> read)
    under,
    GpuDabTexture? paper,
    double paperScale = 1,
    bool paperHeight = false,
  }) => using((arena) {
    final specs = _specsOf(arena, [for (final rub in rubs) rub.dab]);
    final radii = arena<Uint32>(_held(rubs.length));
    radii.asTypedList(rubs.length).setAll(0, [
      for (final rub in rubs) rub.radius,
    ]);
    final (:coordinates, :count) = _rubGround(arena, specs, radii, rubs.length);
    final found = under([
      for (var at = 0; at < count; at++)
        (column: coordinates[2 * at], row: coordinates[2 * at + 1]),
    ]);
    final words = arena<Uint32>(_held(count));
    for (var at = 0; at < count; at++) {
      final tile = found[at];
      words[at] = tile == null ? _noTile : tile.page << 16 | tile.slot;
    }
    rust.strokeRub(
      _stroke,
      _engine._engine,
      _engine._its(blurs)._blurs,
      _engine._its(composite)._composite,
      _engine._its(pool)._pool,
      coordinates,
      words,
      count,
      specs,
      radii,
      rubs.length,
      paper?._texture ?? nullptr,
      paperScale,
      paperHeight,
    );
  });

  /// Every tile the blur of the [count] rubs [specs], at [radii], reads,
  /// as columns and rows — reckoned here of the rubs alone
  /// (rust/src/kernels/dab/abi.rs, `gpu_engine_rub_ground`), no turn of the
  /// engine's waited for — and how many.
  static ({Pointer<Int32> coordinates, int count}) _rubGround(
    Arena arena,
    Pointer<rust.DabSpec> specs,
    Pointer<Uint32> radii,
    int count,
  ) {
    var room = 64;
    while (true) {
      final coordinates = arena<Int32>(2 * room);
      final read = _checked(
        rust.rubGround(specs, radii, count, coordinates, room),
      );
      if (read <= room) {
        return (coordinates: coordinates, count: read);
      }
      room = read;
    }
  }

  /// The picture [rub] left, finished on the tiles [asks]: each pixel of
  /// the cel moved toward it by [opacity] (65535 whole), under [mask] if
  /// any, each result in a fresh slot of [cel] of [pool] — and compared as
  /// [land]'s.
  List<GpuLanded> landBlur(
    GpuBlurs blurs,
    GpuComposite composite,
    GpuPool pool,
    int cel,
    List<GpuTileAsk> asks, {
    int opacity = 65535,
    GpuMask? mask,
    bool compared = false,
  }) => _landed(
    asks,
    (_, coordinates, under, places, changes) => rust.strokeLandBlur(
      _stroke,
      _engine._engine,
      _engine._its(blurs)._blurs,
      _engine._its(composite)._composite,
      _engine._its(pool)._pool,
      cel,
      coordinates,
      under,
      asks.length,
      opacity,
      mask == null ? nullptr : _engine._its(mask)._mask,
      compared,
      places,
      changes,
    ),
  );

  /// [landBlur] uncompared — each result [GpuChange.inked], in a fresh slot
  /// — with no wait for the engine's turn, as [landOnItsWay] lands a
  /// stroke: the slots are given here, and the picture finished in them on
  /// the engine's thread, behind its rubs (rust/src/kernels/dab/abi.rs,
  /// `gpu_engine_stroke_land_blur_unwaited`, has why). [unput] is called
  /// where its picture was not put.
  List<GpuLanded> landBlurOnItsWay(
    GpuBlurs blurs,
    GpuComposite composite,
    GpuPool pool,
    int cel,
    List<GpuTileAsk> asks, {
    int opacity = 65535,
    GpuMask? mask,
    required void Function() unput,
  }) => _landed(
    asks,
    (_, coordinates, under, places, changes) => _putsOnTheirWay.handing(
      unput,
      (number) => rust.strokeLandBlurUnwaited(
        _stroke,
        _engine._engine,
        _engine._its(blurs)._blurs,
        _engine._its(composite)._composite,
        _engine._its(pool)._pool,
        cel,
        coordinates,
        under,
        asks.length,
        opacity,
        mask == null ? nullptr : _engine._its(mask)._mask,
        places,
        changes,
        _putsOnTheirWay.told,
        number,
      ),
    ),
  );

  /// Lays the stroke on the tiles [asks] at [opacity] (65535 whole) in
  /// [mode], under [mask] if any, each result in a fresh slot of [cel] of
  /// [pool]. Where [compared], a result compares with the tile under it
  /// first — waiting for the GPU — and takes no slot where it is that tile
  /// or has no ink left. As many of [asks], the first, as [pool] has room
  /// for.
  List<GpuLanded> land(
    GpuComposite composite,
    GpuPool pool,
    int cel,
    List<GpuTileAsk> asks, {
    int opacity = 65535,
    required int mode,
    GpuMask? mask,
    bool compared = false,
  }) => _landed(
    asks,
    (_, coordinates, under, places, changes) => rust.strokeLand(
      _stroke,
      _engine._engine,
      _engine._its(composite)._composite,
      _engine._its(pool)._pool,
      cel,
      coordinates,
      under,
      asks.length,
      opacity,
      mode,
      mask == null ? nullptr : _engine._its(mask)._mask,
      compared,
      places,
      changes,
    ),
  );

  /// [land] uncompared — each result [GpuChange.inked], in a fresh slot —
  /// with no wait for the engine's turn: the slots are given here, and the
  /// stroke laid in them on the engine's thread, behind its pile
  /// (rust/src/kernels/dab/abi.rs, `gpu_engine_stroke_land_unwaited`, has
  /// why): a stroke on its way, whose frame waits for nothing. [unput] is
  /// called where its picture was not put.
  List<GpuLanded> landOnItsWay(
    GpuComposite composite,
    GpuPool pool,
    int cel,
    List<GpuTileAsk> asks, {
    int opacity = 65535,
    required int mode,
    GpuMask? mask,
    required void Function() unput,
  }) => _landed(
    asks,
    (_, coordinates, under, places, changes) => _putsOnTheirWay.handing(
      unput,
      (number) => rust.strokeLandUnwaited(
        _stroke,
        _engine._engine,
        _engine._its(composite)._composite,
        _engine._its(pool)._pool,
        cel,
        coordinates,
        under,
        asks.length,
        opacity,
        mode,
        mask == null ? nullptr : _engine._its(mask)._mask,
        places,
        changes,
        _putsOnTheirWay.told,
        number,
      ),
    ),
  );

  /// Clears what the stroke wrote and lets its tiles go; the pages stay.
  void clear() => rust.strokeClear(_stroke, _engine._engine);

  /// Frees the stroke; before its engine is closed.
  void free() => rust.strokeFree(_stroke);
}

/// A stamp's picture on the GPU, straight RGBA8: a selection moved lands
/// the same one at each step of the drag, its upload once. Goes with the
/// object.
final class GpuStampPicture implements Finalizable, _OfAnEngine {
  /// [rgba], [width] × [height] row after row.
  factory GpuStampPicture(
    GpuEngine engine,
    Uint8List rgba,
    int width,
    int height,
  ) {
    final made = using((arena) {
      final bytes = _bytes(arena, rgba);
      return rust.stampPictureNew(engine._engine, bytes, width, height);
    });
    return GpuStampPicture._kept(engine, made, width, height);
  }

  /// [made] on [engine], [width] × [height]: let go of with the object.
  factory GpuStampPicture._kept(
    GpuEngine engine,
    Pointer<rust.StampPicture> made,
    int width,
    int height,
  ) {
    if (made == nullptr) {
      throw GpuRefused(_lastError());
    }
    final picture = GpuStampPicture._(engine, made, width, height);
    _freed.attach(picture, made.cast(), externalSize: width * height * 4);
    return picture;
  }

  GpuStampPicture._(this._engine, this._picture, this.width, this.height);

  static final NativeFinalizer _freed = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<rust.StampPicture>)>>(
      rust.stampPictureFree,
    ).cast(),
  );

  /// The bytes of every picture alive, for the memory census.
  static int get liveBytes => rust.stampPictureBytes();

  @override
  final GpuEngine _engine;
  final Pointer<rust.StampPicture> _picture;

  final int width;
  final int height;

  /// Its pixels, row after row, once the GPU has made them: what is asked
  /// of a picture whose bytes nothing here ever held
  /// ([GpuStampLanding.carried]'s). Waits for the GPU.
  Uint8List pixels() => _stampPixels(_engine._engine, _picture, _count);

  int get _count => width * height * 4;
}

/// The [bytes] of [picture] on [engine], once the GPU has made them.
Uint8List _stampPixels(
  Pointer<rust.Engine> engine,
  Pointer<rust.StampPicture> picture,
  int bytes,
) => using((arena) {
  final into = arena<Uint8>(_held(bytes));
  if (!rust.stampPictureRead(engine, picture, into)) {
    throw GpuReadFailed(_lastError());
  }
  return Uint8List.fromList(into.asTypedList(bytes));
});

/// A [GpuStampLanding] as any isolate asks it: plain numbers, its engine's
/// address and its kernels', so a picture's whole carriage crosses to a
/// worker — handed up, carried and read there, every wait for the engine's
/// turn and for the GPU that worker's, not the asker's.
///
/// 🗣️tip-coverage-is-a-second-r1-Q1 (유저 2026-11-12: 「미리 만들어 둔다 —
/// 엔진이 열리면 기다리지 않고 받아 둔다」). ↩️Only the read crossed: the
/// asker handed the picture up and carried it itself, each a turn of the
/// engine's thread it waited for — 🔬behind the band's fill, 77 ms of
/// hands-up and 15 of carriage over the tips' thumbnails a launch makes,
/// as the first stroke went (S5_BA cut 352, main PC, 2026-11-18, board
/// a-tip-thumbnail-waits-for-the-engines-turn).
final class GpuStampCarrier {
  const GpuStampCarrier._(this._engine, this._landing);

  final int _engine;
  final int _landing;

  /// [rgba] — [width] × [height], straight — carried as
  /// [GpuStampLanding.carried] carries a picture of it over a whole output
  /// [columns] × [rows], read. ⚠️Waits for the engine and the GPU.
  Uint8List carriedPixels(
    Uint8List rgba,
    int width,
    int height, {
    required List<double> inverse,
    required double radiusFloor,
    required GpuSampling sampling,
    required int columns,
    required int rows,
  }) {
    if (inverse.length != 9) {
      throw ArgumentError('an inverse of ${inverse.length}, not 9');
    }
    final engine = Pointer<rust.Engine>.fromAddress(_engine);
    final source = using(
      (arena) =>
          rust.stampPictureNew(engine, _bytes(arena, rgba), width, height),
    );
    if (source == nullptr) {
      throw GpuRefused(_lastError());
    }
    try {
      final carried = using(
        (arena) => rust.stampPictureCarried(
          Pointer.fromAddress(_landing),
          engine,
          source,
          _doubles(arena, inverse),
          radiusFloor,
          sampling.id,
          columns,
          rows,
          0,
          0,
          columns,
          rows,
        ),
      );
      if (carried == nullptr) {
        throw GpuRefused(_lastError());
      }
      try {
        return _stampPixels(engine, carried, columns * rows * 4);
      } finally {
        rust.stampPictureFree(carried);
      }
    } finally {
      rust.stampPictureFree(source);
    }
  }
}

/// What lands a stamp on a cel (rust/src/kernels/dab/stamp.rs).
class GpuStampLanding {
  /// Its kernels compiled on [engine].
  factory GpuStampLanding(GpuEngine engine) =>
      GpuStampLanding._(engine, _compiled(engine._engine));

  /// Compiled on [engine] off this isolate, which goes on meanwhile.
  static Future<GpuStampLanding> opening(GpuEngine engine) async =>
      GpuStampLanding._(engine, await _compiledOff(engine, _compiled));

  static Pointer<rust.StampLanding> _compiled(Pointer<rust.Engine> on) {
    final landing = rust.stampLandingNew(on);
    if (landing == nullptr) {
      throw GpuRefused(_lastError());
    }
    return landing;
  }

  GpuStampLanding._(this._engine, this._landing);

  final GpuEngine _engine;
  final Pointer<rust.StampLanding> _landing;

  /// The engine it lands and carries on.
  GpuEngine get engine => _engine;

  /// It as any isolate asks it ([GpuStampCarrier]) — for as long as it and
  /// its engine are alive: what carries on a worker holds it till that is
  /// done.
  GpuStampCarrier get carrier =>
      GpuStampCarrier._(_engine._engine.address, _landing.address);

  /// [picture] carried through [inverse] — a point of the output to
  /// [picture]'s, the nine of the app's `ResampleTransform` row after row,
  /// the homogeneous row last — over an output [width] × [height], by R1
  /// with [radiusFloor], sampled as [sampling] says: a new picture of the
  /// whole output, or of its [window] — (left, top, width, height), what of
  /// it shows — whose pixels are the whole's there; nothing where the map
  /// lands nothing. The GPU makes it without this waiting; what lands it,
  /// or reads it ([GpuStampPicture.pixels]), waits.
  GpuStampPicture carried(
    GpuStampPicture picture, {
    required List<double> inverse,
    required double radiusFloor,
    required GpuSampling sampling,
    required int width,
    required int height,
    (int, int, int, int)? window,
  }) {
    if (inverse.length != 9) {
      throw ArgumentError('an inverse of ${inverse.length}, not 9');
    }
    final (left, top, columns, rows) = window ?? (0, 0, width, height);
    final made = using(
      (arena) => rust.stampPictureCarried(
        _landing,
        _engine._engine,
        _engine._its(picture)._picture,
        _doubles(arena, inverse),
        radiusFloor,
        sampling.id,
        width,
        height,
        left,
        top,
        columns,
        rows,
      ),
    );
    return GpuStampPicture._kept(_engine, made, columns, rows);
  }

  /// [picture], its top-left pixel at [at] on the canvas, through a mesh of
  /// [columns] × [rows] cells whose corners rest at [source] and were
  /// dragged to [destination] — (columns + 1) · (rows + 1) points each, row
  /// after row, an x and a y apiece in canvas pixels — by R1 with
  /// [radiusFloor], sampled as [sampling] says: a new picture of [window]
  /// of the canvas — (left, top, width, height) — each pixel by the map of
  /// the triangle that paints it, nothing where none does (R3). The GPU
  /// makes it without this waiting; what lands it, or reads it, waits.
  GpuStampPicture meshed(
    GpuStampPicture picture, {
    required (double, double) at,
    required int columns,
    required int rows,
    required List<double> source,
    required List<double> destination,
    required double radiusFloor,
    required GpuSampling sampling,
    required (int, int, int, int) window,
  }) {
    final coordinates = 2 * (columns + 1) * (rows + 1);
    if (source.length != coordinates || destination.length != coordinates) {
      throw ArgumentError(
        'a ${columns}x$rows mesh is $coordinates coordinates a grid, not '
        '${source.length} and ${destination.length}',
      );
    }
    final (left, top, width, height) = window;
    final made = using(
      (arena) => rust.stampPictureMeshed(
        _landing,
        _engine._engine,
        _engine._its(picture)._picture,
        at.$1,
        at.$2,
        columns,
        rows,
        _doubles(arena, source),
        _doubles(arena, destination),
        radiusFloor,
        sampling.id,
        left,
        top,
        width,
        height,
      ),
    );
    return GpuStampPicture._kept(_engine, made, width, height);
  }

  /// Lays [picture], its top-left pixel at ([left], [top]), what of it lies
  /// [within] the canvas's (left, top, right, bottom), on the tiles [asks]
  /// at [opacity] (65535 whole) in [mode], under [mask] if any. Each result
  /// compares with the tile under it, and takes a fresh slot of [cel] of
  /// [pool] where it is neither that tile nor empty. As many of [asks], the
  /// first, as [pool] has room for.
  List<GpuLanded> land(
    GpuComposite composite,
    GpuPool pool,
    int cel,
    GpuStampPicture picture, {
    required int left,
    required int top,
    required (int, int, int, int) within,
    required List<GpuTileAsk> asks,
    int opacity = 65535,
    required int mode,
    GpuMask? mask,
  }) => _landed(
    asks,
    (arena, coordinates, under, places, changes) {
      final (l, t, r, b) = within;
      final box = arena<Int32>(4);
      box[0] = l;
      box[1] = t;
      box[2] = r;
      box[3] = b;
      return rust.stampLand(
        _landing,
        _engine._engine,
        _engine._its(composite)._composite,
        _engine._its(pool)._pool,
        cel,
        _engine._its(picture)._picture,
        left,
        top,
        box,
        coordinates,
        under,
        asks.length,
        opacity,
        mode,
        mask == null ? nullptr : _engine._its(mask)._mask,
        places,
        changes,
      );
    },
  );

  /// Lays [coverage] under [paint] on the tiles [asks], as [land] lays a
  /// picture: a pixel it covers at all wholly where [whole], else its byte
  /// for an alpha, at [opacity] in [mode], under [mask] if any. A fill's
  /// pieces in their colour or under their gradient, and a selection's
  /// erase: the selection's own mask, laid by the eraser.
  List<GpuLanded> landMask(
    GpuComposite composite,
    GpuPool pool,
    int cel,
    GpuMask coverage, {
    required GpuPaint paint,
    required bool whole,
    required List<GpuTileAsk> asks,
    int opacity = 65535,
    required int mode,
    GpuMask? mask,
  }) => _landed(
    asks,
    (arena, coordinates, under, places, changes) => rust.stampLandMask(
      _landing,
      _engine._engine,
      _engine._its(composite)._composite,
      _engine._its(pool)._pool,
      cel,
      _engine._its(coverage)._mask,
      _doubles(arena, paint._numbers),
      whole,
      coordinates,
      under,
      asks.length,
      opacity,
      mode,
      mask == null ? nullptr : _engine._its(mask)._mask,
      places,
      changes,
    ),
  );

  /// [land] as far as it asks the GPU, with no wait and no slot taken:
  /// [picture] laid on the tiles [asks] — one at least — over the cel's
  /// as [pool] holds them now, handed to the engine's thread, and what
  /// each is beside the tile under it told once the GPU has said
  /// (rust/src/kernels/dab/abi.rs, `gpu_engine_stamp_finish_unwaited`,
  /// has why): the landing finished, its caller's to land
  /// ([GpuFinished.landOnItsWay]) and to free. Fails as [GpuRefused]
  /// where it was not finished.
  Future<GpuFinished> finished(
    GpuComposite composite,
    GpuPool pool,
    GpuStampPicture picture, {
    required int left,
    required int top,
    required (int, int, int, int) within,
    required List<GpuTileAsk> asks,
    int opacity = 65535,
    required int mode,
    GpuMask? mask,
  }) => GpuFinished._of(
    _engine,
    (out, told, number) => using((arena) {
      final (l, t, r, b) = within;
      final box = arena<Int32>(4);
      box[0] = l;
      box[1] = t;
      box[2] = r;
      box[3] = b;
      final (:coordinates, :under) = _asked(arena, asks);
      rust.stampFinishUnwaited(
        _landing,
        _engine._engine,
        _engine._its(composite)._composite,
        _engine._its(pool)._pool,
        _engine._its(picture)._picture,
        left,
        top,
        box,
        coordinates,
        under,
        asks.length,
        opacity,
        mode,
        mask == null ? nullptr : _engine._its(mask)._mask,
        out,
        told,
        number,
      );
      return true;
    }),
  );

  /// [finished] of [coverage] under [paint], as [landMask] lays one: a
  /// selection's erase, its own mask laid by the eraser.
  Future<GpuFinished> finishedMask(
    GpuComposite composite,
    GpuPool pool,
    GpuMask coverage, {
    required GpuPaint paint,
    required bool whole,
    required List<GpuTileAsk> asks,
    int opacity = 65535,
    required int mode,
    GpuMask? mask,
  }) => GpuFinished._of(
    _engine,
    (out, told, number) => using((arena) {
      final (:coordinates, :under) = _asked(arena, asks);
      return rust.stampFinishMaskUnwaited(
        _landing,
        _engine._engine,
        _engine._its(composite)._composite,
        _engine._its(pool)._pool,
        _engine._its(coverage)._mask,
        _doubles(arena, paint._numbers),
        whole,
        coordinates,
        under,
        asks.length,
        opacity,
        mode,
        mask == null ? nullptr : _engine._its(mask)._mask,
        out,
        told,
        number,
      );
    }),
  );

  /// Frees it; before its engine is closed.
  void free() => rust.stampLandingFree(_landing);
}

/// The blends the executor has beside the app's table of 1 to 27 — the C
/// engine's stroke ids, which blend.wgsl follows (`BLEND_NORMAL` and on):
/// the app names those itself (brush_stroke_blend.dart), these only the
/// engine has.
abstract final class GpuBlend {
  /// Source over.
  static const int normal = 28;

  /// The eraser: what is there loses the alpha of what lands, its colour
  /// kept — a stroke's.
  static const int erase = 29;

  /// Flutter's `BlendMode.plus`: an adjustment's crossfade adds its second
  /// pass onto its first by it.
  static const int plus = 30;
}

/// How a row's pose samples its pixels: R1's modes, by the engine's ids.
enum GpuSampling {
  /// The tent mean — a reduction's.
  blend(0),

  /// The area vote: the one colour covering most of the preimage.
  pick(1),

  /// The one source pixel where the pixel's centre lands.
  nearest(3);

  const GpuSampling(this.id);

  final int id;
}

/// The channel a blur map is read through, by the engine's ids.
enum GpuMapChannel {
  red(0),
  green(1),
  blue(2),
  alpha(3),
  luminance(4);

  const GpuMapChannel(this.id);

  final int id;
}

/// One way of fx Gaussian Blur: its sigma in pixels, and how many pixels
/// either side of a pixel its weights reach — none where the way is not
/// blurred (rust/src/kernels/effects/blur/gaussian.rs).
typedef GpuGaussianWay = ({double sigma, int reach});

/// One pass of a blur along a way — the app's `LineBoxPass` with its maps
/// worked out: `taps` taps, the i-th at centre + M_i·(at − centre) +
/// step·(i − (taps − 1)/2), M_i = each^i · first, a map its columns as the
/// app writes them (rust/src/kernels/effects/blur/line.rs).
typedef GpuLinePass = ({
  int taps,
  (double, double) step,
  (double, double) centre,
  List<double> first,
  List<double> each,
});

/// fx Camera Lens Blur's settings — the app's `IrisGatherPass` but its map
/// (rust/src/kernels/effects/blur/lens.rs): an iris of `sides`, its
/// `roundness` (0 to 1) and `aspect`, its rotation's, half a side's and a
/// whole side's turns as cosine and sine; the `radius` and the `fringe` (0
/// to 500); the light's `gain`, `threshold` and `saturation`, `linear` or
/// not; and the `paper` whose edge pixels it repeats past it, if any.
typedef GpuLens = ({
  int sides,
  double roundness,
  double aspect,
  (double, double) turn,
  (double, double) halfSide,
  (double, double) side,
  double radius,
  double fringe,
  double gain,
  double threshold,
  double saturation,
  bool linear,
  (int, int, int, int)? paper,
});

/// A plan the executor runs, built step by step, bottom to top
/// (rust/src/kernels/composite/abi.rs): tile sets of the pool, key chains,
/// colour matrices, effect chains and the blur maps their lens blurs read,
/// and rows, folders, clips and solid colours laying them. The executor
/// checks it where it runs.
class GpuPlan implements _OfAnEngine {
  /// A plan of nothing, for an executor of [engine]'s to run: what it
  /// names is that engine's ([_OfAnEngine]).
  GpuPlan(this._engine) : _plan = rust.planNew(_engine._engine);

  @override
  final GpuEngine _engine;
  final Pointer<rust.Planned> _plan;

  /// Adds the tile set of [columns] × [rows] canvas tiles whose top-left is
  /// column [x0], row [y0] — [tiles] row by row, null for one with nothing
  /// on it — and returns the index a row lays it by.
  int set(int x0, int y0, int columns, int rows, List<GpuTile?> tiles) =>
      using(
        (arena) => rust.planSet(
          _plan,
          x0,
          y0,
          columns,
          rows,
          _tileWords(arena, columns, rows, tiles),
        ),
      );

  /// Adds a key chain of no runs and returns the index a row or a chain's
  /// op keys by.
  int keys() => rust.planKeys(_plan);

  /// Adds to key chain [keys] a run of colour keys as the app's tables give
  /// one: for each channel's byte — [red], [green], [blue], 256 words each
  /// — which keys are within their tolerance of it, bit k for key k;
  /// [restores], the keys that give back instead of erasing; and [maps],
  /// each key's 256-byte alpha map, one after another.
  void keyRun(
    int keys, {
    required Uint32List red,
    required Uint32List green,
    required Uint32List blue,
    required int restores,
    required Uint8List maps,
  }) {
    if ([red, green, blue].any((table) => table.length != 256) ||
        maps.length % 256 != 0) {
      throw ArgumentError('tables of 256 words, maps of 256 bytes a key');
    }
    _checked(
      using((arena) {
        Pointer<Uint32> words(Uint32List table) =>
            arena<Uint32>(256)..asTypedList(256).setAll(0, table);
        final bytes = _bytes(arena, maps);
        return rust.planKeyRun(
          _plan,
          keys,
          words(red),
          words(green),
          words(blue),
          restores,
          bytes,
          maps.length ~/ 256,
        );
      }),
    );
  }

  /// Adds the colour matrix of [matrix] — `ColorFilter.matrix`'s twenty —
  /// and returns the index a row or a close runs it by.
  int matrix(List<double> matrix) => _checked(
    using((arena) => rust.planMatrix(_plan, _doubles(arena, _twenty(matrix)))),
  );

  /// Adds an effect chain of no ops over the canvas tiles of [columns] ×
  /// [rows] whose top-left is column [x0], row [y0] — a row's in its own
  /// space, a folder's on the canvas — and returns the index a row or a
  /// close runs it by.
  int chain(int x0, int y0, int columns, int rows) {
    _namesAChain = true;
    return rust.planChain(_plan, x0, y0, columns, rows);
  }

  /// Whether an effect chain was added ([chain]): what the executor runs
  /// its chain kernels for ([GpuComposite.chainsAreToCome]).
  bool get namesAChain => _namesAChain;
  bool _namesAChain = false;

  /// Adds to effect chain [chain] the colour matrix of [matrix] —
  /// `ColorFilter.matrix`'s twenty.
  void chainMatrix(int chain, List<double> matrix) => _checked(
    using(
      (arena) => rust.planChainMatrix(
        _plan,
        chain,
        _doubles(arena, _twenty(matrix)),
      ),
    ),
  );

  /// Adds to effect chain [chain] the runs of key chain [keys], every key
  /// against the alpha of what the op reads.
  void chainKeys(int chain, int keys) =>
      _checked(rust.planChainKeys(_plan, chain, keys));

  /// Holds what effect chain [chain] puts in [held] under [id], the number
  /// the app gives what the chain shows: a run whose hold under [id] keeps
  /// what it put over the chain's tiles lays that, and does not run it.
  void chainHeld(int chain, GpuHeldChains held, int id) => _checked(
    rust.planChainHeld(_plan, chain, _engine._its(held)._held, id),
  );

  /// Adds to effect chain [chain] a read of what the ops before it put:
  /// the picture a plug-in's step runs over, kept on the device in [read]
  /// once this plan has run — with [rows], this plan's tile sets ([set])
  /// of the rows its layer values name, by slot, each kept as it is stored
  /// over the chain's tiles. What it put goes on to the ops after it as it
  /// is.
  void chainRead(
    int chain,
    GpuChainRead read, {
    List<int> rows = const [],
  }) => _checked(
    using((arena) {
      final sets = arena<Uint32>(_held(rows.length))
        ..asTypedList(rows.length).setAll(0, rows);
      return rust.planChainRead(
        _plan,
        chain,
        _engine._its(read)._read,
        sets,
        rows.length,
      );
    }),
  );

  /// Adds to effect chain [chain] what a plug-in made — this plan's tile
  /// set [made] ([set]), its tiles where the run landed them in the pool
  /// ([GpuPluginMade.land]) — in place of what the ops before it put:
  /// nothing past its tiles.
  ///
  /// 🚨★ONE MAKING, HOWEVER MANY PLANS (ink-trails-further-on-intel-since-
  /// the-screen-waits-for-the-gpu, 관제 2026-11-13 「한 번 만들고 계획마다
  /// 이름만」): a frame is planned again at each write a pen makes, and the
  /// put took the plug-in's bytes each time — copied twice a plan, 25–40 ms
  /// of a write's 33 planned on the Surface Pro 11. Its tiles stay in the
  /// pool: a plan names them.
  void chainPut(int chain, int made) =>
      _checked(rust.planChainPut(_plan, chain, made));

  /// Adds to effect chain [chain] fx Gaussian Blur, the Gaussian itself a
  /// way a pass, [across] and [down]: reading [picture] — past it nothing,
  /// or its nearest pixel where it [repeats] (Repeat Edge Pixels) — and
  /// putting [puts], nothing outside it; both inside the chain's tiles.
  void chainGaussian(
    int chain, {
    required GpuGaussianWay across,
    required GpuGaussianWay down,
    required (int, int, int, int) picture,
    bool repeats = false,
    required (int, int, int, int) puts,
  }) => _checked(
    using((arena) {
      final reaches = arena<Uint32>(2)
        ..[0] = across.reach
        ..[1] = down.reach;
      return rust.planChainGaussian(
        _plan,
        chain,
        _doubles(arena, [across.sigma, down.sigma]),
        reaches,
        _rect(arena, picture),
        repeats ? 1 : 0,
        _rect(arena, puts),
      );
    }),
  );

  /// Adds to effect chain [chain] fx Directional or Radial Blur's [passes]
  /// over [plate], inside the chain's tiles.
  void chainLine(
    int chain,
    (int, int, int, int) plate,
    List<GpuLinePass> passes,
  ) {
    if (passes.any((pass) => pass.first.length != 4 || pass.each.length != 4)) {
      throw ArgumentError('maps of four, column by column');
    }
    _checked(
      using((arena) {
        final taps = arena<Uint32>(_held(passes.length));
        for (var at = 0; at < passes.length; at++) {
          taps[at] = passes[at].taps;
        }
        final maps = _doubles(arena, [
          for (final pass in passes) ...[
            pass.step.$1,
            pass.step.$2,
            pass.centre.$1,
            pass.centre.$2,
            ...pass.first,
            ...pass.each,
          ],
        ]);
        return rust.planChainLine(
          _plan,
          chain,
          _rect(arena, plate),
          taps,
          maps,
          passes.length,
        );
      }),
    );
  }

  /// Adds to effect chain [chain] fx Camera Lens Blur over [picture] by
  /// [lens], reading blur map [map] if any.
  void chainLens(
    int chain,
    (int, int, int, int) picture,
    GpuLens lens, {
    int? map,
  }) => _checked(
    using(
      (arena) => rust.planChainLens(
        _plan,
        chain,
        _rect(arena, picture),
        lens.sides,
        _doubles(arena, [
          lens.roundness,
          lens.aspect,
          lens.turn.$1,
          lens.turn.$2,
          lens.halfSide.$1,
          lens.halfSide.$2,
          lens.side.$1,
          lens.side.$2,
          lens.radius,
          lens.fringe,
          lens.gain,
          lens.threshold,
          lens.saturation,
        ]),
        lens.linear,
        _rectOrNull(arena, lens.paper),
        map ?? -1,
      ),
    ),
  );

  /// Adds a blur map read from the tiles [tiles] holds — over the blur's
  /// own rectangle, as a run over its tiles put them — through [channel],
  /// in focus at [focal] (0 to 255) and inverted where [inverts]; returns
  /// the index a lens blur reads it by. The plan keeps the tiles past
  /// [tiles]' own free.
  int mapLaid(
    GpuComposited tiles, {
    required GpuMapChannel channel,
    required double focal,
    bool inverts = false,
  }) => _checked(
    rust.planMapLaid(
      _plan,
      _engine._its(tiles)._composited,
      channel.id,
      focal,
      inverts,
    ),
  );

  /// How many steps the plan has: where the steps a blur map is drawn
  /// from begin ([mapDrawn]).
  int get steps => rust.planSteps(_plan);

  /// The tiles a screen makes of the plan laid afresh on [pool]'s tiles
  /// over the pixels [extent] — [left, top, right, bottom) —: of those it
  /// lays anything on, each the engine's pictures keep none for yet —
  /// what the picture will weigh in tiles ([GpuScreen.compose],
  /// [GpuScreen.bytes]). One tile for the same input: a frame's paper is
  /// one, and what a kept picture of its cut was made of is none.
  ///
  /// 🚨WEIGHED ON THE ENGINE'S THREAD, IN ITS TURN (F-610, 2026-11-19):
  /// this isolate waits for none of it — the pictures' books are that
  /// thread's to wait for —, and behind the composes handed over before
  /// it, it is weighed against their pictures as kept: a cut's second
  /// against its first, on its way still as this is asked. ↩️Counted on
  /// this isolate till then, every tile the plan lays on: several times
  /// what a picture weighs once a tile is kept once (rust/src/kernels/
  /// composite/kept.rs, `Kept::tiles_made`).
  ///
  /// The plan is read as it is weighed, and its answer off it: [free]d
  /// meanwhile, it is let go of once that has come.
  Future<int> tilesMade(GpuPool pool, (int, int, int, int) extent) {
    final weighed = Completer<int>();
    using(
      (arena) => rust.planWeigh(
        _plan,
        _engine._engine,
        _engine._its(pool)._pool,
        _rect(arena, extent),
        _weighs.told,
        _weighs.kept((weighed: weighed, plan: this)),
      ),
    );
    _weighing += 1;
    return weighed.future;
  }

  /// The weighs on their way ([tilesMade]), and how the engine's thread
  /// tells this isolate one has been weighed: its plan reads the answer
  /// off itself ([_weighed]).
  static final _weighs = _Told<({Completer<int> weighed, GpuPlan plan})>(
    (_, asked, told) => asked.plan._weighed(asked.weighed, told: told),
  );

  /// A weigh of this plan has run ([tilesMade]): [weighed] answered with
  /// the tiles it counted where it was [told] so, with a refusal where it
  /// was not — and the plan let go of where it was [free]d meanwhile and
  /// this was the last on its way.
  void _weighed(Completer<int> weighed, {required bool told}) {
    final tiles = rust.planWeighed(_plan);
    _weighing -= 1;
    if (_freed && _weighing == 0) {
      rust.planFree(_plan);
    }
    if (told) {
      weighed.complete(tiles);
    } else {
      weighed.completeError(
        GpuRefused('a plan is weighed over pixels past the grid'),
      );
    }
  }

  /// How many weighs of it are on their way ([tilesMade]).
  int _weighing = 0;

  /// Whether it was [free]d while one was.
  bool _freed = false;

  /// Takes the plan's steps from step [first] on as the steps a blur map is
  /// drawn from — drawn alone over the blur's rectangle, as they show by
  /// themselves —, read as [mapLaid]'s; returns the index a lens blur
  /// reads it by.
  int mapDrawn(
    int first, {
    required GpuMapChannel channel,
    required double focal,
    bool inverts = false,
  }) => _checked(rust.planMapDrawn(_plan, first, channel.id, focal, inverts));

  /// Adds a row: tile set [set], keyed by key chain [keys] or run through
  /// effect chain [chain] if one is named (not both: a chain's keys are
  /// its ops), posed by [inverse] — canvas pixel to the row's own,
  /// row-major with the homogeneous row last, over an output of [columns]
  /// × [rows] pixels — sampled by [sampling], Blend's radius at least
  /// [radiusFloor], through colour matrix [matrix] if any, laid at
  /// [opacity] (65535 whole) in blend mode [mode] (the engine's id).
  ///
  /// False where its pose lands nothing, so it lays nothing and is left
  /// out.
  bool row({
    required int set,
    required List<double> inverse,
    required GpuSampling sampling,
    required int columns,
    required int rows,
    required int mode,
    int? matrix,
    int? keys,
    int? chain,
    double radiusFloor = 1,
    int opacity = 65535,
  }) {
    if (inverse.length != 9) {
      throw ArgumentError('an inverse of ${inverse.length}, not 9');
    }
    final added = using(
      (arena) => rust.planRow(
        _plan,
        set,
        matrix ?? -1,
        keys ?? -1,
        chain ?? -1,
        _doubles(arena, inverse),
        radiusFloor,
        sampling.id,
        columns,
        rows,
        opacity,
        mode,
      ),
    );
    return _checked(added) == 1;
  }

  /// Opens a transparent buffer — a folder's, a clip's base or its scope —
  /// or, where [opaque], one holding the buffer under it with its alpha
  /// made whole: a clip's scope whose rows blend with the base.
  void open({bool opaque = false}) => rust.planOpen(_plan, opaque);

  /// Closes the open buffer onto the one under it at [opacity] in [mode],
  /// through effect chain [chain] if any — what it puts laid against the
  /// buffer it ran on at [mix] (65535 whole) — then colour matrix [matrix]
  /// if any.
  void close({
    required int mode,
    int opacity = 65535,
    int? matrix,
    int? chain,
    int mix = 65535,
  }) => rust.planClose(_plan, opacity, mode, matrix ?? -1, chain ?? -1, mix);

  /// Closes the open buffer — opened on nothing, its steps laid in a row's
  /// own space — as that row: drawn over effect chain [chain]'s tiles and
  /// run through it, else over the row's own [tiles] (x0, y0, columns,
  /// rows), and laid as [row] lays a row, posed by [inverse] and the rest.
  ///
  /// False where its pose lands nothing, so it lays nothing: the buffer is
  /// taken out with its steps.
  bool closeRow({
    int? chain,
    (int, int, int, int)? tiles,
    required List<double> inverse,
    required GpuSampling sampling,
    required int columns,
    required int rows,
    required int mode,
    int? matrix,
    double radiusFloor = 1,
    int opacity = 65535,
  }) {
    if (inverse.length != 9) {
      throw ArgumentError('an inverse of ${inverse.length}, not 9');
    }
    final closed = using(
      (arena) => rust.planCloseRow(
        _plan,
        chain ?? -1,
        _rectOrNull(arena, tiles),
        matrix ?? -1,
        _doubles(arena, inverse),
        radiusFloor,
        sampling.id,
        columns,
        rows,
        opacity,
        mode,
      ),
    );
    return _checked(closed) == 1;
  }

  /// Closes a clip's scope onto its base by the base's alpha.
  void closeAtop() => rust.planCloseAtop(_plan);

  /// Lays [colour] — straight RGBA8, A<<24|B<<16|G<<8|R — over the canvas
  /// pixels [[left], [top], [right], [bottom]) in normal.
  void solid(int colour, int left, int top, int right, int bottom) =>
      rust.planSolid(_plan, colour, left, top, right, bottom);

  /// Lays the plan's masked steps — its range marks ([mark]) — under
  /// [mask]: one a plan.
  void mask(GpuMask mask) =>
      _checked(rust.planMask(_plan, _engine._its(mask)._mask));

  /// Adds the range a fill held down will cover, as the engine marks it: a
  /// checker of cells of 8 of its row's pixels, white and black at half
  /// alpha, laid in normal under the plan's [mask] — the range — and posed
  /// as [row] poses its row, by [inverse] and the rest; its cells pushed
  /// [shift] of the row's pixels, the press's move.
  ///
  /// False where its pose lands nothing, so it lays nothing and is left
  /// out.
  bool mark({
    required List<double> inverse,
    required GpuSampling sampling,
    required int columns,
    required int rows,
    (double, double) shift = (0, 0),
    double radiusFloor = 1,
  }) {
    if (inverse.length != 9) {
      throw ArgumentError('an inverse of ${inverse.length}, not 9');
    }
    final (dx, dy) = shift;
    final added = using(
      (arena) => rust.planMark(
        _plan,
        _doubles(arena, inverse),
        radiusFloor,
        sampling.id,
        columns,
        rows,
        (dx * 65536).round(),
        (dy * 65536).round(),
      ),
    );
    return _checked(added) == 1;
  }

  /// Lets go of the plan — once its weighs on their way have told, where
  /// any is ([tilesMade]): each reads its answer off the plan.
  void free() {
    if (_weighing == 0) {
      rust.planFree(_plan);
    } else {
      _freed = true;
    }
  }
}

/// The picture an effect chain had come to at a plug-in's step, and the
/// rows the step reads, kept on the device once the plan that names it ran
/// ([GpuPlan.chainRead]) — what the plug-in runs over there
/// ([GpuPluginRenderer.renderRead]).
class GpuChainRead implements _OfAnEngine {
  GpuChainRead(this._engine) : _read = rust.chainReadNew(_engine._engine);

  @override
  final GpuEngine _engine;
  final Pointer<rust.ChainRead> _read;

  /// It as any isolate asks it ([GpuChainReader]) — for as long as it is
  /// not freed.
  GpuChainReader get reader =>
      GpuChainReader._(_engine._engine.address, _read.address);

  /// Frees it; a plan that names it keeps its own hold.
  void free() => rust.chainReadFree(_read);
}

/// A [GpuChainRead] as any isolate asks it: plain numbers, the engine's
/// address and the read's, so it crosses to a worker — where the wait for
/// the plan that ran through it is that worker's, not the asker's
/// ([debugWaitsHere]).
final class GpuChainReader {
  const GpuChainReader._(this._engine, this._read);

  final int _engine;
  final int _read;

  /// The pixels of [picture] — left, top, right, bottom — of the chain, or
  /// of its row in slot [row], straight RGBA8 row after row; null where no
  /// plan ran through this read, a chain the tiles asked for do not meet
  /// being no chain run, or it keeps no such row. ⚠️Waits for the GPU — a
  /// test's read, and a test's stand-in plug-in's: the app's run reads the
  /// tiles where they lie ([GpuPluginRenderer.renderRead]).
  Uint8List? pixels((int, int, int, int) picture, {int? row}) =>
      using((arena) {
        final (left, top, right, bottom) = picture;
        final edges = arena<Int32>(4);
        edges.asTypedList(4).setAll(0, [left, top, right, bottom]);
        final count = (right - left) * (bottom - top) * 4;
        final bytes = arena<Uint8>(_held(count));
        final read = rust.chainReadPixels(
          Pointer.fromAddress(_engine),
          Pointer.fromAddress(_read),
          edges,
          row ?? -1,
          bytes,
          count,
        );
        return read ? Uint8List.fromList(bytes.asTypedList(count)) : null;
      });
}

/// What effect chains put, held past the run that made them
/// (rust/src/kernels/composite/held.rs), under the numbers the app gives
/// them ([GpuPlan.chainHeld]) — for as long as it is not freed, or let go.
class GpuHeldChains implements _OfAnEngine {
  /// Holds of [engine]'s, for its plans to name ([_OfAnEngine]): what a
  /// run put is that engine's, and a plan that finds it under its number
  /// lays it — and that engine lets go of it, on its thread.
  ///
  /// ↩️⏳Till 2026-11-14 a hold was made with no engine, was of none
  /// while it held no number, and outlived the engine an app let go
  /// (1bd028848, the day before). What a hold keeps is let go of on the
  /// thread of the engine it was made for (rust `device::Handed`), and
  /// one kept past its engine had the next one's buffers let go of on
  /// the first one's thread. So the app makes one for each engine
  /// (`EngineChainHolds.heldOf`) — 브러시/렌더링, the user asleep; theirs
  /// to overturn.
  GpuHeldChains(this._engine) : _held = rust.heldNew(_engine._engine);

  /// The bytes every hold keeps, counted by the engine where a hold keeps
  /// and lets go — on its thread, so one let go of ([letGo]) is counted
  /// off once a [GpuEngine.done] asked after it is told.
  static int get liveBytes => rust.heldBytes();

  @override
  final GpuEngine _engine;

  /// The engine whose plans name it.
  GpuEngine get engine => _engine;

  final Pointer<rust.HeldChains> _held;

  /// The bytes it keeps under [id] — none where it keeps nothing.
  int bytesOf(int id) => rust.heldBytesOf(_held, id);

  /// Lets go of what it keeps under [id], if anything: on the engine's
  /// thread, in turn behind every run handed there before it, this
  /// isolate waiting for none of it (rust/src/device.rs, `posted_of` —
  /// 🔬waited for, each value of a blur dragged held the UI 48–63 ms for
  /// the driver to let one put go, the Surface, 2026-11-20).
  void letGo(int id) => rust.heldLetGo(_held, id);

  /// Frees it; a plan that names it keeps its own hold.
  void free() => rust.heldFree(_held);
}

/// A mask kept on the GPU (rust/src/kernels/composite/abi.rs): a byte a
/// pixel over its box — a fill range's, in the space of the row it lies on
/// — made once and named by each plan that lays steps under it
/// ([GpuPlan.mask]) till it is freed, or let go of.
class GpuMask implements _OfAnEngine, Finalizable {
  /// [bytes], a byte a pixel row after row over [width] × [height], whose
  /// top-left pixel is ([x], [y]), on [composite]'s engine.
  factory GpuMask(
    GpuComposite composite,
    Uint8List bytes, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    if (bytes.length != width * height) {
      throw ArgumentError('${bytes.length} bytes, not $width × $height');
    }
    final mask = using((arena) {
      final held = _bytes(arena, bytes);
      return rust.maskNew(
        composite._engine._engine,
        held,
        x,
        y,
        width,
        height,
      );
    });
    return GpuMask._kept(composite._engine, mask, width * height);
  }

  /// [made] on [engine], [bytes] a byte a pixel: freed by [free], or with
  /// the object where nothing freed it — a selection's mask lives as long
  /// as the clip that asked for it (the app's `SelectionClip`), as a
  /// stamp's picture does ([GpuStampPicture]).
  factory GpuMask._kept(
    GpuEngine engine,
    Pointer<rust.MaskPlane> made,
    int bytes,
  ) {
    if (made == nullptr) {
      throw GpuRefused(_lastError());
    }
    final mask = GpuMask._(engine, made, bytes);
    _freed.attach(mask, made.cast(), detach: mask, externalSize: bytes);
    return mask;
  }

  GpuMask._(this._engine, this._mask, this._length);

  static final NativeFinalizer _freed = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<rust.MaskPlane>)>>(
      rust.maskFree,
    ).cast(),
  );

  /// The bytes of every mask made and not yet freed, counted by the engine
  /// where it makes and frees them.
  static int get liveBytes => rust.maskBytes();

  @override
  final GpuEngine _engine;
  final Pointer<rust.MaskPlane> _mask;

  /// Its pixels: a byte each over its box.
  final int _length;

  /// Its bytes, a byte a pixel row after row over its box, once the GPU is
  /// done with what put them. Waits for the GPU.
  Uint8List read() => using((arena) {
    final bytes = arena<Uint8>(_held(_length));
    // ⚠️No test reaches the throw: a read fails only where the device does.
    if (!rust.maskRead(_engine._engine, _mask, bytes, _length)) {
      throw GpuRefused(_lastError());
    }
    return Uint8List.fromList(bytes.asTypedList(_length));
  });

  /// Frees the mask now; a plan that names it keeps its own hold.
  void free() {
    _freed.detach(this);
    rust.maskFree(_mask);
  }
}

/// The executor: plans of the pool's tiles composited on the GPU.
class GpuComposite implements _OfAnEngine {
  /// The executor on [engine], its full pass compiled.
  factory GpuComposite(GpuEngine engine) =>
      GpuComposite._(engine, _compiled(engine._engine));

  /// Compiled on [engine] off this isolate, which goes on meanwhile — and
  /// with it the pass that shows on a screen of BGRA texels where [bgra],
  /// of RGBA else ([GpuEngine.surface]'s; a [GpuWindow] is RGBA), which the
  /// first [show] compiles where it is called else: the thread an app's
  /// frames are built on (🗣️관제 2026-11-10 18:14, gpu-canonical-store ⑦ —
  /// 🔬3.5 s of a stopped UI at the first canvas, Surface Pro 11).
  static Future<GpuComposite> opening(
    GpuEngine engine, {
    required bool bgra,
  }) async =>
      GpuComposite._(engine, await _compiledOff(engine, _showing(bgra)));

  static Pointer<rust.Composite> _compiled(Pointer<rust.Engine> on) =>
      _made(rust.compositeNew(on));

  /// [_compiled], and with it the pass that shows on a screen as [bgra]
  /// says, the two at once (rust/src/kernels/composite, `showing`) — made
  /// here, of a bool alone, for what crosses to the other isolate.
  static Pointer<rust.Composite> Function(Pointer<rust.Engine>) _showing(
    bool bgra,
  ) => (on) => _made(rust.compositeShowing(on, bgra));

  static Pointer<rust.Composite> _made(Pointer<rust.Composite> composite) {
    if (composite == nullptr) {
      throw GpuRefused(_lastError());
    }
    return composite;
  }

  GpuComposite._(this._engine, this._composite);

  @override
  final GpuEngine _engine;
  final Pointer<rust.Composite> _composite;

  /// The engine it composes on.
  GpuEngine get engine => _engine;

  /// Whether the kernels an effect chain runs on are still to be compiled
  /// by [compileChains]. A plan that names a chain ([GpuPlan.namesAChain])
  /// compiles them where it is run else — all seven, for any chain: 🔬6.5 s
  /// of a stopped UI as S5 opened, Surface Pro 11 (gpu-canonical-store ⑦).
  ///
  /// False once that compile has been through, where it left them
  /// uncompiled too: the plan's run is then what compiles them, and what
  /// says why it cannot — nothing waits for a compile that will not come.
  /// ↩️The engine was asked whether they stood besides (11-10): nothing
  /// makes them stand while a frame would wait but this compile, whose end
  /// says so — with the engine's word turned off no pin moved.
  bool get chainsAreToCome => !_chainsThrough;

  /// The chains' kernels compiled off this isolate, which goes on
  /// meanwhile: one compile, however many ask. ⚠️The executor is freed only
  /// once it is done.
  Future<void> compileChains() => _chains ??=
      (debugChainsCompile?.call() ??
              _chainsOff(_composite.address, _engine._engine.address))
          .whenComplete(() => _chainsThrough = true);

  /// Test seam: the compile [compileChains] waits for, in place of the
  /// one off this isolate. A compile that ends in an error is no state
  /// a driver can be put in, and what a frame does once one has is
  /// pinned all the same (🗣️관제 2026-11-11: 「컴파일이 실패한 뒤 … 끝나지
  /// 않는 재시도로 가지 않는지」).
  @visibleForTesting
  static Future<void> Function()? debugChainsCompile;

  Future<void>? _chains;
  bool _chainsThrough = false;

  static Future<void> _chainsOff(int composite, int engine) => Isolate.run(
    () => rust.compositeChains(
      Pointer.fromAddress(composite),
      Pointer.fromAddress(engine),
    ),
  );

  /// Composites [plan] of [pool]'s tiles over the output [tiles] — canvas
  /// tile columns and rows — with nothing outside the pixels [extent],
  /// [left, top, right, bottom), and submits the work.
  GpuComposited run(
    GpuPool pool,
    GpuPlan plan,
    List<(int, int)> tiles,
    (int, int, int, int) extent,
  ) {
    final out = using((arena) {
      final at = arena<Int32>(_held(2 * tiles.length));
      for (var tile = 0; tile < tiles.length; tile++) {
        at[2 * tile] = tiles[tile].$1;
        at[2 * tile + 1] = tiles[tile].$2;
      }
      return rust.compositeRun(
        _composite,
        _engine._engine,
        _engine._its(pool)._pool,
        _engine._its(plan)._plan,
        at,
        tiles.length,
        _rect(arena, extent),
      );
    });
    _engine._composed();
    if (out == nullptr) {
      throw GpuRefused(_lastError());
    }
    return GpuComposited._(_engine, out, tiles.length);
  }

  /// Composites [plan] of [pool]'s tiles onto the pixels [rect] of
  /// [target] — [left, top, right, bottom) — leaving the rest of it as it
  /// was, and submits the work, waiting for none of it ([GpuEngine.done]);
  /// returns how many passes it took.
  int show(
    GpuPool pool,
    GpuPlan plan,
    GpuTarget target,
    (int, int, int, int) rect,
  ) {
    final passes = using(
      (arena) => rust.compositeShow(
        _composite,
        _engine._engine,
        _engine._its(pool)._pool,
        _engine._its(plan)._plan,
        _engine._its(target)._texture,
        _edges(arena, rect),
      ),
    );
    _engine._composed();
    return _checked(passes);
  }

  /// Lays [picture] — [pool]'s tiles over a box of canvas tiles as
  /// [GpuPlan.set] takes a set: its top-left column [x0] and row [y0], how
  /// many [columns] and [rows], its [tiles] row by row, null for one with
  /// nothing on it — on the tiles [asks] at [opacity] (65535 whole) in
  /// [mode], under [mask] if any, each result in a fresh slot of [cel] of
  /// [pool], inked: a picture the engine drew landed as a cel's own, with
  /// no wait for the GPU — what nothing compares ([GpuStroke.land]
  /// unasked). As many of [asks], the first, as [pool] has room for.
  List<GpuLanded> land(
    GpuPool pool,
    int cel,
    ({int x0, int y0, int columns, int rows, List<GpuTile?> tiles}) picture,
    List<GpuTileAsk> asks, {
    int opacity = 65535,
    required int mode,
    GpuMask? mask,
  }) => _landed(
    asks,
    (arena, coordinates, under, places, changes) => rust.tilesLand(
      _engine._engine,
      _composite,
      _engine._its(pool)._pool,
      cel,
      picture.x0,
      picture.y0,
      picture.columns,
      picture.rows,
      _tileWords(arena, picture.columns, picture.rows, picture.tiles),
      coordinates,
      under,
      asks.length,
      opacity,
      mode,
      mask == null ? nullptr : _engine._its(mask)._mask,
      places,
      changes,
    ),
  );

  /// Frees the executor; before its engine is closed.
  void free() => rust.compositeFree(_composite);
}

/// [rect] — [left, top, right, bottom) of a target's pixels — as four
/// unsigned words of [arena]'s.
Pointer<Uint32> _edges(Arena arena, (int, int, int, int) rect) {
  final (left, top, right, bottom) = rect;
  return arena<Uint32>(4)..asTypedList(4).setAll(0, [left, top, right, bottom]);
}

/// A canvas's screen (rust/src/kernels/composite/screen.rs): the canvas's
/// composite kept at its own pixels, made again where it changed
/// ([compose]), and shown through the camera ([show]) — a pan or a zoom
/// shows what is kept, the canvas's pixels magnified, so what is shown
/// while working is the result (gpu-canonical-store ④⑤).
class GpuScreen implements _OfAnEngine {
  /// The screen of a canvas's composite over the pixels [extent] — [left,
  /// top, right, bottom): the page and what lies past it — on
  /// [composite]'s engine, shown on Blend's radius [radiusFloor] at least,
  /// nothing composed on it yet.
  factory GpuScreen(
    GpuComposite composite,
    (int, int, int, int) extent, {
    double radiusFloor = 1,
  }) {
    final screen = using(
      (arena) => rust.screenNew(
        composite._engine._engine,
        _rect(arena, extent),
        radiusFloor,
      ),
    );
    if (screen == nullptr) {
      throw GpuRefused(_lastError());
    }
    return GpuScreen._(composite, screen);
  }

  GpuScreen._(this._composite, this._screen);

  final GpuComposite _composite;
  final Pointer<rust.Screen> _screen;

  @override
  GpuEngine get _engine => _composite._engine;

  /// Composites [plan] of [pool]'s tiles onto the kept canvas over its
  /// tiles that meet the pixels [changed] — [left, top, right, bottom); the
  /// whole canvas the first time — and submits the work: on the engine's
  /// thread, this isolate waiting for none of it. Ends once the GPU has
  /// finished it, or fails by the [GpuRefused] that names why it did not
  /// ([GpuEngine.done], asked as it is handed over). The tiles [changed]
  /// meets none of are kept as they were: where the composite changed is
  /// the caller's to say. Nothing is added to [plan] after.
  ///
  /// 🚨★★THE UI'S THREAD WAITS FOR NO COMPOSE (the-ui-thread-never-enters-
  /// the-driver B1-a, 2026-11-15): 🔬S5_BA cut 352, main PC, the first fill
  /// and a band baked meanwhile — 5 of 437 composes past 16 ms, 73 ms the
  /// longest, a frame moved under a bake 79 ms; the screen's and the
  /// bake's composes alike (rust/src/device.rs, `Engine::posted`).
  Future<void> compose(
    GpuPool pool,
    GpuPlan plan,
    (int, int, int, int) changed,
  ) {
    using(
      (arena) => rust.screenCompose(
        _screen,
        _engine._its(_composite)._composite,
        _engine._engine,
        _engine._its(pool)._pool,
        _engine._its(plan)._plan,
        _rect(arena, changed),
      ),
    );
    _engine._composed();
    return _engine.done();
  }

  /// [compose] onto a canvas nothing is composed on yet, but over its tiles
  /// that meet the pixels [fresh] alone — [left, top, right, bottom) —:
  /// every other tile [film]'s canvas keeps is copied from it as it is.
  /// Over a film nothing is composed on, the whole canvas.
  Future<void> composeOver(
    GpuScreen film,
    GpuPool pool,
    GpuPlan plan,
    (int, int, int, int) fresh,
  ) {
    using(
      (arena) => rust.screenComposeOver(
        _screen,
        _engine._its(film)._screen,
        _engine._its(_composite)._composite,
        _engine._engine,
        _engine._its(pool)._pool,
        _engine._its(plan)._plan,
        _rect(arena, fresh),
      ),
    );
    _engine._composed();
    return _engine.done();
  }

  /// Shows the kept canvas through the camera onto the pixels [rect] of
  /// [target] — [left, top, right, bottom) — leaving the rest of it as it
  /// was, and submits the work as [compose] does. The camera is [inverse]
  /// — a screen pixel to the canvas's, the affine `[a, b, c, d, e, f]` —
  /// sampled by [sampling]: the one composite at every scale (F-610-Q4,
  /// 유저 2026-11-19 — the engine's `Screen::show` has what a far
  /// reduction costs). ↩️It took the display's scale too till then, for
  /// the halving stage it read under 1/16.
  ///
  /// 🚨WHY IT DID NOT SHOW IS THE NEXT [GpuEngine.done]'S of this isolate
  /// — the one its frame is put up by (`ScreenTexture.present`), asked in
  /// the turn the frame is drawn: a done asked after another body handed
  /// over in between would answer for that one's too.
  void show(
    GpuTarget target, {
    required List<double> inverse,
    required GpuSampling sampling,
    required (int, int, int, int) rect,
  }) {
    if (inverse.length != 6) {
      throw ArgumentError('an inverse of ${inverse.length}, not 6');
    }
    using(
      (arena) => rust.screenShow(
        _screen,
        _engine._its(_composite)._composite,
        _engine._engine,
        _doubles(arena, inverse),
        sampling.id,
        _engine._its(target)._texture,
        _edges(arena, rect),
      ),
    );
  }

  /// The bytes the screen keeps on the GPU — its canvas's: what a budget
  /// and the memory census weigh it by. As of the last of its verbs the
  /// engine has run: one handed over is counted by the time its done is
  /// told ([compose]).
  ///
  /// EACH TILE AS IT LIES (F-610, 2026-11-21): folded at a rest of the
  /// engine's ([GpuEngine.restsAfter]), a tile weighs what the engine
  /// keeps made for it from there on, and the screen is told so by the
  /// engine once that rest's folds are through — with no verb of its own:
  /// a playback's picture nobody composes again reads lighter after the
  /// rest. ↩️A tile's bytes whole for each till then, whatever it lay as:
  /// the memory tab's 「프레임 이미지」 row and the playback's line read
  /// several times what the GPU kept.
  ///
  /// The tiles it MADE, of those it holds (F-610, 유저 2026-11-18 「같은
  /// 타일은 한 벌만」): a tile another screen made of the same input — a
  /// cut's paper, a row no frame of it changes — is held, not made, and is
  /// that screen's to weigh; nobody's once that one is let go
  /// ([GpuEngine.unownedPictureBytes]).
  int get bytes => rust.screenBytes(_screen);

  /// The bytes of every screen's canvas the engine keeps: each screen's
  /// [bytes], counted off as its [free] returns.
  static int get liveBytes => rust.keptBytes();

  /// Frees the screen; before its executor is. Waits for none of the verbs
  /// handed over ahead of it, which still read it ([compose], [show]): the
  /// engine lets go of it behind them, and its pictures' slots go back to
  /// the pool there — [GpuEngine.idlePictureBytes] counts them by a
  /// [GpuEngine.done] asked after this.
  void free() => rust.screenFree(_screen);
}

/// What a run put: its output tiles' pixels, on the GPU.
class GpuComposited implements _OfAnEngine {
  GpuComposited._(this._engine, this._composited, this.tiles);

  @override
  final GpuEngine _engine;
  final Pointer<rust.Composited> _composited;

  /// How many output tiles it put.
  final int tiles;

  /// Its pixels once the GPU is done — straight RGBA8, tile after tile in
  /// the order asked, each [gpuTileSide] rows of [gpuTileSide].
  Uint8List read() => _compositedPixels(_engine._engine, _composited, tiles);

  /// This run as any isolate reads it — till it is freed.
  GpuCompositedReader get reader => GpuCompositedReader._(
    _engine._engine.address,
    _composited.address,
    tiles,
  );

  void free() => rust.compositedFree(_composited);
}

/// A [GpuComposited] as any isolate reads it: plain numbers, the engine's
/// address and the run's, so it crosses to a worker — where the wait for
/// the GPU is that worker's, not the asker's ([debugWaitsHere]), as a
/// [GpuChainReader]'s is.
final class GpuCompositedReader {
  const GpuCompositedReader._(this._engine, this._composited, this._tiles);

  final int _engine;
  final int _composited;
  final int _tiles;

  /// [GpuComposited.read], asked here. ⚠️Waits for the GPU.
  Uint8List read() => _compositedPixels(
    Pointer.fromAddress(_engine),
    Pointer.fromAddress(_composited),
    _tiles,
  );
}

/// The pixels [composited] put over its [tiles] on [engine], once the GPU
/// has made them.
Uint8List _compositedPixels(
  Pointer<rust.Engine> engine,
  Pointer<rust.Composited> composited,
  int tiles,
) => using((arena) {
  final count = rust.compositedBytes(tiles);
  final bytes = arena<Uint8>(_held(count));
  // ⚠️No test reaches the throw: a read fails only where the device does.
  if (!rust.compositedRead(engine, composited, bytes, count)) {
    throw GpuRefused(_lastError());
  }
  return Uint8List.fromList(bytes.asTypedList(count));
});

/// The export's conversions of a frame as the screen shows it, on the GPU
/// before its readback (gpu-export-path ①), each pass compiled where it
/// is first asked. A frame is a [GpuShown] ([shown]); the picture is its
/// width × height from the frame's top-left pixel.
class GpuExport implements _OfAnEngine {
  /// The export's passes on [engine], none compiled yet.
  GpuExport(GpuEngine engine)
    : _engine = engine,
      _export = rust.exportNew(engine._engine);

  /// The export's passes on [engine], compiled off this isolate for the
  /// frames it makes and for frames shown on surfaces laid [bgra] or not:
  /// no frame's first lay, and no file's first conversion of any kind,
  /// compiles where it is asked (🗣️관제 2026-11-10 18:14,
  /// gpu-canonical-store ⑦).
  static Future<GpuExport> opening(
    GpuEngine engine, {
    required bool bgra,
  }) async {
    final export = GpuExport(engine);
    final passes = engine._its(export)._export.address;
    final on = engine._engine.address;
    await Isolate.run(
      () => rust.exportWarm(
        Pointer<rust.Export>.fromAddress(passes),
        Pointer<rust.Engine>.fromAddress(on),
        bgra,
      ),
    );
    return export;
  }

  @override
  final GpuEngine _engine;
  final Pointer<rust.Export> _export;

  /// The picture of [width] × [height] from the top-left pixel of
  /// [surface] — a frame as the screen shows it, premultiplied — copied on
  /// the GPU for the conversions: what the canvas shows is what a file is
  /// made of, and nothing crosses to the CPU before a writer's bytes.
  GpuShown shown(GpuSurface surface, int width, int height) {
    final shown = rust.exportShown(
      _engine._engine,
      _engine._its(surface)._surface,
      width,
      height,
    );
    if (shown == nullptr) {
      throw GpuRefused(_lastError());
    }
    return GpuShown._(_engine, shown, width, height);
  }

  /// A [width] × [height] frame this export makes, laid with [ground] —
  /// straight RGBA8, A<<24|B<<16|G<<8|R; an alpha of 0 leaves it clear —
  /// for pictures to be laid over ([lay]): a frame's last picture made on
  /// the engine, which the conversions read as they read a frame shown.
  GpuShown blank(int width, int height, {int ground = 0}) => _shownOrWhy(
    rust.exportBlank(_export, _engine._engine, width, height, ground),
    width,
    height,
  );

  /// [rgba] — [width] × [height] premultiplied pixels, four bytes each,
  /// red first, row after row — on the GPU, to lay over a frame ([lay]):
  /// what the app rasters of what it draws over one.
  GpuShown upload(Uint8List rgba, int width, int height) => _shownOrWhy(
    using(
      (arena) => rust.exportUpload(
        _engine._engine,
        _bytes(arena, rgba),
        rgba.length,
        width,
        height,
      ),
    ),
    width,
    height,
  );

  /// [alpha] — a byte for each of [width] × [height] pixels, row after
  /// row — on the GPU as a frame's cover ([lay]): how much of what is laid
  /// each pixel takes.
  GpuCover cover(Uint8List alpha, int width, int height) {
    final cover = using(
      (arena) => rust.exportCover(
        _engine._engine,
        _bytes(arena, alpha),
        alpha.length,
        width,
        height,
      ),
    );
    if (cover == nullptr) {
      throw GpuRefused(_lastError());
    }
    return GpuCover._(_engine, cover);
  }

  /// Lays [source], its top-left at ([x], [y]) of [onto], over [onto] at
  /// [opacity] — 65535 whole, as a plan lays a row — each pixel taking of
  /// it what [cover] says, all of it where there is none, and only within
  /// the pixels [within] names — [left, top, right, bottom) — where it
  /// does; and submits the work. [onto] is a frame [blank] made.
  void lay(
    GpuShown onto,
    GpuShown source, {
    int x = 0,
    int y = 0,
    int opacity = 65535,
    GpuCover? cover,
    (int, int, int, int)? within,
  }) => _laid(
    using(
      (arena) => rust.exportLay(
        _export,
        _engine._engine,
        _engine._its(onto)._shown,
        _engine._its(source)._shown,
        x,
        y,
        opacity,
        cover == null ? nullptr : _engine._its(cover)._cover,
        _rectOrNull(arena, within),
      ),
    ),
  );

  /// [lay] of one [colour] — straight RGBA8, A<<24|B<<16|G<<8|R — over
  /// the whole of [onto].
  void layColour(
    GpuShown onto,
    int colour, {
    int opacity = 65535,
    GpuCover? cover,
    (int, int, int, int)? within,
  }) => _laid(
    using(
      (arena) => rust.exportLayColour(
        _export,
        _engine._engine,
        _engine._its(onto)._shown,
        colour,
        opacity,
        cover == null ? nullptr : _engine._its(cover)._cover,
        _rectOrNull(arena, within),
      ),
    ),
  );

  /// What [frame] — one [blank] made — holds, to read back: its
  /// premultiplied RGBA, red first, row after row with nothing between.
  GpuReadout read(GpuShown frame) =>
      _readout(rust.exportRead(_engine._engine, _engine._its(frame)._shown));

  GpuShown _shownOrWhy(Pointer<rust.Shown> shown, int width, int height) {
    if (shown == nullptr) {
      throw GpuRefused(_lastError());
    }
    return GpuShown._(_engine, shown, width, height);
  }

  void _laid(bool laid) {
    if (!laid) {
      throw GpuRefused(_lastError());
    }
  }

  /// The picture of [width] × [height] in [frame] as an encoder's NV12
  /// frame of [frameWidth] × [frameHeight], rows [stride] bytes apart —
  /// the writer's frame as it opened its encoder: `frameHeight` Y rows,
  /// then `frameHeight / 2` CbCr rows.
  GpuReadout nv12(
    GpuShown frame,
    int width,
    int height, {
    required int frameWidth,
    required int frameHeight,
    required int stride,
  }) => _readout(
    using((arena) {
      final words = [width, height, frameWidth, frameHeight, stride];
      final shape = arena<Uint32>(5)..asTypedList(5).setAll(0, words);
      return rust.exportNv12(
        _export,
        _engine._engine,
        _engine._its(frame)._shown,
        shape,
      );
    }),
  );

  /// The picture of [width] × [height] in [frame] over [ground] —
  /// B<<16|G<<8|R — three bytes a pixel, row after row with nothing
  /// between; its alpha cut at [cut] where a GIF cuts it (null: its
  /// shades; 0: a GIF with no clear colour).
  GpuReadout overGround(
    GpuShown frame,
    int width,
    int height,
    int ground, {
    int? cut,
  }) => _readout(
    rust.exportOverGround(
      _export,
      _engine._engine,
      _engine._its(frame)._shown,
      width,
      height,
      ground,
      cut ?? -1,
    ),
  );

  /// The pixels of the picture of [width] × [height] in [frame] whose
  /// alpha is under [cut]: pixel i is bit i % 8 of byte i ~/ 8, low bit
  /// first, row after row with nothing between.
  GpuReadout clear(GpuShown frame, int width, int height, int cut) => _readout(
    rust.exportClear(
      _export,
      _engine._engine,
      _engine._its(frame)._shown,
      width,
      height,
      cut,
    ),
  );

  /// Whether every pixel of the picture of [width] × [height] in [frame]
  /// is opaque, once the GPU is done.
  bool opaque(GpuShown frame, int width, int height) {
    final readout = _readout(
      rust.exportOpaque(
        _export,
        _engine._engine,
        _engine._its(frame)._shown,
        width,
        height,
      ),
    );
    try {
      return using((arena) {
        final word = arena<Uint8>(4);
        readout
          ..map()
          ..rows(
            word,
            offset: 0,
            stride: 4,
            rowBytes: 4,
            rows: 1,
            dstStride: 4,
          );
        final answer = ByteData.sublistView(word.asTypedList(4));
        return answer.getUint32(0, Endian.little) == 255;
      });
    } finally {
      readout.free();
    }
  }

  /// The rows of a PNG of the picture of [width] × [height] in [frame],
  /// four bytes a pixel, under their filters: each its filter's byte and
  /// its own, [pngRowBytes] from the last.
  GpuReadout pngRgba(GpuShown frame, int width, int height) => _readout(
    rust.exportPngRgba(
      _export,
      _engine._engine,
      _engine._its(frame)._shown,
      width,
      height,
    ),
  );

  /// The picture of [width] × [height] in [frame] straight — four bytes a
  /// pixel, red first, row after row with nothing between: what a writer
  /// that keeps the alpha takes.
  GpuReadout straight(GpuShown frame, int width, int height) => _readout(
    rust.exportStraight(
      _export,
      _engine._engine,
      _engine._its(frame)._shown,
      width,
      height,
    ),
  );

  /// [pngRgba] for a PNG of three bytes a pixel, from [rgb] — what
  /// [overGround] put for the same picture, which stays on the GPU.
  GpuReadout pngRgb(GpuReadout rgb, int width, int height) => _readout(
    rust.exportPngRgb(
      _export,
      _engine._engine,
      _engine._its(rgb)._readout,
      width,
      height,
    ),
  );

  /// [pngRgba] for a PNG of four bytes a pixel, from [rgba] — the picture
  /// of [width] × [height] straight, red first, row after row with nothing
  /// between — copied to the GPU as it is: an animated PNG's frame, whose
  /// alpha a frame's premultiplied colour would not carry back as it was.
  GpuReadout pngStraight(Uint8List rgba, int width, int height) =>
      _readout(
        using(
          (arena) => rust.exportPngStraight(
            _export,
            _engine._engine,
            _bytes(arena, rgba),
            rgba.length,
            width,
            height,
          ),
        ),
      );

  /// Where each of a PNG's filtered rows starts from the last's, for a
  /// picture [width] wide of [pixelBytes] a pixel.
  static int pngRowBytes(int width, int pixelBytes) =>
      rust.exportPngRowBytes(width, pixelBytes);

  /// Where each row of an NV12 frame [width] wide ([nv12]) starts from the
  /// last's, the least the pass takes: the width on whole words, as the
  /// pass writes a word at a time.
  static int nv12RowBytes(int width) => (width + 3) & ~3;

  GpuReadout _readout(Pointer<rust.Readout> readout) {
    if (readout == nullptr) {
      throw GpuRefused(_lastError());
    }
    return GpuReadout._(_engine, readout);
  }

  /// Frees the passes; before their engine is closed.
  void free() => rust.exportFree(_export);
}

/// A frame as the screen shows it, copied on the GPU for the export's
/// conversions ([GpuExport.shown]).
class GpuShown implements _OfAnEngine {
  GpuShown._(this._engine, this._shown, this.width, this.height);

  @override
  final GpuEngine _engine;
  final Pointer<rust.Shown> _shown;

  /// Its size in pixels: what it was made as.
  final int width;
  final int height;

  /// Frees the copy; before its engine is closed.
  void free() => rust.exportShownFree(_shown);
}

/// How much of what is laid each pixel of a frame takes, on the GPU
/// ([GpuExport.cover]).
class GpuCover implements _OfAnEngine {
  GpuCover._(this._engine, this._cover);

  @override
  final GpuEngine _engine;
  final Pointer<rust.Cover> _cover;

  /// Frees the cover; before its engine is closed.
  void free() => rust.exportCoverFree(_cover);
}

/// What a conversion put: on the GPU until it is mapped, then copied row
/// by row straight into wherever its writer takes it.
class GpuReadout implements _OfAnEngine {
  GpuReadout._(this._engine, this._readout);

  @override
  final GpuEngine _engine;
  final Pointer<rust.Readout> _readout;

  /// The bytes of the buffer every readout was made of, made and not yet
  /// freed: counted by the engine where it makes and frees them. A readout
  /// is one read's — none stays counted past it.
  static int get liveBytes => rust.readoutLiveBytes();

  /// The bytes of it its writer takes.
  int get bytes => rust.readoutBytes(_readout);

  /// All the bytes of it its writer takes, mapped and copied out as they
  /// lie.
  Uint8List copy() => copyRows(stride: bytes, rowBytes: bytes, rows: 1);

  /// [rows] rows of [rowBytes] — the first at its start, each [stride]
  /// from the last — mapped and copied out one after another with nothing
  /// between: a PNG's filtered rows without the filling that starts each
  /// on a word ([GpuExport.pngRowBytes]).
  Uint8List copyRows({
    required int stride,
    required int rowBytes,
    required int rows,
  }) {
    map();
    return using((arena) {
      final count = rowBytes * rows;
      final into = arena<Uint8>(_held(count));
      this.rows(
        into,
        offset: 0,
        stride: stride,
        rowBytes: rowBytes,
        rows: rows,
        dstStride: rowBytes,
      );
      return Uint8List.fromList(into.asTypedList(count));
    });
  }

  /// [copy], and the readout freed: what a writer takes of one it reads
  /// once.
  Uint8List take() {
    try {
      return copy();
    } finally {
      free();
    }
  }

  /// The rows of a PNG [width] × [height] of [pixelBytes] a pixel that a
  /// filter pass put ([GpuExport.pngRgba], [GpuExport.pngRgb],
  /// [GpuExport.pngStraight]) — each its filter's byte and its own, one
  /// after another without the filling that starts each on a word
  /// ([GpuExport.pngRowBytes]) — and the readout freed: what a writer
  /// deflates.
  Uint8List takePngRows(int width, int height, int pixelBytes) {
    try {
      return copyRows(
        stride: GpuExport.pngRowBytes(width, pixelBytes),
        rowBytes: 1 + width * pixelBytes,
        rows: height,
      );
    } finally {
      free();
    }
  }

  /// Waits for the GPU and maps its bytes — once: a second call finds
  /// them mapped.
  void map() {
    if (!rust.readoutMap(_engine._engine, _readout)) {
      throw GpuRefused(_lastError());
    }
  }

  /// [map] with no wait on this isolate, which goes on meanwhile: the
  /// engine's thread waits for the GPU, and this ends once it has
  /// (rust/src/kernels/export/abi.rs, `gpu_engine_readout_map_then`).
  /// ⚠️It ends the same where the wait was refused — [rows] then throws
  /// by why. Nothing else is asked of it, nor is it freed, till this has
  /// ended.
  Future<void> mapping() {
    debugBeforeMapping?.call();
    final ended = Completer<void>();
    rust.readoutMapThen(
      _engine._engine,
      _readout,
      _maps.told,
      _maps.kept(ended),
    );
    return ended.future;
  }

  /// The waits on their way ([mapping]), and how a thread of the engine's
  /// tells this isolate one has ended — mapped or not alike: [rows] says
  /// which.
  static final _maps = _Told<Completer<void>>(
    (_, ended, _) => ended.complete(),
  );

  /// Test seam: called before a thread of the engine's is handed the wait
  /// ([mapping]) — how a test has the device go between a copy's submit
  /// and the wait for it.
  @visibleForTesting
  static void Function()? debugBeforeMapping;

  /// Copies [rows] rows of [rowBytes] — the first at [offset], each
  /// [stride] from the last — into [dst], each [dstStride] from the last.
  /// It is mapped, and the rows end within its [bytes]; one whose wait was
  /// refused ([mapping]) throws by why.
  void rows(
    Pointer<Uint8> dst, {
    required int offset,
    required int stride,
    required int rowBytes,
    required int rows,
    required int dstStride,
  }) {
    final copied = rust.readoutRows(
      _readout,
      offset,
      stride,
      rowBytes,
      rows,
      dst,
      dstStride,
    );
    if (!copied) {
      throw GpuRefused(_lastError());
    }
  }

  void free() => rust.readoutFree(_readout);
}

/// A walked tile's ink: where it is on its cel's grid, and its box —
/// tile-local, the far edges past the last column and row with ink — or
/// null where it holds none.
typedef GpuTileInk = ({
  int column,
  int row,
  ({int left, int top, int right, int bottom})? box,
});

/// The words the scan puts for a walked tile (cel_pixel/abi.rs's
/// TILE_INK_WORDS): its column and row, then its box's four edges — four 0s
/// where it holds no ink.
const _tileInkWords = 6;

/// The fold and the unfold (rust/src/kernels/fold), compiled: what a pool
/// folds its tiles by ([GpuPool.fold]) — and, kept by the engine, what a
/// read of a tile that lies folded finds there.
class GpuFold implements _OfAnEngine {
  /// Compiled on [engine], the caller waiting.
  factory GpuFold(GpuEngine engine) =>
      GpuFold._(engine, _compiled(engine._engine));

  /// Compiled on [engine] off this isolate, which goes on meanwhile.
  static Future<GpuFold> opening(GpuEngine engine) async =>
      GpuFold._(engine, await _compiledOff(engine, _compiled));

  static Pointer<rust.Fold> _compiled(Pointer<rust.Engine> on) {
    final fold = rust.foldNew(on);
    if (fold == nullptr) {
      throw GpuRefused(_lastError());
    }
    return fold;
  }

  GpuFold._(this._engine, this._fold);

  @override
  final GpuEngine _engine;
  final Pointer<rust.Fold> _fold;

  void free() => rust.foldFree(_fold);
}

/// The ink scan (rust/src/kernels/cel_pixel/ink.rs): where each of a cel's
/// tiles on the pool holds ink, as the app's `TileInkBounds` says it.
class GpuInk {
  /// The scan on [engine], compiled, the caller waiting.
  factory GpuInk(GpuEngine engine) =>
      GpuInk._(engine, _compiled(engine._engine));

  /// Compiled on [engine] off this isolate, which goes on meanwhile.
  static Future<GpuInk> opening(GpuEngine engine) async =>
      GpuInk._(engine, await _compiledOff(engine, _compiled));

  static Pointer<rust.Ink> _compiled(Pointer<rust.Engine> on) {
    final ink = rust.inkNew(on);
    if (ink == nullptr) {
      throw GpuRefused(_lastError());
    }
    return ink;
  }

  GpuInk._(this._engine, this._ink);

  final GpuEngine _engine;
  final Pointer<rust.Ink> _ink;

  /// Each tile of the cel of [columns] × [rows] tiles whose top-left is
  /// column [x0], row [y0] — [tiles] of [pool] row by row, null for one it
  /// has none of — and its ink, in that order, the tiles it has none of
  /// left out. Waits for the GPU.
  List<GpuTileInk> run(
    GpuPool pool,
    int x0,
    int y0,
    int columns,
    int rows,
    List<GpuTile?> tiles,
  ) => using((arena) {
    final words = _tileWords(arena, columns, rows, tiles);
    final capacity = tiles.nonNulls.length * _tileInkWords;
    final out = arena<Int32>(_held(capacity));
    final walked = rust.inkRun(
      _ink,
      _engine._engine,
      _engine._its(pool)._pool,
      x0,
      y0,
      columns,
      rows,
      words,
      out,
      capacity,
    );
    if (walked < 0) {
      throw GpuRefused(_lastError());
    }
    final put = out.asTypedList(capacity);
    return [
      for (var tile = 0; tile < walked; tile++)
        _walkedAt(put, tile * _tileInkWords),
    ];
  });

  void free() => rust.inkFree(_ink);
}

/// The channel a colour verb writes (rust/src/kernels/cel_pixel/mod.rs
/// `Channel`): its [bytes], byte i at [base] + i × [stride] of a pixel's
/// four, and whether a pixel with no ink takes part.
typedef GpuCelChannel = ({int bytes, int base, int stride, bool takesEmpty});

/// A colour verb's selector: for each channel's byte, 256 words, whether
/// the key's tolerance reaches it (bit 0), and whether the verb keeps what
/// the key names rather than takes it.
typedef GpuCelSelector = ({
  Uint32List red,
  Uint32List green,
  Uint32List blue,
  bool keepsMatches,
});

/// What the pixels taking part in a colour verb take.
sealed class GpuCelIncoming {
  const GpuCelIncoming();
}

/// Going forward: the channel's bytes, one value for every pixel.
final class GpuCelValue extends GpuCelIncoming {
  const GpuCelValue(this.bytes);

  final Uint8List bytes;
}

/// An undo: [count] pixels' channel bytes, the i-th at i × [step] of
/// [bytes].
final class GpuCelRecipe extends GpuCelIncoming {
  const GpuCelRecipe(this.bytes, {required this.step, required this.count});

  final Uint8List bytes;
  final int step;
  final int count;
}

/// The kernels over a cel's pixels (rust/src/kernels/cel_pixel): the
/// colour verbs' pass and a selection's lift.
final class GpuCelPixels {
  /// Compiled on [engine], the caller waiting.
  factory GpuCelPixels(GpuEngine engine) =>
      GpuCelPixels._(engine, _made(rust.celPixelsNew(engine._engine)));

  GpuCelPixels._(this._engine, this._pixels);

  /// Compiled on [engine] off this isolate, which goes on meanwhile.
  static Future<GpuCelPixels> opening(GpuEngine engine) async =>
      GpuCelPixels._(engine, await _compiledOff(engine, _compiled));

  static Pointer<rust.CelPixels> _compiled(Pointer<rust.Engine> on) =>
      _made(rust.celPixelsNew(on));

  static Pointer<rust.CelPixels> _made(Pointer<rust.CelPixels> pixels) {
    if (pixels == nullptr) {
      throw GpuRefused(_lastError());
    }
    return pixels;
  }

  final GpuEngine _engine;
  final Pointer<rust.CelPixels> _pixels;

  /// A colour verb over the cel of [columns] × [rows] tiles whose top-left
  /// is column [x0], row [y0] — [tiles] of [pool] row by row, null for one
  /// not walked —, under [mask] if any. What it left is the caller's to
  /// free. Waits for the GPU.
  GpuCelPassed run(
    GpuPool pool,
    int x0,
    int y0,
    int columns,
    int rows,
    List<GpuTile?> tiles, {
    required GpuCelChannel channel,
    required GpuCelIncoming incoming,
    GpuMask? mask,
    GpuCelSelector? selector,
    int threshold = 0,
  }) => using((arena) {
    Pointer<Uint32> table(Uint32List? words) {
      if (words == null) {
        return nullptr;
      }
      if (words.length != 256) {
        throw ArgumentError('a selector\'s tables are 256 words');
      }
      return arena<Uint32>(256)..asTypedList(256).setAll(0, words);
    }

    final bytes = switch (incoming) {
      GpuCelValue(:final bytes) => bytes,
      GpuCelRecipe(:final bytes) => bytes,
    };
    final held = _bytes(arena, bytes);
    final spec = arena<rust.VerbSpec>();
    spec.ref
      ..bytes = channel.bytes
      ..base = channel.base
      ..stride = channel.stride
      ..takesEmpty = channel.takesEmpty ? 1 : 0
      ..threshold = threshold
      ..keepsMatches = selector?.keepsMatches ?? false ? 1 : 0
      ..red = table(selector?.red)
      ..green = table(selector?.green)
      ..blue = table(selector?.blue)
      ..incoming = held
      ..length = bytes.length;
    if (incoming case GpuCelRecipe(:final step, :final count)) {
      spec.ref
        ..undo = 1
        ..step = step
        ..count = count;
    } else {
      spec.ref
        ..undo = 0
        ..step = 0
        ..count = 0;
    }
    final passed = rust.celPixelsRun(
      _pixels,
      _engine._engine,
      _engine._its(pool)._pool,
      x0,
      y0,
      columns,
      rows,
      _tileWords(arena, columns, rows, tiles),
      mask == null ? nullptr : _engine._its(mask)._mask,
      spec,
    );
    if (passed == nullptr) {
      throw GpuRefused(_lastError());
    }
    return GpuCelPassed._(_engine, passed);
  });

  /// What [mask] takes off the cel [run] would walk — a pixel it covers at
  /// all whole where [whole], else its alpha scaled by the coverage —, kept
  /// on the GPU as the picture of its box, [width] × [height], straight
  /// RGBA8: its bytes never read back. Null where it took nothing. Waits for
  /// the GPU to say whether it took any.
  GpuStampPicture? liftPicture(
    GpuPool pool,
    int x0,
    int y0,
    int columns,
    int rows,
    List<GpuTile?> tiles, {
    required GpuMask mask,
    required bool whole,
    required int width,
    required int height,
  }) => using((arena) {
    final out = arena<Pointer<rust.StampPicture>>();
    final lifted = rust.celPixelsLiftPicture(
      _pixels,
      _engine._engine,
      _engine._its(pool)._pool,
      x0,
      y0,
      columns,
      rows,
      _tileWords(arena, columns, rows, tiles),
      _engine._its(mask)._mask,
      whole,
      out,
    );
    if (lifted < 0) {
      throw GpuRefused(_lastError());
    }
    if (lifted == 0) {
      return null;
    }
    return GpuStampPicture._kept(_engine, out.value, width, height);
  }, malloc);

  /// [liftPicture] with no wait: the cel's tiles read where [pool] holds
  /// them now, the lift handed to the engine's thread, and its picture
  /// told once the GPU has said whether it took any — null where it
  /// took nothing (rust/src/kernels/cel_pixel/abi.rs,
  /// `gpu_engine_cel_pixels_lift_picture_unwaited`). Fails as
  /// [GpuRefused] where the lift failed.
  Future<GpuStampPicture?> lifted(
    GpuPool pool,
    int x0,
    int y0,
    int columns,
    int rows,
    List<GpuTile?> tiles, {
    required GpuMask mask,
    required bool whole,
    required int width,
    required int height,
  }) {
    final told = Completer<GpuStampPicture?>();
    final out = malloc<Pointer<rust.StampPicture>>()..value = nullptr;
    _lifts.handing(
      (told: told, engine: _engine, out: out, width: width, height: height),
      (number) => using((arena) {
        rust.celPixelsLiftPictureUnwaited(
          _pixels,
          _engine._engine,
          _engine._its(pool)._pool,
          x0,
          y0,
          columns,
          rows,
          _tileWords(arena, columns, rows, tiles),
          _engine._its(mask)._mask,
          whole,
          out,
          _lifts.told,
          number,
        );
        return 1;
      }),
    );
    return told.future;
  }

  /// The lifts on their way ([lifted]), each told by its number once the
  /// GPU has said whether it took any — or that it failed —, its picture
  /// written to [out] first.
  static final _lifts =
      _Told<
        ({
          Completer<GpuStampPicture?> told,
          GpuEngine engine,
          Pointer<Pointer<rust.StampPicture>> out,
          int width,
          int height,
        })
      >((_, lift, lifted) {
        final made = lift.out.value;
        malloc.free(lift.out);
        if (!lifted) {
          lift.told.completeError(
            _toldRefused(lift.engine, 'a lift failed'),
          );
          return;
        }
        lift.told.complete(
          made == nullptr
              ? null
              : GpuStampPicture._kept(
                  lift.engine,
                  made,
                  lift.width,
                  lift.height,
                ),
        );
      });

  void free() => rust.celPixelsFree(_pixels);
}

/// What a colour verb left ([GpuCelPixels.run]): freed by its caller.
final class GpuCelPassed {
  GpuCelPassed._(this._engine, this._passed);

  final GpuEngine _engine;
  final Pointer<rust.CelPassed> _passed;

  /// The tiles walked, in the walk's order.
  List<({int column, int row})> get tiles => using((arena) {
    final walked = rust.celPassedWalked(_passed);
    final words = arena<Int32>(_held(2 * walked));
    rust.celPassedTiles(_passed, words);
    return [
      for (var at = 0; at < walked; at++)
        (column: words[2 * at], row: words[2 * at + 1]),
    ];
  });

  /// What the pixels taking part held, going forward, as runs in the walk's
  /// order: two words a run, its value (the channel's byte i in bits 8i)
  /// and its length. None from an undo.
  Uint32List get runs => using((arena) {
    final count = rust.celPassedRunCount(_passed);
    final words = arena<Uint32>(_held(2 * count));
    rust.celPassedRuns(_passed, words);
    return Uint32List.fromList(words.asTypedList(2 * count));
  });

  /// Puts as many of the walked tiles from [first] on as [asks] names, each
  /// a pixel of took part in, in a fresh slot of [cel]; as many of them,
  /// the first, as [pool] has room for.
  List<GpuLanded> land(
    GpuPool pool,
    int cel,
    int first,
    List<GpuTileAsk> asks,
  ) => _landed(
    asks,
    (arena, _, _, places, changes) => rust.celPassedLand(
      _passed,
      _engine._engine,
      _engine._its(pool)._pool,
      cel,
      first,
      asks.length,
      places,
      changes,
    ),
  );

  void free() => rust.celPassedFree(_passed);
}

/// The picture a fill reads (rust/src/kernels/flood/picture.rs): what a
/// plan shows over a box — the screen's with the paper left out, which is
/// its maker's to leave out — kept on the GPU for every press that floods
/// it ([GpuFloods.fill]) and freed by its maker.
final class GpuFloodPicture implements _OfAnEngine {
  /// What [plan] of [pool]'s tiles shows over the pixels [extent] of the
  /// canvas — [left, top, right, bottom), nothing past it. Submits the
  /// work.
  factory GpuFloodPicture(
    GpuComposite composite,
    GpuPool pool,
    GpuPlan plan,
    (int, int, int, int) extent,
  ) {
    final engine = composite._engine;
    return GpuFloodPicture._(
      engine,
      using(
        (arena) => rust.floodPictureNew(
          engine._its(composite)._composite,
          engine._engine,
          engine._its(pool)._pool,
          engine._its(plan)._plan,
          _rect(arena, extent),
        ),
      ),
    );
  }

  /// What [plan] of [pool]'s tiles shows as a space posed on the canvas
  /// reads it, over the pixels [extent] of that space — [left, top, right,
  /// bottom): each what the plan shows where [toCanvas] lands it, the
  /// space's pixel to the canvas's — the nine a row is posed by
  /// ([GpuPlan.row]), row-major with the homogeneous row last — and nothing
  /// past the canvas pixels [within], the world the plan draws in. Submits
  /// the work.
  factory GpuFloodPicture.posed(
    GpuComposite composite,
    GpuPool pool,
    GpuPlan plan,
    (int, int, int, int) extent, {
    required List<double> toCanvas,
    required (int, int, int, int) within,
  }) {
    if (toCanvas.length != 9) {
      throw ArgumentError('a pose of ${toCanvas.length}, not 9');
    }
    final engine = composite._engine;
    return GpuFloodPicture._(
      engine,
      using(
        (arena) => rust.floodPicturePosed(
          engine._its(composite)._composite,
          engine._engine,
          engine._its(pool)._pool,
          engine._its(plan)._plan,
          _doubles(arena, toCanvas),
          _rect(arena, extent),
          _rect(arena, within),
        ),
      ),
    );
  }

  GpuFloodPicture._(this._engine, this._picture) {
    if (_picture == nullptr) {
      throw GpuRefused(_lastError());
    }
  }

  @override
  final GpuEngine _engine;
  final Pointer<rust.FloodPicture> _picture;

  void free() => rust.floodPictureFree(_picture);
}

/// A fill finished ([GpuFloods.fill]): its [mask] — a byte a pixel, row
/// after row over [width] × [height] — whose top-left pixel is ([left],
/// [top]) in the space of the picture it flooded.
typedef GpuFilled = ({
  int left,
  int top,
  int width,
  int height,
  Uint8List mask,
});

/// The fill's kernels (rust/src/kernels/flood): the flood's passes and the
/// mask's it is finished by.
final class GpuFloods {
  /// Compiled on [engine], the caller waiting.
  factory GpuFloods(GpuEngine engine) =>
      GpuFloods._(engine, _compiled(engine._engine));

  GpuFloods._(this._engine, this._floods);

  /// Compiled on [engine] off this isolate, which goes on meanwhile.
  static Future<GpuFloods> opening(GpuEngine engine) async =>
      GpuFloods._(engine, await _compiledOff(engine, _compiled));

  static Pointer<rust.Floods> _compiled(Pointer<rust.Engine> on) =>
      rust.floodsNew(on);

  /// The bytes of every picture a fill reads ([GpuFloodPicture]) and every
  /// fill finished, made and not yet freed: counted by the engine where it
  /// makes and lets go of them. Each is one press's — none stays counted
  /// past it.
  static int get liveBytes => rust.floodBytes();

  final GpuEngine _engine;
  final Pointer<rust.Floods> _floods;

  /// The fill a press at ([x], [y]) of [picture]'s space makes: what it
  /// reaches through pixels within [tolerance] of the one pressed —
  /// closing gaps of [gap] pixels where that is not 0 —, grown [expand]
  /// pixels and softened past its outline where [antiAlias]. Refused where
  /// the press is off the picture's box. Waits for the GPU.
  GpuFilled fill(
    GpuFloodPicture picture,
    int x,
    int y, {
    required int tolerance,
    required int gap,
    required int expand,
    required bool antiAlias,
  }) => using((arena) {
    final covers = arena<Int32>(4);
    final filled = rust.floodRun(
      _floods,
      _engine._engine,
      _engine._its(picture)._picture,
      x,
      y,
      tolerance,
      gap,
      expand,
      antiAlias,
      covers,
    );
    if (filled == nullptr) {
      throw GpuRefused(_lastError());
    }
    try {
      final [left, top, width, height] = covers.asTypedList(4);
      final count = width * height;
      final bytes = arena<Uint8>(_held(count));
      // ⚠️No test reaches the throw: a read fails only where the device
      // does.
      if (!rust.floodFilledRead(_engine._engine, filled, bytes, count)) {
        throw GpuRefused(_lastError());
      }
      return (
        left: left,
        top: top,
        width: width,
        height: height,
        mask: Uint8List.fromList(bytes.asTypedList(count)),
      );
    } finally {
      rust.floodFilledFree(filled);
    }
  }, malloc);

  void free() => rust.floodsFree(_floods);
}

/// A selection's mask made on the engine (rust/src/kernels/mask/abi.rs):
/// its hard mask's passes and its finishing's, one set for every
/// selection.
final class GpuSelectionMasks {
  /// Compiled on [engine], the caller waiting.
  factory GpuSelectionMasks(GpuEngine engine) =>
      GpuSelectionMasks._(engine, _compiled(engine._engine));

  GpuSelectionMasks._(this._engine, this._masks);

  /// Compiled on [engine] off this isolate, which goes on meanwhile.
  static Future<GpuSelectionMasks> opening(GpuEngine engine) async =>
      GpuSelectionMasks._(engine, await _compiledOff(engine, _compiled));

  static Pointer<rust.SelectionMasks> _compiled(Pointer<rust.Engine> on) =>
      rust.selectionMasksNew(on);

  final GpuEngine _engine;
  final Pointer<rust.SelectionMasks> _masks;

  /// The mask of the selection [program] spells over [points] — the
  /// spelling the engine reads (`steps_of`) — on the pixel box [width] ×
  /// [height] whose top-left pixel is ([x], [y]), finished by [grow],
  /// [feather] and [antiAlias]. Kept on the GPU till it is freed or let
  /// go of; the work is submitted and nothing waits for it.
  GpuMask selection({
    required Uint32List program,
    required Float64List points,
    required int x,
    required int y,
    required int width,
    required int height,
    required int grow,
    required double feather,
    required bool antiAlias,
  }) {
    final mask = using((arena) {
      final words = arena<Uint32>(_held(program.length))
        ..asTypedList(program.length).setAll(0, program);
      return rust.selectionMaskNew(
        _masks,
        _engine._engine,
        words,
        program.length,
        _doubles(arena, points),
        points.length,
        x,
        y,
        width,
        height,
        grow,
        feather,
        antiAlias,
      );
    });
    return GpuMask._kept(_engine, mask, width * height);
  }

  /// [mask] cut by the selection [by] — a fill's range as its mark shows
  /// it under a selection: whole where both take any of the pixel, nothing
  /// elsewhere, over [mask]'s box. Kept on the GPU as [selection]'s masks
  /// are; the work is submitted and nothing waits for it. Refused where
  /// another engine made either ([_OfAnEngine]).
  GpuMask cut(GpuMask mask, GpuMask by) => GpuMask._kept(
    _engine,
    rust.selectionMaskCut(
      _masks,
      _engine._engine,
      _engine._its(mask)._mask,
      _engine._its(by)._mask,
    ),
    mask._length,
  );

  /// The AREA [program] spells over [points] on the pixel box [width] ×
  /// [height] whose top-left pixel is ([x], [y]), finished as a fill
  /// finishes what it flooded — grown [expand] generations, softened past
  /// its outline where [antiAlias] — over [parts] of the box alone, and cut
  /// into a mask for each, in their order: a part its left, top, width and
  /// height, canvas pixels. Kept on the GPU as [selection]'s masks are; the
  /// work is submitted and nothing waits for it.
  ///
  /// ⚠️Exact where [parts] hold every pixel the finish leaves any of: what
  /// lies past them is read as nothing (rust `MaskPasses::fill`).
  List<GpuMask> area({
    required Uint32List program,
    required Float64List points,
    required int x,
    required int y,
    required int width,
    required int height,
    required int expand,
    required bool antiAlias,
    required List<({int left, int top, int width, int height})> parts,
  }) => using((arena) {
    final words = arena<Uint32>(_held(program.length))
      ..asTypedList(program.length).setAll(0, program);
    final boxes = arena<Int32>(_held(parts.length * 4));
    final edges = boxes.asTypedList(parts.length * 4);
    for (final (at, part) in parts.indexed) {
      edges
        ..[at * 4] = part.left
        ..[at * 4 + 1] = part.top
        ..[at * 4 + 2] = part.width
        ..[at * 4 + 3] = part.height;
    }
    final planes = arena<Pointer<rust.MaskPlane>>(_held(parts.length));
    final made = rust.areaMasksNew(
      _masks,
      _engine._engine,
      words,
      program.length,
      _doubles(arena, points),
      points.length,
      x,
      y,
      width,
      height,
      expand,
      antiAlias,
      boxes,
      parts.length,
      planes,
    );
    if (!made) {
      throw GpuRefused(_lastError());
    }
    return [
      for (final (at, part) in parts.indexed)
        GpuMask._kept(_engine, planes[at], part.width * part.height),
    ];
  });

  /// The hard mask of the selection [program] spells over [points] on the
  /// pixel box [width] × [height] whose top-left pixel is ([x], [y]), read
  /// back as its runs: a row each, top to bottom, its selected pixels'
  /// starts and ends in turn — columns from the box's left, each end the
  /// first column past its run. Waits for the GPU.
  List<Uint32List> runs({
    required Uint32List program,
    required Float64List points,
    required int x,
    required int y,
    required int width,
    required int height,
  }) => using((arena) {
    final words = arena<Uint32>(_held(program.length))
      ..asTypedList(program.length).setAll(0, program);
    final count = arena<UintPtr>();
    final runs = rust.selectionRuns(
      _masks,
      _engine._engine,
      words,
      program.length,
      _doubles(arena, points),
      points.length,
      x,
      y,
      width,
      height,
      count,
    );
    if (runs == nullptr) {
      throw GpuRefused(_lastError());
    }
    try {
      final offsets = arena<Uint32>(height + 1);
      final ends = arena<Uint32>(_held(count.value));
      rust.selectionRunsRead(runs, offsets, ends);
      final at = offsets.asTypedList(height + 1);
      final all = Uint32List.fromList(ends.asTypedList(count.value));
      return [
        for (var row = 0; row < height; row += 1)
          Uint32List.sublistView(all, at[row], at[row + 1]),
      ];
    } finally {
      rust.selectionRunsFree(runs);
    }
  }, malloc);

  /// The bytes it keeps between its folds: the bit planes a selection is
  /// folded in, kept for the next.
  int get bytes => rust.selectionMasksBytes(_masks);

  /// Lets go of what it keeps between its folds.
  void letGo() => rust.selectionMasksLetGo(_masks);

  void free() => rust.selectionMasksFree(_masks);
}

/// The faces letters are set in (rust/src/kernels/letters/glyphs.rs): each
/// family's files, the families in the order a letter goes down them —
/// handed over a file at a time ([GpuFacesHanding]).
class GpuFaces {
  GpuFaces._(this._faces);

  final Pointer<rust.Faces> _faces;

  /// These families in the order [order] names them, each by where it
  /// stands in this one — sharing their files, and freed on its own,
  /// before these or after.
  GpuFaces ordered(List<int> order) {
    final faces = using((arena) {
      final at = arena<Uint32>(_held(order.length));
      at.asTypedList(order.length).setAll(0, order);
      return rust.facesOrdered(_faces, at, order.length);
    });
    if (faces == nullptr) {
      throw GpuRefused(_lastError());
    }
    return GpuFaces._(faces);
  }

  void free() => rust.facesFree(_faces);
}

/// [GpuFaces] being handed to the engine a file at a time: each file
/// mapped by the engine where it is a file on the device ([addAt]), else
/// copied by it as it is [add]ed — once, from where its bytes lie
/// (`gpu_engine_faces_file`) — and the faces set up when all are
/// ([done]).
///
/// ⛔A FILE AT A TIME, so the one copy each file costs can fall where it
/// is read rather than all of them in one stop (35 MB: ~12 ms on the
/// surface, a Noto Sans SC file ~11 MB of it).
///
/// ↩️Till 2026-11-14 every file was copied into a block zeroed for it
/// first, all at once, and the engine copied that: 35 MB three times over,
/// the UI stopped 50–120 ms the first time letters were set (🔬저장, the
/// surface's AOT profiler — board engine-faces-load-35-mb-on-the-ui-thread).
class GpuFacesHanding {
  GpuFacesHanding() : _handed = rust.facesHanded();

  final Pointer<rust.FacesHanded> _handed;

  /// [file], read whole, as one of family [family]'s: 0 first and each one
  /// the last's or the next, so a family's files are added together in the
  /// order its family is.
  void add(int family, Uint8List file) {
    rust.facesFile(_handed, family, file.address, file.length);
    debugFilesHanded += 1;
  }

  /// The file at [path] as one of family [family]'s, as [add] hands one —
  /// mapped by the engine, not copied: its bytes are the file's own pages,
  /// which the OS shares with whoever else maps it, and Flutter maps the
  /// app's bundled fonts too (`gpu_engine_faces_file_at`). False, and
  /// nothing handed, where the engine cannot map it: [add] its bytes then.
  ///
  /// 🗣️유저 (engine-fonts-held-twice): 「사본이나 ram에있는걸 최대한
  /// 없애고싶어서」 — 🔬공통 11-21, a Windows release run: [add]'s copy was
  /// the faces' one copy in the process, 35 MB.
  bool addAt(int family, String path) => using((arena) {
    final bytes = utf8.encode(path);
    final mapped = rust.facesFileAt(
      _handed,
      family,
      _bytes(arena, bytes),
      bytes.length,
    );
    if (mapped) {
      debugFilesHanded += 1;
    }
    return mapped;
  });

  /// Test seam: how many files have been handed ([add], [addAt]), every
  /// handing's.
  @visibleForTesting
  static int debugFilesHanded = 0;

  /// The faces of every file [add]ed — after which this hands nothing more.
  GpuFaces done() {
    final faces = rust.facesOf(_handed);
    if (faces == nullptr) {
      throw GpuRefused(_lastError());
    }
    return GpuFaces._(faces);
  }
}

/// A cluster of letters as the app's layout set it: its text, its box's
/// left and its line's baseline — 64ths of a px.
typedef GpuCluster = ({String text, int x, int y});

/// A PICTURE OF LETTERS (rust/src/kernels/letters): passes bottom to top,
/// each of runs of letters as the app's layout set them and of boxes and
/// lines, set in [GpuFaces] on the GPU into the straight RGBA8 tiles of one
/// rectangle of the grid. Where a shape stands in the layout is the six
/// floats a, b, c, d, e, f: x' = a·x + c·y + e, y' = b·x + d·y + f.
class GpuLetters {
  GpuLetters() : _letters = rust.lettersNew();

  final Pointer<rust.Lettering> _letters;

  /// Begins a pass over the ones before it: its shapes in [colour] —
  /// straight RGBA8, A<<24|B<<16|G<<8|R, its alpha the pass's strength —
  /// cut [hard] or not, filled where [outline] is 0 and else outlined that
  /// wide, 64ths of a px.
  void pass(int colour, {required bool hard, int outline = 0}) =>
      _done(rust.lettersPass(_letters, colour, hard, outline));

  /// Adds to the pass begun last a run of [clusters] in one style — [size]
  /// 64ths of a px — standing in the layout where [at] puts its own space.
  /// [weight] is a `FontWeight`'s value.
  void run(
    List<double> at, {
    required int size,
    required int weight,
    required bool italic,
    required List<GpuCluster> clusters,
  }) => using((arena) {
    final (:text, :length, :ends, :origins) = _clustered(arena, clusters);
    _done(
      rust.lettersRun(
        _letters,
        _floats(arena, _six(at)),
        size,
        weight,
        italic,
        text,
        length,
        ends,
        origins,
        clusters.length,
      ),
    );
  });

  /// Adds to the pass begun last a box or a line — [rect], [left, top,
  /// right, bottom), 64ths of a px — standing in the layout where [at] puts
  /// its own space.
  void rect(List<double> at, (int, int, int, int) rect) => using(
    (arena) => _done(
      rust.lettersRect(_letters, _floats(arena, _six(at)), _rect(arena, rect)),
    ),
  );

  /// The letters set in [faces] and laid on the grid by [toGrid] — the
  /// layout's space to the grid's —, on this isolate's thread, the CPU's
  /// work alone: the rectangle of tiles they cover — its first tile's
  /// column and row, and how many columns and rows of tiles it spans —,
  /// their covers kept for [land]. Null for letters that cover no pixel.
  ({int x0, int y0, int columns, int rows})? cover(
    GpuFaces faces,
    List<double> toGrid,
  ) => using((arena) {
    final rect = arena<Int32>(4)..asTypedList(4).fillRange(0, 4, -1);
    _done(
      rust.lettersCover(
        _letters,
        faces._faces,
        _floats(arena, _six(toGrid)),
        rect,
      ),
    );
    final [x0, y0, columns, rows] = rect.asTypedList(4).toList();
    return columns == 0
        ? null
        : (x0: x0, y0: y0, columns: columns, rows: rows);
  });

  /// Gives each tile of what was covered last ([cover]) that [asks] names
  /// — by its column and row on the grid — a fresh slot of [cel] of
  /// [pool], and hands the laying of their picture by [composite] and its
  /// putting there to the engine's thread, this isolate waiting for none
  /// of it (rust/src/kernels/letters/abi.rs, `gpu_engine_letters_land`,
  /// has why): the engine's alone, as a landing puts what it made. Each
  /// landed is [GpuChange.inked]; as many of [asks], the first, as [pool]
  /// has room for. [unput] is called where their picture was not put.
  List<GpuLanded> land(
    GpuComposite composite,
    GpuPool pool,
    int cel,
    List<GpuTileAsk> asks, {
    required void Function() unput,
  }) {
    final engine = composite._engine;
    return _landed(
      asks,
      (_, coordinates, _, places, changes) => _putsOnTheirWay.handing(
        unput,
        (number) => rust.lettersLand(
          _letters,
          engine._engine,
          engine._its(composite)._composite,
          engine._its(pool)._pool,
          cel,
          coordinates,
          asks.length,
          places,
          changes,
          _putsOnTheirWay.told,
          number,
        ),
      ),
    );
  }

  void free() => rust.lettersFree(_letters);
}

/// What is called where the picture of a land on its way was not put —
/// the letters' ([GpuLetters.land]), a stroke's ([GpuStroke.landOnItsWay])
/// —, and how the engine's thread tells this isolate whether it was.
final _putsOnTheirWay = _Told<void Function()>((_, unput, put) {
  if (!put) {
    unput();
  }
});

/// What ticks, and says whether anyone hears it.
final class _Ticks extends ChangeNotifier {
  void tick() => notifyListeners();

  bool get isHeard => hasListeners;
}

/// What a thread of the engine's tells this isolate by a number — a
/// wait ended, a copy written, a picture put — and whether it went well:
/// each [kept] till it is told, and one listener for every number of the
/// kind, [told].
///
/// 🚨It keeps its isolate for as long as one is on its way, and no longer:
/// an isolate with nothing else to do stays for what it asked — let go, it
/// ended under a wait with its readout never freed — and ends once all
/// have come. ⛔Not one listener a number: nothing is made for a number, so
/// none leaves anything to close (↩️one each, closed as its wait ended —
/// a close gone showed in no test, 2026-11-12).
///
/// ↩️Till 2026-11-18 each kind held its map and listener itself — the
/// engine's waits, a pool's stores, a readout's maps and the letters'
/// lands, four of one, the fourth added that morning (rule of three).
final class _Told<T> {
  _Told(this._then);

  /// What is done with what was [kept] under a number once it is told:
  /// the number, what was kept, and whether it went well.
  final void Function(int number, T kept, bool ok) _then;
  final Map<int, T> _waiting = {};
  int _numbered = 0;

  /// The function a thread of the engine's tells by.
  Pointer<NativeFunction<Void Function(Uint64, Bool)>> get told =>
      _listener.nativeFunction;

  late final _listener = NativeCallable<Void Function(Uint64, Bool)>.listener(
    _told,
  );

  /// [waiting] kept till its number is told: the number. Kept before it
  /// is handed over — the engine's thread may tell it before the call that
  /// handed it returns, and its word comes after this isolate's turn.
  int kept(T waiting) {
    final number = _numbered++;
    _waiting[number] = waiting;
    _listener.keepIsolateAlive = true;
    return number;
  }

  /// What [handOver] answers — how many it handed over under the number
  /// it is given, [waiting] [kept] under that number till it is told —, the
  /// number forgotten where none went: a call that handed none over, or
  /// failed (below none, or thrown), is told of by nothing
  /// (`Pool::lands_unwaited`).
  ///
  /// 🚨ONE ROAD (rule of three, 2026-11-18): a pool's store, the letters'
  /// land and a stroke's on its way each kept, handed over and forgot alike
  /// — the third came. ↩️Till then one that threw kept its number, and the
  /// isolate, for good.
  int handing(T waiting, int Function(int number) handOver) {
    final number = kept(waiting);
    var handed = 0;
    try {
      return handed = handOver(number);
    } finally {
      if (handed <= 0) {
        _waiting.remove(number);
        _listener.keepIsolateAlive = _waiting.isNotEmpty;
      }
    }
  }

  void _told(int number, bool ok) {
    final waiting = _waiting.remove(number) as T;
    _listener.keepIsolateAlive = _waiting.isNotEmpty;
    _then(number, waiting, ok);
  }
}

/// [clusters] as a run is handed them, in [arena]'s: their letters as
/// UTF-8, [length] bytes, the i-th ending at `ends[i]` and set at
/// `origins[2i]`, `origins[2i + 1]`.
({
  Pointer<Uint8> text,
  int length,
  Pointer<Uint32> ends,
  Pointer<Int32> origins,
})
_clustered(Arena arena, List<GpuCluster> clusters) {
  final text = <int>[];
  final ends = arena<Uint32>(_held(clusters.length));
  final origins = arena<Int32>(_held(2 * clusters.length));
  for (final (index, cluster) in clusters.indexed) {
    text.addAll(utf8.encode(cluster.text));
    ends[index] = text.length;
    origins[2 * index] = cluster.x;
    origins[2 * index + 1] = cluster.y;
  }
  final bytes = _bytes(arena, text);
  return (text: bytes, length: text.length, ends: ends, origins: origins);
}

/// A WORD OF A FRAME GRID'S TILE (rust/src/kernels/letters/words.rs): its
/// runs as the app's layout set them, rastered into coverage over a box
/// the app says — what the word's bake is averaged from. No GPU is asked:
/// the raster is the engine's, on the CPU, made within the call.
class GpuWord {
  GpuWord() : _word = rust.wordNew();

  final Pointer<rust.Wording> _word;

  /// Adds a run of [clusters] in one style — [size] 64ths of a px,
  /// [weight] a `FontWeight`'s value — where the word's layout set it.
  void run({
    required int size,
    required int weight,
    required bool italic,
    required List<GpuCluster> clusters,
  }) => using((arena) {
    final (:text, :length, :ends, :origins) = _clustered(arena, clusters);
    _done(
      rust.wordRun(
        _word,
        size,
        weight,
        italic,
        text,
        length,
        ends,
        origins,
        clusters.length,
      ),
    );
  });

  /// Whether every letter of the word is one some family of [faces] has:
  /// false for a word a letter of which the engine would set as an empty
  /// box, where Flutter sets it in a face of the machine's.
  bool isWholeIn(GpuFaces faces) => rust.wordWhole(_word, faces._faces);

  /// The word set in [faces] and laid by [toRaster] — its layout's space
  /// to the raster's — as coverage over [width] × [height] pixels, a byte
  /// each, row by row: ink past them cut off. Null where the engine
  /// refuses the raster — one of no pixel, or past the longest side it
  /// rasters over.
  Uint8List? raster(
    GpuFaces faces,
    List<double> toRaster, {
    required int width,
    required int height,
  }) => using((arena) {
    final count = width > 0 && height > 0 ? width * height : 0;
    final bytes = arena<Uint8>(_held(count));
    final rastered = rust.wordRaster(
      _word,
      faces._faces,
      _floats(arena, _six(toRaster)),
      width,
      height,
      bytes,
    );
    return rastered ? Uint8List.fromList(bytes.asTypedList(count)) : null;
  }, malloc);

  void free() => rust.wordFree(_word);
}

/// A word's letters as a frame grid's tile reads them: A8 coverage,
/// [alpha] row by row, [width] across and [height] down.
typedef GpuGridLetters = ({Uint8List alpha, int width, int height});

/// The side of the square atlas a frame grid's batch puts its letters on
/// (rust/src/kernels/timeline/grid `ATLAS_SIDE`), in pixels.
final int gpuGridAtlasSide = rust.gridAtlasSide();

/// WHERE A FRAME GRID'S LETTERS LIE on its batch's atlas: each word once,
/// by its key, on shelves — along a shelf from the left, a shelf as tall
/// as the tallest word on it, the next one under it. What a batch places
/// its letters by ([GpuGridBatch.lettersAt]), and where a caller with no
/// batch reads the places a fresh one would give.
final class GpuGridShelves {
  final _at = <Object, ({int x, int y})>{};

  /// Where the open shelf's next word goes, and the shelf's top and height.
  var _x = 0;
  var _y = 0;
  var _tallest = 0;

  /// Whether [key]'s letters are on the shelves.
  bool holds(Object key) => _at.containsKey(key);

  /// Where each of [words] lies, by its key — each the shelves do not hold
  /// put after the last, in order — or null where they do not all fit:
  /// none is put then.
  Map<K, ({int x, int y})>? place<K extends Object>(
    Map<K, GpuGridLetters> words,
  ) {
    var (x, y, tallest) = (_x, _y, _tallest);
    final placed = <K, ({int x, int y})>{};
    for (final MapEntry(:key, value: (:width, :height, alpha: _))
        in words.entries) {
      if (_at[key] case final at?) {
        placed[key] = at;
        continue;
      }
      if (x + width > gpuGridAtlasSide) {
        (x, y, tallest) = (0, y + tallest, 0);
      }
      if (width > gpuGridAtlasSide || y + height > gpuGridAtlasSide) {
        return null;
      }
      placed[key] = (x: x, y: y);
      x += width;
      tallest = height > tallest ? height : tallest;
    }
    _at.addAll(placed);
    _x = x;
    _y = y;
    _tallest = tallest;
    return placed;
  }

  /// Nothing on the shelves: the next word goes top left.
  void clear() {
    _at.clear();
    _x = 0;
    _y = 0;
    _tallest = 0;
  }
}

/// THE FRAME GRID'S BATCH (rust/src/kernels/timeline/grid): a frame's
/// tiles — each an op stream, `TimelineGridTileOpWriter`'s words — drawn
/// into pictures the engine keeps, and its sounds' waves laid over them,
/// for the view's screen to lay. What it is asked is held till it is
/// flushed, then made, drawn and laid on one trip to the engine and one
/// submit: the first time one of its pictures is laid
/// ([GpuGridLay.lay]) or read ([GpuGridPicture.read]), or its atlas is full
/// ([lettersAt]), or [flush] is called.
///
/// ⛔WHAT DATA CAN REACH IS ANSWERED WHERE IT IS ASKED, a tile at a time: a
/// picture past the device's side ([picture]) and words past the atlas
/// ([lettersAt]) are answered with none, so a flush refuses its batch only
/// for a stream or a view the writer got wrong, or where the device fails
/// (🗣️관제 2026-11-15 07:0x, a-grid-row-paints-its-cells-on-a-canvas-
/// beside-its-tiles: 「묶음 통째 거절이 남는 길은 작성기 버그뿐」 — a whole
/// frame's grid stood where one tile had).
///
/// ↩️A tile and a sound each were a trip and a submit of their own
/// (`GpuGrid.draw`, `GpuWave.draw`), a picture made on a trip of its own
/// and a tile's letters on an atlas made for it alone
/// (a-grid-row-paints-its-cells-on-a-canvas-beside-its-tiles-Q2, 유저
/// 2026-11-15 「(라) 엔진의 타일당 준비를 걷어내고 다시 잰다」): 🔬a cold
/// tile's 3.3 ms on the main PC, of which the GPU's was 6–10 µs
/// (measure-cold-tiles, 11-15).
class GpuGridBatch {
  /// The passes on [engine], compiled for the pictures it draws.
  GpuGridBatch(GpuEngine engine)
    : this._(engine, _grid(engine._engine), _wave(engine._engine));

  /// Compiled on [engine] off this isolate, which goes on meanwhile.
  static Future<GpuGridBatch> opening(GpuEngine engine) async =>
      GpuGridBatch._(
        engine,
        await _compiledOff(engine, _grid),
        await _compiledOff(engine, _wave),
      );

  static Pointer<rust.Grid> _grid(Pointer<rust.Engine> on) =>
      rust.gridNew(on);

  static Pointer<rust.Wave> _wave(Pointer<rust.Engine> on) =>
      rust.waveNew(on);

  GpuGridBatch._(this._engine, this._tiles, this._sounds);

  final GpuEngine _engine;
  final Pointer<rust.Grid> _tiles;
  final Pointer<rust.Wave> _sounds;
  final _shelves = GpuGridShelves();

  /// The longest side of a picture the device makes.
  late final int mostSide = rust.gridMostSide(_tiles);

  /// What the next flush makes, puts, draws and lays, in order.
  final _pending = <GpuGridPicture>[];
  final _puts = <({int x, int y, GpuGridLetters letters})>[];
  final _drawn = <(GpuGridPicture, Int32List)>[];
  final _waved = <(GpuGridPicture, GpuWavePeaks, GpuWaveView)>[];

  /// How many flushes it has sent the engine.
  int get debugFlushes => _flushes;
  var _flushes = 0;

  /// A clear picture [width] × [height], made at the next flush — or null,
  /// nothing held, for a side past [mostSide]: the caller answers for that
  /// tile. Throws for a side of none.
  GpuGridPicture? picture(int width, int height) {
    if (width < 1 || height < 1) {
      throw ArgumentError('a grid tile $width × $height');
    }
    if (width > mostSide || height > mostSide) {
      return null;
    }
    final picture = GpuGridPicture._(this, width, height);
    _pending.add(picture);
    return picture;
  }

  /// Where each of [words] lies on the atlas, by its key, for a GLYPH op
  /// to read it — put there at the next flush the first time it is asked
  /// for. Where the atlas has no room for them all, what the batch holds is
  /// flushed and the atlas starts over; null, nothing put or flushed, for
  /// more than an empty atlas holds ([gpuGridAtlasSide]): the caller
  /// answers for that tile. Throws for letters whose bytes are not their
  /// box's.
  Map<K, ({int x, int y})>? lettersAt<K extends Object>(
    Map<K, GpuGridLetters> words,
  ) {
    for (final (:alpha, :width, :height) in words.values) {
      if (alpha.length != width * height) {
        // The engine reads width × height bytes of them.
        throw ArgumentError(
          'letters $width × $height of ${alpha.length} bytes',
        );
      }
    }
    var fresh = [
      for (final key in words.keys)
        if (!_shelves.holds(key)) key,
    ];
    var placed = _shelves.place(words);
    if (placed == null) {
      if (GpuGridShelves().place(words) == null) {
        return null;
      }
      flush();
      _shelves.clear();
      fresh = [...words.keys];
      placed = _shelves.place(words)!;
    }
    for (final key in fresh) {
      final (:x, :y) = placed[key]!;
      _puts.add((x: x, y: y, letters: words[key]!));
    }
    return placed;
  }

  /// Draws [ops] into [picture] over clear at the next flush, its letters
  /// read where its GLYPH ops say ([lettersAt]) — the stream as it stands
  /// then.
  void draw(GpuGridPicture picture, Int32List ops) =>
      _drawn.add((_engine._its(picture), ops));

  /// Lays [peaks] over what [picture] holds as [view] shows them at the
  /// next flush, after every tile it draws.
  void wave(GpuGridPicture picture, GpuWavePeaks peaks, GpuWaveView view) =>
      _waved.add((_engine._its(picture), _engine._its(peaks), view));

  /// Makes, puts, draws and lays what it holds: one trip to the engine for
  /// the pictures, one for the rest, and one submit — not waited for: what
  /// reads a picture after comes after it on the GPU. Throws for a stream
  /// or a view the passes refuse, or a picture the device fails to make:
  /// nothing of the batch is drawn then, it holds nothing after, and the
  /// words it is asked for next are put again.
  void flush() {
    if (_pending.isEmpty &&
        _puts.isEmpty &&
        _drawn.isEmpty &&
        _waved.isEmpty) {
      return;
    }
    final pending = [..._pending];
    final puts = [..._puts];
    final drawn = [..._drawn];
    final waved = [..._waved];
    _pending.clear();
    _puts.clear();
    _drawn.clear();
    _waved.clear();
    _flushes += 1;
    try {
      using((arena) {
        final made = arena<Pointer<rust.GridPicture>>(_held(pending.length));
        final sizes = arena<Uint32>(_held(2 * pending.length));
        for (final (index, picture) in pending.indexed) {
          sizes[2 * index] = picture.width;
          sizes[2 * index + 1] = picture.height;
        }
        _done(
          rust.gridPicturesNew(_engine._engine, sizes, pending.length, made),
        );
        for (final (index, picture) in pending.indexed) {
          _engine._its(picture)._made = made[index];
        }
        final boxes = arena<Uint32>(_held(4 * puts.length));
        final length = puts.fold(
          0,
          (sum, put) => sum + put.letters.alpha.length,
        );
        final bytes = arena<Uint8>(_held(length));
        var end = 0;
        for (final (index, (:x, :y, :letters)) in puts.indexed) {
          boxes
              .asTypedList(4 * puts.length)
              .setAll(4 * index, [x, y, letters.width, letters.height]);
          bytes.asTypedList(length).setAll(end, letters.alpha);
          end += letters.alpha.length;
        }
        final tiles = arena<Pointer<rust.GridPicture>>(_held(drawn.length));
        final ends = arena<Uint32>(_held(drawn.length));
        final words = drawn.fold(0, (sum, tile) => sum + tile.$2.length);
        final stream = arena<Int32>(_held(words));
        end = 0;
        for (final (index, (picture, ops)) in drawn.indexed) {
          tiles[index] = _engine._its(picture)._picture;
          stream.asTypedList(words).setAll(end, ops);
          end += ops.length;
          ends[index] = end;
        }
        final under = arena<Pointer<rust.GridPicture>>(_held(waved.length));
        final peaks = arena<Pointer<rust.WavePeaks>>(_held(waved.length));
        final views = arena<Int32>(_held(11 * waved.length));
        for (final (index, (picture, sound, view)) in waved.indexed) {
          under[index] = _engine._its(picture)._picture;
          peaks[index] = _engine._its(sound)._peaks;
          views.asTypedList(11 * waved.length).setAll(11 * index, [
            view.along0,
            view.length,
            if (view.vertical) 1 else 0,
            view.frameQ8,
            view.fpsNumerator,
            view.fpsDenominator,
            view.bucketsPerSecond,
            view.leadingFrames,
            view.acrossQ8,
            view.gainQ16,
            view.rgba,
          ]);
        }
        final flushed = rust.gridFlush(
          _tiles,
          _sounds,
          _engine._engine,
          boxes,
          puts.length,
          bytes,
          tiles,
          ends,
          drawn.length,
          stream,
          under,
          peaks,
          views,
          waved.length,
        );
        // Their peaks were read on the engine's thread: none is let go of
        // before (a list on the stack keeps nothing alive — [Finalizable]
        // holds a variable).
        for (final (_, sound, _) in waved) {
          _reachable(sound);
        }
        _done(flushed);
      });
    } on Object {
      // Its letters may not be on the atlas: every word is put again.
      _shelves.clear();
      rethrow;
    }
  }

  /// The bytes it keeps between its flushes — its letters' atlas, its
  /// planes, the waves' unders — for the memory census.
  int get keptBytes => rust.gridKeptBytes(_tiles, _sounds);

  /// What it keeps between its flushes, let go of once what it holds is
  /// flushed: the next makes its own, and puts its letters again.
  void letGoKept() {
    flush();
    rust.gridLetGoKept(_tiles, _sounds, _engine._engine);
    _shelves.clear();
  }

  /// [picture] freed: nothing of it is made, drawn or laid after.
  void _drop(GpuGridPicture picture) {
    _pending.remove(picture);
    _drawn.removeWhere((drawn) => identical(drawn.$1, picture));
    _waved.removeWhere((waved) => identical(waved.$1, picture));
  }

  void free() {
    rust.gridFree(_tiles);
    rust.waveFree(_sounds);
  }
}

/// A frame grid's tile as the engine keeps it: [width] × [height] pixels,
/// straight, asked of a batch ([GpuGridBatch.picture]) and made at its
/// flush, drawn by it and laid by [GpuGridLay.lay].
class GpuGridPicture implements _OfAnEngine {
  GpuGridPicture._(this._batch, this.width, this.height);

  final GpuGridBatch _batch;
  final int width;
  final int height;

  /// Its picture on the engine, once its batch has made it.
  Pointer<rust.GridPicture>? _made;

  @override
  GpuEngine get _engine => _batch._engine;

  /// Its picture on the engine: made by flushing its batch where it is not
  /// yet. ⛔No pass is handed a picture its batch holds unmade.
  Pointer<rust.GridPicture> get _picture {
    if (_made == null) {
      _batch.flush();
    }
    return _made ?? (throw GpuRefused('a grid tile its batch did not make'));
  }

  /// Its pixels once the GPU is done — straight RGBA8, row by row.
  Uint8List read() => using((arena) {
    final count = width * height * 4;
    final bytes = arena<Uint8>(_held(count));
    // ⚠️No test reaches the throw: a read fails only where the device does.
    if (!rust.gridPictureRead(_engine._engine, _picture, bytes, count)) {
      throw GpuRefused(_lastError());
    }
    return Uint8List.fromList(bytes.asTypedList(count));
  });

  void free() {
    _batch._drop(this);
    if (_made case final made?) {
      rust.gridPictureFree(made);
    }
    _made = null;
  }
}

/// [held] kept alive up to this call ([Finalizable]'s rule).
void _reachable(Finalizable held) {}

/// A tile laid on a view's screen: the part [from] of its [picture], in its
/// pixels, onto the part [onto] of the screen, in the screen's — each
/// (left, top, right, bottom).
typedef GpuGridLaid = ({
  GpuGridPicture picture,
  (double, double, double, double) from,
  (double, double, double, double) onto,
});

/// THE VIEW'S SCREEN OF FRAME GRID TILES (rust/src/kernels/timeline/grid/
/// lay.rs): the tiles a sheet's rows lay, onto what the view shows.
class GpuGridLay {
  /// The pass on [engine], compiled for a screen where it first lays onto
  /// one.
  GpuGridLay(GpuEngine engine)
    : this._(engine, rust.gridLayNew(engine._engine));

  /// The pass compiled on [engine], off this isolate, which goes on
  /// meanwhile, for a screen of BGRA texels where [bgra], of RGBA else —
  /// [GpuEngine.surface]'s; a [GpuWindow] is RGBA.
  static Future<GpuGridLay> opening(
    GpuEngine engine, {
    required bool bgra,
  }) async => GpuGridLay._(engine, await _compiledOff(engine, _ready(bgra)));

  /// The pass, ready for a screen as [bgra] says — made here, of a bool
  /// alone, for what crosses to the other isolate.
  static Pointer<rust.GridLay> Function(Pointer<rust.Engine>) _ready(
    bool bgra,
  ) => (on) {
    final lay = rust.gridLayNew(on);
    rust.gridLayReady(lay, on, bgra);
    return lay;
  };

  GpuGridLay._(this._engine, this._lay);

  final GpuEngine _engine;
  final Pointer<rust.GridLay> _lay;

  /// The pixels [rect] of [target] — (left, top, right, bottom) — clear,
  /// and each of [laid] over the pixels whose centres its `onto` holds, a
  /// later one over an earlier; submits the work, waiting for none of it
  /// ([GpuEngine.done]). Throws for a rect past the target and a tile laid
  /// from past its picture or onto no box.
  void lay(
    GpuTarget target,
    (int, int, int, int) rect,
    List<GpuGridLaid> laid,
  ) => using((arena) {
    final (left, top, right, bottom) = rect;
    final edges = arena<Uint32>(4)
      ..asTypedList(4).setAll(0, [left, top, right, bottom]);
    final pictures = arena<Pointer<rust.GridPicture>>(_held(laid.length));
    final boxes = arena<Double>(_held(8 * laid.length));
    for (final (index, (:picture, :from, :onto)) in laid.indexed) {
      pictures[index] = _engine._its(picture)._picture;
      final (x0, y0, x1, y1) = from;
      final (u0, v0, u1, v1) = onto;
      boxes
          .asTypedList(8 * laid.length)
          .setAll(8 * index, [x0, y0, x1, y1, u0, v0, u1, v1]);
    }
    _done(
      rust.gridLay(
        _lay,
        _engine._engine,
        _engine._its(target)._texture,
        edges,
        pictures,
        boxes,
        laid.length,
      ),
    );
  });

  void free() => rust.gridLayFree(_lay);
}

/// Where a strip shows its sound, in the integers the waveform pass takes
/// (rust/src/kernels/timeline/wave `WaveView`): the strip pixel the
/// picture's first column (or row, running down) is; how many pixels long
/// the strip is, a column before its first or past its last showing what
/// the picture holds; pixels a frame, q8;
/// frames a second as a fraction; the peaks' buckets a second; frames into
/// the file before the strip starts; the strip's extent across, q8; the
/// gain, q16 (65536 is 1); the band's straight colour, r | g<<8 | b<<16 |
/// a<<24.
typedef GpuWaveView = ({
  int along0,
  int length,
  bool vertical,
  int frameQ8,
  int fpsNumerator,
  int fpsDenominator,
  int bucketsPerSecond,
  int leadingFrames,
  int acrossQ8,
  int gainQ16,
  int rgba,
});

/// A sound's peaks as the engine keeps them for [GpuGridBatch.wave]:
/// [lanes] lanes of [buckets] q16 peaks — round(min(|s|, 1) · 65535) —
/// each, let go of with the object, as a stamp's picture is
/// ([GpuStampPicture]): they are the sound's as long as the sound is.
final class GpuWavePeaks implements Finalizable, _OfAnEngine {
  /// [peaks]' lanes, all of one length, uploaded once. Throws for none, an
  /// empty one, lanes of different lengths, or more than the pass takes.
  factory GpuWavePeaks(GpuEngine engine, List<Uint16List> peaks) =>
      using((arena) {
        final buckets = peaks.isEmpty ? 0 : peaks.first.length;
        final count = peaks.length * buckets;
        final words = arena<Uint16>(_held(count));
        final all = words.asTypedList(_held(count));
        for (final (lane, values) in peaks.indexed) {
          if (values.length != buckets) {
            throw ArgumentError('lanes of ${values.length} and $buckets');
          }
          all.setAll(lane * buckets, values);
        }
        final made = rust.wavePeaksNew(
          engine._engine,
          words,
          peaks.length,
          buckets,
        );
        if (made == nullptr) {
          throw GpuRefused(_lastError());
        }
        final kept = GpuWavePeaks._(engine, made, peaks.length, buckets);
        // Its table's bytes (rust WavePeaks::new): a level a doubling of
        // the buckets it holds the most of.
        _freed.attach(
          kept,
          made.cast(),
          externalSize: count * buckets.bitLength * 2,
        );
        return kept;
      });

  GpuWavePeaks._(this._engine, this._peaks, this.lanes, this.buckets);

  @override
  final GpuEngine _engine;
  final Pointer<rust.WavePeaks> _peaks;
  final int lanes;
  final int buckets;

  static final NativeFinalizer _freed = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<rust.WavePeaks>)>>(
      rust.wavePeaksFree,
    ).cast(),
  );
}

/// [argb] — a `Color`'s, A<<24|R<<16|G<<8|B — as the engine's colours
/// are: straight RGBA8, A<<24|B<<16|G<<8|R.
int gpuColourOf(int argb) =>
    argb & 0xFF00FF00 | (argb >> 16 & 0xFF) | (argb & 0xFF) << 16;

/// What a mask is laid under ([GpuStampLanding.landMask]): a colour, or a
/// gradient's colour at each pixel — rust/src/kernels/dab/abi.rs's
/// `PaintOf`, a tag and the numbers it reads.
sealed class GpuPaint {
  const GpuPaint();

  List<double> get _numbers;
}

/// [argb] — a `Color`'s — its alpha unread: a mask's byte is the alpha.
final class GpuColour extends GpuPaint {
  const GpuColour(this.argb);

  final int argb;

  @override
  List<double> get _numbers => [0, gpuColourOf(argb).toDouble()];
}

/// The shapes of a [GpuGradient].
enum GpuGradientShape { line, circle }

/// [start] at [from], [end] at [to] and past it — and, along a line,
/// [start] behind [from] —, canvas pixels; each colour a `Color`'s ARGB,
/// straight.
final class GpuGradient extends GpuPaint {
  const GpuGradient({
    required this.shape,
    required this.from,
    required this.to,
    required this.start,
    required this.end,
  });

  final GpuGradientShape shape;
  final (double, double) from;
  final (double, double) to;
  final int start;
  final int end;

  @override
  List<double> get _numbers => [
    1,
    switch (shape) {
      GpuGradientShape.line => 0,
      GpuGradientShape.circle => 1,
    },
    from.$1,
    from.$2,
    to.$1,
    to.$2,
    gpuColourOf(start).toDouble(),
    gpuColourOf(end).toDouble(),
  ];
}

/// [values] as floats of [arena]'s.
Pointer<Float> _floats(Arena arena, List<double> values) =>
    arena<Float>(_held(values.length))
      ..asTypedList(values.length).setAll(0, values);

/// [affine], checked to be the six floats a placement is.
List<double> _six(List<double> affine) {
  if (affine.length != 6) {
    throw ArgumentError('a placement of ${affine.length}, not 6');
  }
  return affine;
}

/// What a C entry answering whether it did answered: nothing, or its last
/// error thrown.
void _done(bool done) {
  if (!done) {
    throw GpuRefused(_lastError());
  }
}

/// The walked tile whose words start at [at] of [words].
GpuTileInk _walkedAt(Int32List words, int at) {
  final [column, row, left, top, right, bottom] = words.sublist(
    at,
    at + _tileInkWords,
  );
  return (
    column: column,
    row: row,
    box: right > left
        ? (left: left, top: top, right: right, bottom: bottom)
        : null,
  );
}

/// The closed contours of the pixels [ends] hold — row `r`'s
/// `ends[offsets[r] .. offsets[r + 1]]`, a start and an end in turn,
/// columns from the left of a box [width] wide — on the pixel grid, walked
/// by the engine (rust/src/kernels/mask/contours.rs): contour `c`'s points
/// are `points[2 * starts[c] .. 2 * starts[c + 1]]`, a column and a line in
/// turn from the box's top-left corner, in the order the scan met them. No
/// device is asked. Throws [GpuRefused] where the runs are none of such a
/// box.
({Uint32List starts, Int32List points}) contoursOfRuns({
  required Uint32List offsets,
  required Uint32List ends,
  required int width,
}) => using((arena) {
  final rows = offsets.length - 1;
  final counts = arena<UintPtr>(2);
  final offsetsAt = arena<Uint32>(offsets.length)
    ..asTypedList(offsets.length).setAll(0, offsets);
  final endsAt = arena<Uint32>(_held(ends.length))
    ..asTypedList(ends.length).setAll(0, ends);
  final contours = rust.runContours(
    offsetsAt,
    rows,
    endsAt,
    ends.length,
    width,
    counts,
  );
  if (contours == nullptr) {
    throw GpuRefused(_lastError());
  }
  try {
    final (lines, points) = (counts[0], counts[1]);
    final startsAt = arena<Uint32>(lines + 1);
    final pointsAt = arena<Int32>(_held(2 * points));
    rust.runContoursRead(contours, startsAt, pointsAt);
    return (
      starts: Uint32List.fromList(startsAt.asTypedList(lines + 1)),
      points: Int32List.fromList(pointsAt.asTypedList(2 * points)),
    );
  } finally {
    rust.runContoursFree(contours);
  }
}, malloc);

/// The fingerprint of [bytes] by the engine's own code — for bytes read off
/// Flutter's screen, so they are compared as the GPU's are.
int fingerprintBytes(Uint8List bytes) => using((arena) {
  final buffer = _bytes(arena, bytes);
  return rust.fingerprintBytes(buffer, bytes.length);
});

/// [running] with the first [length] bytes of [bytes] folded in — the CRC
/// [fingerprintBytes] takes, kept as a chunked one is: inverted, starting
/// from `0xFFFFFFFF`. Read where the bytes lie, without a copy.
///
/// ⚠️A slice at a time ([_crcSlice]): a leaf call holds its isolate out of
/// every safepoint while it runs, so one call over a whole file would hold
/// a collection of the isolate group — the UI's among it — for as long.
int crc32Update(int running, Uint8List bytes, int length) {
  var folded = running;
  for (var at = 0; at < length; at += _crcSlice) {
    final slice = Uint8List.sublistView(
      bytes,
      at,
      at + _crcSlice < length ? at + _crcSlice : length,
    );
    folded = rust.crc32Update(folded, slice.address, slice.length);
  }
  return folded;
}

/// The most [crc32Update] reads in one leaf call: a millisecond's worth,
/// well under a frame, at a gigabyte a second.
const int _crcSlice = 1 << 20;

/// A Flutter texture the engine presents into: a SurfaceProducer's window,
/// whose images Flutter shows without a copy (Android). Drawn on and
/// presented with no wait for the engine's thread
/// (rust/src/platform/android.rs, `Window`).
class GpuWindow extends GpuTarget {
  GpuWindow._(super._engine, this._window, this.textureId);

  final Pointer<rust.Window> _window;

  /// What a `Texture` widget shows the window by.
  final int textureId;

  /// What the kernels write for the window, one texture for its life —
  /// [present] shows what a kernel wrote there.
  @override
  Pointer<rust.Texture> get _texture => rust.windowTarget(_window);

  /// Hands what a kernel last wrote ([fill], [GpuScreen.show]) to
  /// Flutter: copied onto the window's next image and put up once the GPU
  /// has finished the copy, this isolate waiting for none of it. Asked
  /// once the GPU has finished what was written ([GpuEngine.done]), as a
  /// screen's frame is (`ScreenTexture.present`); where it fails, the
  /// next done fails by it.
  void present() => rust.windowPresent(_engine._engine, _window);

  /// Frees the swapchain, then Flutter's producer: the window it presents
  /// into must outlive it.
  Future<void> free() async {
    rust.windowFree(_window);
    await _plugin.invokeMethod<void>('release', {'textureId': textureId});
  }
}

/// A Flutter external texture that shows [front], or [back] once
/// [show] picks slot 1 — Windows', iOS', macOS' and Linux' way to the
/// screen: the engine makes the texture, Flutter shows it.
class SharedTexture {
  SharedTexture._(this.id);

  factory SharedTexture.register(GpuSurface front, {GpuSurface? back}) {
    final id = shim.textureRegister(
      front._handle,
      back?._handle ?? nullptr,
      front.width,
      front.height,
      front.bgra,
    );
    if (id < 0) {
      throw GpuRefused('Flutter refused the texture');
    }
    return SharedTexture._(id);
  }

  final int id;

  /// Shows slot 0 (front) or 1 (back) on the next frame.
  bool show(int slot) => shim.textureShow(id, slot);

  /// Flutter must no longer show the texture: on Linux nothing tells the
  /// plugin when Flutter stops drawing it (linux/gpu_engine_plugin.cc).
  void unregister() => shim.textureUnregister(id);
}

/// How a plugin's value — four doubles a parameter — becomes the words it
/// reads; its index is the engine's code (rust/src/kernels/plugin/abi.rs:
/// WHOLE · FIXED · CHANNELS).
enum GpuPluginValue {
  /// A whole number: a menu's choice, a checkbox's 0 or 1, a layer's slot
  /// or -1.
  whole,

  /// Q.16: a number, an angle, a length in pixels, a point's canvas pixels.
  fixed,

  /// 16 bits a channel: a colour's four, each on 0..=1.
  channels,
}

/// What a plugin is asked with: its values, four doubles a parameter each
/// read as its kind says, and the moment — the frame's number, its time in
/// seconds, the frames a second and the output pixels a canvas pixel.
typedef GpuPluginAsked = ({
  Float64List values,
  List<GpuPluginValue> kinds,
  int frame,
  double time,
  double rate,
  double scale,
});

/// A GPU fx plugin the device compiled (rust/src/kernels/plugin/abi.rs):
/// asked its reach on the CPU, run over a picture on the device. Each
/// invocation of a run is cut once it spends its share — a count of the
/// plugin's instructions, the same on every device, each pixel's its own
/// (🗣️an-endless-plugin-stalls-the-app-Q19).
class GpuPlugin {
  GpuPlugin._(this._engine, this._plugin)
    : readsTheMoment = rust.pluginReadsTheMoment(_plugin);

  /// [source], the plugin's WGSL, checked, counted and compiled on
  /// [engine] — or the refusal's words thrown. Where [cut] is false the
  /// device compiles it with no count, so no run of it is cut on the
  /// device (🗣️-Q18 「설정에 『끊지 않음』」).
  factory GpuPlugin.open(GpuEngine engine, String source, {bool cut = true}) =>
      GpuPlugin._(engine, _openOf(utf8.encode(source), cut)(engine._engine));

  /// [GpuPlugin.open] off this isolate, which goes on meanwhile — the
  /// refusal's words thrown as it ends. 🔬The check and the count alone
  /// (fx_wgsl) took 79 ms of a plugin of 2,000 statements and 934 ms of
  /// one of 8,000, and the device's compile 0.7–11.7 s more (Surface Pro
  /// 11, 11-08 · 11-12): an-endless-plugin-stalls-the-app A5.
  static Future<GpuPlugin> opening(
    GpuEngine engine,
    String source, {
    bool cut = true,
  }) async => GpuPlugin._(
    engine,
    await _compiledOff(engine, _openOf(utf8.encode(source), cut)),
  );

  /// The open of [source]'s bytes, as [cut] says, on the engine it is
  /// handed: made of plain values, so it crosses to the isolate that
  /// compiles ([_compiledOff]).
  static Pointer<rust.Plugin> Function(Pointer<rust.Engine> on) _openOf(
    Uint8List source,
    bool cut,
  ) => (on) => using((arena) {
    final at = _bytes(arena, source);
    final plugin = rust.pluginOpen(on, at, source.length, cut);
    if (plugin == nullptr) {
      throw GpuRefused(_lastError());
    }
    return plugin;
  });

  final GpuEngine _engine;
  final Pointer<rust.Plugin> _plugin;

  /// Whether the plugin reads the moment — the frame's number or its time
  /// (fx_wgsl's `Kernel::reads_the_moment`): one that does not draws the
  /// same picture of the same values at every frame. Read as it opens.
  final bool readsTheMoment;

  /// It as any isolate runs it over [read] ([GpuPluginRenderer]) — for as
  /// long as neither is freed. Refused where another engine made [read]
  /// ([_OfAnEngine]): the worker's job names both by their addresses, and
  /// this is where they are asked of the engine it is on.
  GpuPluginRenderer rendererOver(GpuChainRead read) => GpuPluginRenderer._(
    _plugin.address,
    _engine._engine.address,
    _engine._its(read)._read.address,
  );

  /// What [run] of it made ([GpuPluginRenderer.renderRead]), taken in hand
  /// on the isolate that lands it.
  GpuPluginMade made(GpuPluginRun run) => GpuPluginMade._(_engine, run);

  /// How far past its input the plugin reaches, in output pixels, for
  /// [asked] — spending no more than [share] — or why not thrown: a value
  /// past what the plugin reads, or the reach cut.
  int reach(GpuPluginAsked asked, {required int share}) => using((arena) {
    _whole(asked);
    return _checked(
      rust.pluginReach(
        _plugin,
        _doubles(arena, asked.values),
        _kinds(arena, asked.kinds),
        asked.kinds.length,
        _moment(arena, asked),
        share,
      ),
    );
  });

  /// Throws where [asked] has other than four values a kind: the engine
  /// reads as many as the kinds say.
  static void _whole(GpuPluginAsked asked) {
    if (asked.values.length != 4 * asked.kinds.length) {
      throw ArgumentError(
        '${asked.values.length} values for ${asked.kinds.length} kinds',
      );
    }
  }

  static Pointer<Uint32> _kinds(Arena arena, List<GpuPluginValue> kinds) =>
      arena<Uint32>(_held(kinds.length))
        ..asTypedList(kinds.length).setAll(0, [
          for (final kind in kinds) kind.index,
        ]);

  static Pointer<Double> _moment(Arena arena, GpuPluginAsked asked) =>
      _doubles(arena, [
        asked.frame.toDouble(),
        asked.time,
        asked.rate,
        asked.scale,
      ]);

  /// Lets the compiled plugin go; it is asked nothing after.
  void free() => rust.pluginFree(_plugin);
}

/// A [GpuPlugin] as any isolate runs it over what a chain kept for it
/// ([GpuPlugin.rendererOver]): plain numbers, the plugin's address, its
/// engine's and the read's, so it crosses to a worker — where the waits of
/// a run are that worker's, not the asker's ([debugWaitsHere]).
final class GpuPluginRenderer {
  const GpuPluginRenderer._(this._plugin, this._engine, this._read);

  final int _plugin;
  final int _engine;
  final int _read;

  /// The plugin's picture over what its read kept of a chain — its tiles,
  /// and its rows' as the layers its layer values name, by slot — at
  /// [picture], its place in the plug-in's pixels (the paper's), which lie
  /// [at] from the tiles' grid; with [asked], each pixel spending no more
  /// than [share]: the chain's rectangle of tiles on the device, clear
  /// past the picture and wherever its alpha is 0 — for the isolate that
  /// lands it ([GpuPlugin.made]) — or why not thrown: a value past what
  /// the plugin reads, a side below 0, no plan ran through the read, the
  /// run cut, or the device failed. A plugin opened not to be cut runs
  /// whole, in chunks sized as [share]'s are. ⚠️Waits for the GPU, a chunk
  /// at a time.
  GpuPluginRun renderRead(
    ({int left, int top, int width, int height}) picture,
    (int, int) at,
    GpuPluginAsked asked, {
    required int share,
  }) => using((arena) {
    GpuPlugin._whole(asked);
    final (:left, :top, :width, :height) = picture;
    final place = arena<Int32>(4)
      ..asTypedList(4).setAll(0, [left, top, width, height]);
    final (dx, dy) = at;
    final shift = arena<Int32>(2)..asTypedList(2).setAll(0, [dx, dy]);
    final rect = arena<Int32>(4);
    final made = rust.pluginRenderRead(
      Pointer.fromAddress(_plugin),
      Pointer.fromAddress(_engine),
      Pointer.fromAddress(_read),
      place,
      shift,
      _doubles(arena, asked.values),
      GpuPlugin._kinds(arena, asked.kinds),
      asked.kinds.length,
      GpuPlugin._moment(arena, asked),
      share,
      rect,
    );
    if (made == nullptr) {
      throw GpuRefused(_lastError());
    }
    final [x0, y0, columns, rows] = rect.asTypedList(4);
    return (
      made: made.address,
      rect: (x0: x0, y0: y0, columns: columns, rows: rows),
    );
  });
}

/// What a plug-in's run made ([GpuPluginRenderer.renderRead]) as plain
/// numbers, so it crosses back from the worker: the address of what it
/// made, and its rectangle of tiles.
typedef GpuPluginRun = ({
  int made,
  ({int x0, int y0, int columns, int rows}) rect,
});

/// What a plug-in made over a chain's tiles: the straight RGBA8 tiles of
/// [rect] — the chain's rectangle, its first tile's column and row, and how
/// many columns and rows of tiles it spans — on the GPU.
class GpuPluginMade {
  GpuPluginMade._(this._engine, GpuPluginRun run)
    : _made = Pointer.fromAddress(run.made),
      rect = run.rect;

  final GpuEngine _engine;
  final Pointer<rust.PluginMade> _made;
  final ({int x0, int y0, int columns, int rows}) rect;

  /// The engine that made it — what the app asks before it lands it
  /// (`isTheAppsEngine`): what an engine the app let go made lands nowhere.
  GpuEngine get engine => _engine;

  /// Puts each of its tiles [asks] names — by their column and row on the
  /// grid, in [rect] — in a fresh slot of [cel] of [pool], as a landing
  /// puts what it made: the engine's alone, with no wait for the GPU. Each
  /// landed is [GpuChange.inked]. As many of [asks], the first, as [pool]
  /// has room for.
  List<GpuLanded> land(GpuPool pool, int cel, List<GpuTileAsk> asks) =>
      _landed(
        asks,
        (_, coordinates, _, places, changes) => rust.pluginMadeLand(
          _engine._engine,
          _made,
          _engine._its(pool)._pool,
          cel,
          coordinates,
          asks.length,
          places,
          changes,
        ),
      );

  void free() => rust.pluginMadeFree(_made);
}
