import 'dart:ui' show RootIsolateToken;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:gpu_engine/gpu_engine.dart';

import 'gpu_adapter_choice.dart';

/// The app's one GPU engine, opened the first time anything asks — so a
/// test file that never asks opens no device (보드/인프라 2026-11-07: 0.6–1.2
/// s a device, eighteen test files at once on the machine's line) — on the
/// adapter [debugGpuAdapterChoice] names. ⛔No fallback: a test that needs
/// the engine and gets none fails.
// The app opens it after its first frame ([openAppGpuEngine], main.dart),
// for the frame grids' tiles (grid-on-the-engine ⑤); ⏳the tile ledger
// (`EngineTileLedger.instance`) asks once the screen asks it
// (screen-on-the-engine c6).
GpuEngine get appGpuEngine => _engine ??= _opener()();
GpuEngine? _engine;

/// Whether this isolate can have [appGpuEngine]: a worker cannot — the
/// engine, and the tiles its pool holds, are the main isolate's.
bool get appGpuEngineIsHere => RootIsolateToken.instance != null;

/// A set of kernels on [appGpuEngine], one for the app: compiled here the
/// first time anything asks, if [warm] has not got there first.
final class AppKernels<T extends Object> {
  AppKernels(this._here, this._off, this._free);

  final T Function(GpuEngine) _here;
  final Future<T> Function(GpuEngine) _off;
  final void Function(T) _free;

  T? _kept;

  T get kept => _kept ??= _here(appGpuEngine);

  /// [kept] where it has been compiled, null till then.
  T? get compiled => _kept;

  /// [kept] compiled off this isolate, at once where it is compiled already:
  /// ahead of a first use that would otherwise wait with the app frozen.
  Future<T> warm() async {
    final made = _kept ?? await _off(appGpuEngine);
    // Asked for the other way while this compiled: the app keeps one.
    final kept = _kept ??= made;
    if (!identical(kept, made)) {
      _free(made);
    }
    return kept;
  }

  /// Test seam: gone, as at launch.
  void debugForget() {
    if (_kept case final kept?) {
      _free(kept);
    }
    _kept = null;
  }
}

/// The executor on [appGpuEngine]: one for the frames and the strokes alike.
/// Warmed for the first frame's picture: 🔬1.7–6 s cold on the main PC
/// (11-06) and 8.3 s beside a busy test line (11-10).
GpuComposite get appGpuComposite => appGpuCompositeKernels.kept;
final appGpuCompositeKernels = AppKernels<GpuComposite>(
  GpuComposite.new,
  GpuComposite.opening,
  (composite) => composite.free(),
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

/// [appGpuEngine] once [openAppGpuEngine] has opened it, null till then:
/// what the app's screens on the engine wait for, drawing as they did
/// before it till it is there (grid-on-the-engine ④, 관제 2026-11-08 20:54:
/// 「열리기 전엔 모든 스팬이 지금의 차가운 스팬처럼 클래식 — 없다가 생기는 것
/// 없음 · 장치는 첫 프레임 뒤에」).
ValueListenable<GpuEngine?> get appGpuEngineOpen => _opened;
final ValueNotifier<GpuEngine?> _opened = ValueNotifier(null);

/// Opens [appGpuEngine] off this isolate ([GpuEngine.opening]) — at once
/// where it is open already — and tells [appGpuEngineOpen]. The app asks
/// after its first frame; a test that shows the engine's screens asks for
/// itself.
Future<GpuEngine> openAppGpuEngine() => _opening ??= () async {
  final opened = _engine ?? await GpuEngine.opening(_opener());
  // Asked the other way while this one opened: the app keeps one.
  final engine = _engine ??= opened;
  if (!identical(engine, opened)) {
    opened.close();
  }
  return _opened.value = engine;
}();
Future<GpuEngine>? _opening;
