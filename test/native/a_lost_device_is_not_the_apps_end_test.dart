import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_refusals.dart';
import 'package:anicel/src/native/gpu_adapter_choice.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
/// 유지한다」 — a device the driver took away (a reset, an update, a wake
/// from sleep) is not the app's end. The first of it, here: nothing asked
/// of a device that is gone ends the process, what waits for it is refused
/// by name ([GpuRefused]), and the app says so once
/// (🗣️gpu-canonical-store-Q14, [EngineRefusals]).
///
/// What the engine makes of a device destroyed under it is its own tests'
/// to pin (rust/src/device.rs) — here, what Dart makes of its C ABI.
///
/// ⚠️IN THIS ORDER: the first test asks before any engine is open, and the
/// last loses the app's own — one a process — for what is left of the file.
void main() {
  final held = <Pointer<Uint8>>[];
  tearDown(() {
    held
      ..forEach(calloc.free)
      ..clear();
  });

  /// A tile's bytes, each [value].
  Pointer<Uint8> tileOf(int value) {
    final tile = calloc<Uint8>(gpuTileBytes);
    held.add(tile);
    tile.asTypedList(gpuTileBytes).fillRange(0, gpuTileBytes, value);
    return tile;
  }

  /// What reading [tiles] of [pool] back is refused by.
  GpuRefused? refusedReading(GpuPool pool, List<GpuTile> tiles) {
    try {
      pool.read(tiles, tileOf(0));
    } on GpuRefused catch (refused) {
      return refused;
    }
    return null;
  }

  // 🔬On Windows Flutter names its adapter, and names none to a test: an
  // engine opened here on Flutter's is refused, so an asking that opened
  // one would throw. Elsewhere the only adapter there is would open, and
  // the asking is not seen to.
  test('asked of an app that has opened no engine, its device is not gone '
      'and has raised nothing — and the asking opens none', () {
    debugGpuAdapterChoice = GpuAdapterChoice.flutters;
    addTearDown(() => debugGpuAdapterChoice = GpuAdapterChoice.first);

    expect(appGpuEngineIsGone, isFalse);
    expect(debugTakeAppGpuEngineNoted(), isNull);
  });

  // On an engine of its own: nothing made on a device that is gone is of
  // use again, and the app has one.
  test('a device that is gone refuses what waits for it, by name, and ends '
      'no process at what does not wait', () {
    final engine = GpuEngine.onFirstAdapter();
    addTearDown(engine.close);
    final pool = GpuPool(engine, 1 << 30);
    addTearDown(pool.free);
    final stored = pool.store(pool.cel(), [tileOf(7)]);
    expect(refusedReading(pool, stored), isNull, reason: '⛔premise: read');
    expect(engine.debugTakeNoted(), isNull, reason: '⛔premise: none raised');
    expect(engine.isGone, isFalse);

    engine.debugLose();
    expect(engine.isGone, isFalse, reason: 'the word comes inside a wait');

    expect(
      refusedReading(pool, stored),
      isA<GpuReadFailed>().having(
        (refused) => refused.message,
        'why',
        startsWith('the graphics device is gone: '),
      ),
    );
    expect(engine.isGone, isTrue);

    // ↩️The two that ended the process, till 2026-11-11: a buffer made with
    // its bytes in it, and the first copy that named one of a lost device.
    final picture = GpuStampPicture(engine, Uint8List(2 * 2 * 4), 2, 2);
    expect(picture.pixels, throwsA(isA<GpuReadFailed>()));
    // What does not wait is refused where the engine meets what it cannot
    // do — a store has no buffer to lay its tiles in — and returns as if
    // it had worked elsewhere, told by what next waits.
    expect(
      () => pool.store(pool.cel(), [tileOf(9)]),
      throwsA(isA<GpuRefused>()),
    );

    // What the lost device raised at each of those is noted, and taken by
    // the one asking.
    expect(engine.debugTakeNoted(), isNotNull);
    expect(engine.debugTakeNoted(), isNull, reason: 'taken');
  });

  test('once the app\'s device is gone, whatever is refused for it is one '
      'cause — told once, and a cause of its own', () async {
    final reported = FlutterError.onError;
    final uncaught = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = reported;
      PlatformDispatcher.instance.onError = uncaught;
      EngineRefusals.debugForget();
    });
    FlutterError.onError = (_) {};
    PlatformDispatcher.instance.onError = (_, _) => true;
    EngineRefusals.install();
    var tellings = 0;
    void count() => tellings += 1;
    EngineRefusals.told.addListener(count);
    addTearDown(() => EngineRefusals.told.removeListener(count));
    // [refused] reported as what caught it reports it; the tellings once
    // the turn it was heard in is through.
    Future<int> toldOf(Object refused) async {
      FlutterError.reportError(FlutterErrorDetails(exception: refused));
      await null;
      return tellings;
    }

    final pool = GpuPool(appGpuEngine, 1 << 30);
    addTearDown(pool.free);
    final stored = pool.store(pool.cel(), [tileOf(7)]);
    expect(await toldOf(GpuReadFailed('a read the device refused')), 1);

    appGpuEngine.debugLose();
    expect(appGpuEngineIsGone, isFalse, reason: 'the word comes in a wait');
    final lost = refusedReading(pool, stored);
    expect(lost, isA<GpuReadFailed>());
    expect(appGpuEngineIsGone, isTrue);

    expect(await toldOf(lost!), 2, reason: 'not the cause its type was');
    expect(await toldOf(GpuRefused('a landing')), 2, reason: 'one cause');
    expect(await toldOf(GpuReadFailed('a save')), 2, reason: 'one cause');

    // What a lost device raises is no test's to answer for: each use of
    // what was made on it raises one.
    expect(debugTakeAppGpuEngineNoted(), isNull);
    expect(appGpuEngine.debugTakeNoted(), isNotNull, reason: '⛔premise');
  });
}
