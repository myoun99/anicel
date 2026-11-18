import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/engine_tile_ledger.dart';

/// 🚨WHAT THE ENGINE REFUSES IS THROWN BY NAME ([GpuRefused]), wherever it
/// is met: the app says a job its graphics device refused by that name
/// alone (`EngineRefusals`, 🗣️gpu-canonical-store-Q14, 유저 2026-11-11:
/// 「공통 알림 창으로 한 번 알린다」), so a refusal thrown bare is one never
/// said.
void main() {
  test('the engine\'s library throws nothing as a bare state error', () {
    final library = File(
      'packages/gpu_engine/lib/gpu_engine.dart',
    ).readAsStringSync();
    expect(
      'throw GpuRefused(_lastError())'.allMatches(library),
      isNotEmpty,
      reason: '⛔premise: the library is read',
    );
    expect('StateError('.allMatches(library), isEmpty);
  });

  // ⚠️By its source: past both budgets a store falls short only where the
  // driver refuses a page, which no test has one do.
  test('room the device has not for tiles asked of it is a refusal, and a '
      'cause of its own', () {
    final ledger = File(
      'lib/src/native/engine_tile_ledger.dart',
    ).readAsStringSync();
    for (final short in ['the device lands ', 'the device stores ']) {
      expect(
        RegExp(
          r"throw TileRoomRefused\(\s*'" + RegExp.escape(short),
        ).hasMatch(ledger),
        isTrue,
        reason: short,
      );
    }
    expect(TileRoomRefused('none'), isA<GpuRefused>());
    expect(TileRoomRefused('none'), isNot(isA<GpuReadFailed>()));
  });

  test('a refusal met on the isolate a device opens on comes back as one', () {
    expect(
      GpuEngine.opening(_noDevice),
      throwsA(
        isA<GpuRefused>().having((error) => error.message, 'why', 'no device'),
      ),
    );
  });
}

/// An opener the device refuses, as `GpuEngine.onFlutterAdapter` is where
/// Flutter gives no adapter.
GpuEngine _noDevice() => throw GpuRefused('no device');
