// The first compile of the pass takes seconds on a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/app_gpu_engine.dart' show AppKernels;
import 'package:anicel/src/native/engine_cel_pixels.dart';

/// THE FIRST PRESS OF A COLOUR VERB WAITS FOR NOTHING (flip lane ⓒ): the
/// pass is compiled off this isolate once the engine is open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => AppKernels.debugCompileHere = false);
  tearDown(EngineCelPixels.debugForget);

  test('this isolate goes on while it compiles', () async {
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks += 1,
    );
    await EngineCelPixels.warm();
    timer.cancel();
    expect(ticks, greaterThan(0));
  });

  test('warmed, it is the one every press is handed', () async {
    await EngineCelPixels.warm();
    expect(identical(EngineCelPixels.pass, EngineCelPixels.pass), isTrue);
  });

  test('asked for while it compiles, the app keeps one', () async {
    final warming = EngineCelPixels.warm();
    final asked = EngineCelPixels.pass;
    await warming;
    expect(identical(EngineCelPixels.pass, asked), isTrue);
  });

  test('warmed twice, it is compiled once', () async {
    await EngineCelPixels.warm();
    final first = EngineCelPixels.pass;
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks += 1,
    );
    await EngineCelPixels.warm();
    timer.cancel();
    expect(identical(EngineCelPixels.pass, first), isTrue);
    expect(ticks, 0, reason: 'nothing off this isolate to wait for');
  });
}
