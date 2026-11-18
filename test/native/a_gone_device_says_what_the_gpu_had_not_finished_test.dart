import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

/// H63 (관제 · 타임라인/콘티 2026-11-18): the GPU driver reset as the conte
/// panel's playback reached a third cut, and nothing said what the engine
/// had handed the GPU then. The engine keeps each submit until the GPU
/// says it finished it (rust/src/submits.rs pins how); here, what Dart
/// reads of it — and that it reads it of a device that is gone.
void main() {
  test('an engine tells each submit, where it was made and when, on the '
      'clock DateTime reads — and tells it still once its device is '
      'gone', () async {
    final engine = GpuEngine.onFirstAdapter();
    addTearDown(engine.close);
    final pool = GpuPool(engine, 1 << 30);
    addTearDown(pool.free);
    final tile = calloc<Uint8>(gpuTileBytes);
    addTearDown(() => calloc.free(tile));
    final before = DateTime.now().microsecondsSinceEpoch;
    pool.store(pool.cel(), [tile], (tile) => tile);
    await engine.done();
    final after = DateTime.now().microsecondsSinceEpoch;

    final line = RegExp(
      r'^submit #(\d+) at (\d+) (\S+):(\d+) dispatches=(\d+) groups=(\d+) '
      r'(unfinished|last-done)$',
    );
    final told = engine.unfinishedSubmits.trimRight().split('\n');
    final said = [for (final each in told) line.firstMatch(each)];
    expect(said, everyElement(isNotNull), reason: told.join('\n'));
    final done = said.lastWhere((each) => each![7] == 'last-done')!;
    expect(int.parse(done[2]!), inInclusiveRange(before, after));
    expect(done[3], endsWith('.rs'));

    engine.debugLose();
    expect(engine.unfinishedSubmits, isNotEmpty);
  });
}
