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
        'final tools = await appEngineFrameTools;',
      ).hasMatch(list),
      isTrue,
      reason: 'the list starts at the frame tools',
    );
    final tools = File(
      'lib/src/native/engine_frame_tools.dart',
    ).readAsStringSync();
    expect(
      RegExp(
        r'get appEngineFrameTools => _tools \?\?= \(\) async \{\s*'
        r'await openAppGpuEngine\(\);',
      ).hasMatch(tools),
      isTrue,
      reason: 'which open the engine off this isolate first',
    );
  });
}
