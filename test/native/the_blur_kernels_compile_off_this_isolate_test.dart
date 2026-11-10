// The first compile of the blur kernels takes seconds on a machine this
// busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/app_gpu_engine.dart' show AppKernels;
import 'package:anicel/src/native/engine_strokes.dart';

/// 🚨THE FIRST BLUR OF A LAUNCH WAITS FOR NOTHING (flip lane ⓒ): the blur
/// brush's kernels are ten pipelines, 🔬10.2 s on the main PC with eighteen
/// test files running, and every stroke shares the one set. They are
/// compiled off this isolate once the engine is open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => AppKernels.debugCompileHere = false);
  tearDown(EngineStrokes.debugForgetBlurs);

  // First in the file: no stroke has been compiled yet.
  test('a stroke for the first pen-down is compiled off this isolate too',
      () async {
    final warming = EngineStrokes.warm();
    expect(EngineStrokes.debugIdle, 0, reason: 'still compiling');
    await warming;
    expect(EngineStrokes.debugIdle, 1);
  });

  test('this isolate goes on while they compile', () async {
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks += 1,
    );
    await EngineStrokes.warmBlurs();
    timer.cancel();
    expect(ticks, greaterThan(0));
  });

  test('warmed, they are the ones every stroke is handed', () async {
    await EngineStrokes.warmBlurs();
    expect(identical(EngineStrokes.blurs, EngineStrokes.blurs), isTrue);
  });

  test('asked for while they compile, the app keeps one set', () async {
    final warming = EngineStrokes.warmBlurs();
    final asked = EngineStrokes.blurs;
    await warming;
    expect(identical(EngineStrokes.blurs, asked), isTrue);
  });

  test('warmed twice, they are compiled once', () async {
    await EngineStrokes.warmBlurs();
    final first = EngineStrokes.blurs;
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks += 1,
    );
    await EngineStrokes.warmBlurs();
    timer.cancel();
    expect(identical(EngineStrokes.blurs, first), isTrue);
    expect(ticks, 0, reason: 'nothing off this isolate to wait for');
  });
}
