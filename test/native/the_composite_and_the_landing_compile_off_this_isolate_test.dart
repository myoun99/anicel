import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show debugKernelsCompiledHere;

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';

/// THE FIRST PICTURE OF A LAUNCH WAITS FOR NOTHING: the composite pass and
/// what lands a stamp are compiled off this isolate once the engine is
/// open, as the blur brush's and the colour verbs' kernels are.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => AppKernels.debugCompileHere = false);

  // First in the file: nothing has compiled the pass yet.
  test('the first picture does not compile the pass on this isolate', () async {
    await openAppGpuEngine();
    final tools = appEngineFrameTools;

    await Future<void>.delayed(Duration.zero);

    expect(appGpuCompositeKernels.compiled, isNull, reason: 'still compiling');
    await tools;
    expect(appGpuCompositeKernels.compiled, isNotNull);
  });

  test('asked for while the pass compiles, the app keeps one', () async {
    appGpuCompositeKernels.debugForget();

    final opening = appGpuCompositeKernels.warm();
    final asked = appGpuComposite;

    expect(identical(await opening, asked), isTrue);
    expect(identical(appGpuComposite, asked), isTrue);
  });

  test('compiled already, the pass is the one it was', () async {
    final first = await appGpuCompositeKernels.warm();

    expect(identical(await appGpuCompositeKernels.warm(), first), isTrue);
  });

  test('what lands a stamp is not compiled on this isolate', () async {
    final warming = appGpuStampLandingKernels.warm();
    // Turned once: a compile on this isolate has finished by now.
    await Future<void>.delayed(Duration.zero);

    expect(
      appGpuStampLandingKernels.compiled,
      isNull,
      reason: 'still compiling',
    );
    await warming;
    expect(appGpuStampLandingKernels.compiled, isNotNull);
  });

  test('the compile that lost the race is freed, and what is forgotten',
      () async {
    final freed = <Object>[];
    final elsewhere = Completer<Object>();
    final here = Object();
    final made = Object();
    final kernels = AppKernels<Object>(
      (_) => here,
      (_) => elsewhere.future,
      freed.add,
    );

    final warming = kernels.warm();
    expect(kernels.kept, same(here));
    elsewhere.complete(made);

    expect(await warming, same(here));
    expect(freed, [made]);

    kernels.debugForget();
    expect(freed, [made, here]);
    expect(kernels.compiled, isNull);
  });

  test('forgotten, a set is compiled again as at launch — not made of the '
      'kernels the engine kept', () {
    int builtHereBy(void Function() use) {
      final before = debugKernelsCompiledHere;
      use();
      return debugKernelsCompiledHere - before;
    }

    builtHereBy(() => appGpuStampLandingKernels.kept);
    expect(
      builtHereBy(() => appGpuStampLandingKernels.kept),
      0,
      reason: '⛔premise: compiled',
    );

    appGpuStampLandingKernels.debugForget();

    expect(
      builtHereBy(() => appGpuStampLandingKernels.kept),
      greaterThan(0),
    );
  });

  // 🗣️관제 2026-11-11 06:07 (gpu-canonical-store ④): 「잡은 것은 모든 길에서
  // 놓여야 한다 — 컴파일 실패 …」: a hold left on, no plan would ever run on
  // a pass of its own.
  test('what the engine compiles apart is let go however what was compiled '
      'ahead of it ends', () async {
    final engine = await openAppGpuEngine();
    expect(engine.debugCompilesApartHeld, 0, reason: '⛔premise');
    final failure = StateError('a compile that failed');

    await expectLater(
      engine.whileCompilesApartWait<void>(() async {
        expect(engine.debugCompilesApartHeld, 1, reason: 'held meanwhile');
        await Future<void>.delayed(Duration.zero);
        throw failure;
      }),
      throwsA(same(failure)),
    );
    expect(engine.debugCompilesApartHeld, 0, reason: 'one that failed late');

    await expectLater(
      engine.whileCompilesApartWait<void>(() => throw failure),
      throwsA(same(failure)),
    );
    expect(engine.debugCompilesApartHeld, 0, reason: 'one that never began');

    expect(await engine.whileCompilesApartWait(() async => 7), 7);
    expect(engine.debugCompilesApartHeld, 0, reason: 'one that ended well');
  });
}
