import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨THE APP OPENS THE GPU ENGINE ONCE ITS FIRST FRAME IS ON THE SCREEN
/// (관제 2026-11-08 20:54: 「장치는 첫 프레임 뒤에」).
///
/// The device is not the first frame's: till it is open every row draws
/// its cells itself. 🔬Asked after the first frame was built, it was open
/// before that frame was rastered in 4 of 5 launches (main PC, profile,
/// 11-09) — so it waits for the raster, and is asked from main alone.
///
/// ↩️Main asked for the engine by name till 2026-11-10; it asks for the
/// list of kernels compiled ahead now (gpu-canonical-store ⑦), which opens
/// the engine before anything is compiled on it.
void main() {
  test('main opens the engine once the first frame is rastered, and only '
      'there', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      RegExp(
        r'waitUntilFirstFrameRasterized\.then\(\s*\(_\)\s*=>\s*'
        r'compileAppKernelsAhead\(\),',
      ).hasMatch(source),
      isTrue,
      reason: 'main asks for the engine, and its kernels behind it, once '
          'the first frame is rastered',
    );
    expect(
      RegExp(
        r'compileAppKernelsAhead\(|openAppGpuEngine\(|appEngineFrameTools\b|'
        r'appGpuEngine\b',
      ).allMatches(source).length,
      1,
      reason: 'main asks for the engine in one place',
    );
  });

  // 🗣️gpu-canonical-store-Q15 (유저 2026-11-11): 「준비가 끝난 뒤에 그림을
  // 띄운다 — 그때까지 고리」 — a first frame built before the word would show
  // the app as one a hand may work on.
  test('main says the app is held for its engine before its first frame is '
      'built', () {
    final source = File('lib/main.dart').readAsStringSync();
    final (said, run) = (
      source.indexOf('holdTheAppForItsEngine();'),
      source.indexOf('runApp('),
    );
    expect(said, isNonNegative, reason: 'main says so');
    expect(said, lessThan(run), reason: 'before the app is run');
  });

  test('the list main asks for opens the engine before it compiles on it', () {
    final list = File(
      'lib/src/native/app_kernels_ahead.dart',
    ).readAsStringSync();
    expect(
      RegExp(
        r'Future<void> compileAppKernelsAhead\(\) async \{\s*'
        r'final EngineFrameTools tools;\s*try \{\s*'
        r'final engine = await openAppGpuEngine\(\);',
      ).hasMatch(list),
      isTrue,
      reason: 'the list starts at the engine, opened off this isolate',
    );
  });

  // 🗣️관제 2026-11-11 04:09 · 06:00 · 06:42 (gpu-canonical-store ④): 「선은
  // 첫 획 · 첫 들어올리기의 멈춤 자체다 … 손이 쓰는 커널 → composite 전용
  // 패스」, 「블러 브러시도 손이 쓰는 도구」 — what a hand on the canvas would
  // else compile at its first press comes before what draws itself or
  // waits meanwhile, the scan (12 ms) before the canvas itself, the blur
  // brush's strips last (🔬six of its ten, nine tenths of their 7.1–7.4 s
  // of the Surface's compiler: a stroke goes a pass a dispatch meanwhile),
  // and what the engine compiles apart waits from before the canvas first
  // shows till a hand's are in. ↩️What a hand needs was compiled in turn
  // till 2026-11-13; it is asked for all at once now (🗣️유저 2026-11-13,
  // the-wait-window-stands-seven-seconds-on-the-surface-Q1 「나란히
  // 컴파일」), the engine compiling on a thread a core.
  test('the list compiles what a hand needs, all at once, before the grids\', '
      'the chains\' and the blur brush\'s strips — what the engine compiles '
      'apart held till then, and no longer', () {
    final list = File(
      'lib/src/native/app_kernels_ahead.dart',
    ).readAsStringSync();
    final (atOnce, through) = (
      list.indexOf('await Future.wait<void>(['),
      list.indexOf(']);', list.indexOf('await Future.wait<void>([')),
    );
    final aHandNeeds = [
      'GpuInk.opening(engine)',
      'opened,',
      'EngineStrokes.warm(),',
      'EngineCelPixels.warm(),',
      'appGpuStampLandingKernels.warm(),',
      'EngineFloods.warm(),',
      'EngineStrokes.warmBlurs(),',
    ];
    final asked = [for (final one in aHandNeeds) list.indexOf(one, atOnce)];
    expect(atOnce, isNonNegative, reason: '⛔premise: asked all at once');
    expect(
      asked,
      everyElement(allOf(greaterThan(atOnce), lessThan(through))),
      reason: 'each of what a hand needs is asked for with the rest',
    );
    final inTurn = <Pattern>[
      'await openAppGpuEngine();',
      'await engine.whileCompilesApartWait(() async {',
      'final opened = appEngineFrameTools;',
      'await Future.wait<void>([',
      // Where the hold ends.
      RegExp(r'return opened;\s*\}\);'),
      // 🗣️gpu-canonical-store-Q15 (유저 2026-11-11): 「준비가 끝난 뒤에 그림을
      // 띄운다 — 그때까지 고리」 — where the app is let go: past what a hand
      // needs, before what draws itself, and on a throw as well.
      RegExp(r'\} finally \{[^}]*_getsReady\.value = false;\s*\}'),
      'await appGpuGridKernels.warm();',
      'await tools.composite.compileChains();',
      'await EngineStrokes.warmBlurStrips();',
    ];
    final at = [for (final asked in inTurn) list.indexOf(asked)];
    expect(at, everyElement(isNonNegative), reason: '⛔premise: each asked');
    expect(at, orderedEquals([...at]..sort()));
  });
}
