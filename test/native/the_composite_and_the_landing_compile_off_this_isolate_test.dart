import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show debugKernelsCompiledHere;

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';

import '../helpers/the_apps_engine_let_go.dart';

/// THE FIRST PICTURE OF A LAUNCH WAITS FOR NOTHING: the composite pass and
/// what lands a stamp are compiled off this isolate once the engine is
/// open, as the blur brush's and the colour verbs' kernels are.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => AppKernels.debugCompileHere = false);

  test('the first picture does not compile the pass on this isolate', () async {
    // Nothing has compiled the pass yet: no engine is asked for yet.
    theAppHasNoEngineYet();
    await openAppGpuEngine();
    final tools = appEngineFrameTools;

    await Future<void>.delayed(Duration.zero);

    expect(appGpuCompositeKernels.compiled, isNull, reason: 'still compiling');
    await tools;
    expect(appGpuCompositeKernels.compiled, isNotNull);
  });

  test('asked for while the pass compiles, the app keeps one', () async {
    // 🐞bundled-files-find-the-engine-already-open ③ (2026-11-23): from no
    // engine, as the first test is — not with the pass forgotten. The frame
    // tools the first test opened keep the pass they were opened with
    // (`appEngineFrameTools`), and forgotten it was freed under them: the
    // next file's first frame was laid with it, and the engine's thread
    // waited for good on a lock in freed memory (🔬cdb on the stuck
    // tester: `Fulls::cell` under `Composite::walk_here`, the UI thread in
    // `gpu_engine_surface_read` waiting for it).
    theAppHasNoEngineYet();
    await openAppGpuEngine();

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

  // 🐞the-windows-app-stays-after-its-window-closes (관제 2026-11-16 00:46):
  // the wait for the holds stood on a worker in the engine, and an app
  // closed while it compiled ahead what a hand needs never ended — the
  // isolate that lets go went down first, and the VM waited for the worker.
  // A widget test's clock lets no worker answer (`debugWorkersRunHere` has
  // why): a wait made where the holds are let go goes on all the same.
  testWidgets('what waits for the holds waits on this isolate: it goes on '
      'as the last of them is let go, with no worker to answer', (
    tester,
  ) async {
    final engine = appGpuEngine;
    expect(engine.debugCompilesApartHeld, 0, reason: '⛔premise');
    final first = Completer<void>();
    final second = Completer<void>();
    final holding = [
      engine.whileCompilesApartWait(() => first.future),
      engine.whileCompilesApartWait(() => second.future),
    ];
    var through = false;
    unawaited(engine.compilesApartLetGo().then((_) => through = true));
    // The wait takes a turn of this isolate first (`compilesApartLetGo`).
    await tester.pump(Duration.zero);
    expect(through, isFalse, reason: 'held twice');

    first.complete();
    await tester.pump(Duration.zero);
    expect(through, isFalse, reason: 'one hold left');

    second.complete();
    await tester.pump(Duration.zero);
    expect(through, isTrue);
    await Future.wait(holding);
    expect(engine.debugCompilesApartHeld, 0);

    // Held again, it is waited for again.
    final again = Completer<void>();
    final holdingAgain = engine.whileCompilesApartWait(() => again.future);
    var throughAgain = false;
    unawaited(engine.compilesApartLetGo().then((_) => throughAgain = true));
    await tester.pump(Duration.zero);
    expect(throughAgain, isFalse, reason: 'held again');
    again.complete();
    await tester.pump(Duration.zero);
    expect(throughAgain, isTrue);
    await holdingAgain;
  });
}
