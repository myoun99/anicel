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

  test('the list main asks for opens the engine before it compiles on it', () {
    final list = File(
      'lib/src/native/app_kernels_ahead.dart',
    ).readAsStringSync();
    expect(
      RegExp(
        r'Future<void> compileAppKernelsAhead\(\) async \{\s*'
        r'final engine = await openAppGpuEngine\(\);',
      ).hasMatch(list),
      isTrue,
      reason: 'the list starts at the engine, opened off this isolate',
    );
  });

  // 🗣️관제 2026-11-11 04:09 · 06:00 (gpu-canonical-store ④): 「선은 첫 획 ·
  // 첫 들어올리기의 멈춤 자체다 … 손이 쓰는 커널 → composite 전용 패스」 —
  // what a hand on the canvas would else compile at its first press comes
  // before what draws itself or waits meanwhile, the blur brush's ten last
  // (🔬7.1–7.4 s of the Surface's compiler), and what the engine compiles
  // apart waits from before the canvas first shows till a hand's are in.
  test('the list compiles what a hand needs before the grids\', the chains\' '
      'and the blur brush\'s — what the engine compiles apart held till '
      'then, and no longer', () {
    final list = File(
      'lib/src/native/app_kernels_ahead.dart',
    ).readAsStringSync();
    final inTurn = <Pattern>[
      'await openAppGpuEngine();',
      'await engine.whileCompilesApartWait(() async {',
      'await appEngineFrameTools;',
      'await EngineStrokes.warm();',
      'await GpuInk.opening(engine)',
      'await EngineCelPixels.warm();',
      'await appGpuStampLandingKernels.warm();',
      // Where the hold ends.
      RegExp(r'return tools;\s*\}\);'),
      'await appGpuGridKernels.warm();',
      'await tools.composite.compileChains();',
      'await EngineStrokes.warmBlurs();',
    ];
    final at = [for (final asked in inTurn) list.indexOf(asked)];
    expect(at, everyElement(isNonNegative), reason: '⛔premise: each asked');
    expect(at, orderedEquals([...at]..sort()));
  });
}
