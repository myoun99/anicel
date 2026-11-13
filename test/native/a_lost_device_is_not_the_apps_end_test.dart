import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/gpu_adapter_choice.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
/// 유지한다」 — a device the driver took away (a reset, an update, a wake
/// from sleep) is not the app's end. The first of it, here: nothing asked
/// of a device that is gone ends the process, and what waits for it is
/// refused by name ([GpuRefused]). What the app makes of the first such
/// refusal it hears — another engine, or one telling — is pinned where
/// that is
/// (`the_first_refusal_of_a_gone_device_opens_another_engine_test.dart`).
///
/// What the engine makes of a device destroyed under it is its own tests'
/// to pin (rust/src/device.rs) — here, what Dart makes of its C ABI.
///
/// ⚠️IN THIS ORDER: the first test asks before any engine is open.
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

  // The causes the package names are the numbers the engine answers by: a
  // number written twice is two numbers the day one of them moves — and
  // the person is told of a cause that was not theirs.
  test('the causes the package names a device\'s going by are the '
      'engine\'s, number for number, and a number it does not know is no '
      'cause said', () {
    final engine = File(
      'packages/gpu_engine/rust/src/platform/mod.rs',
    ).readAsStringSync();
    expect(
      {
        for (final named in RegExp(
          r'pub const WENT_(\w+): u32 = (\d+);',
        ).allMatches(engine))
          GpuDeviceWent.of(int.parse(named[2]!)): named[1]!,
      },
      {
        GpuDeviceWent.unsaid: 'UNSAID',
        GpuDeviceWent.memory: 'BY_MEMORY',
        GpuDeviceWent.thisApp: 'BY_THIS_APP',
        GpuDeviceWent.removal: 'BY_REMOVAL',
        GpuDeviceWent.reset: 'BY_RESET',
        GpuDeviceWent.driver: 'BY_DRIVER',
      },
    );
    expect(
      [-1, GpuDeviceWent.values.length].map(GpuDeviceWent.of),
      everyElement(GpuDeviceWent.unsaid),
    );
  });
}
