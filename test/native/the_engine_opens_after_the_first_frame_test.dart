import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨THE APP OPENS THE GPU ENGINE ONCE ITS FIRST FRAME IS ON THE SCREEN
/// (관제 2026-11-08 20:54: 「장치는 첫 프레임 뒤에」).
///
/// The device is not the first frame's: till it is open every row draws
/// its cells itself. 🔬Asked after the first frame was built, it was open
/// before that frame was rastered in 4 of 5 launches (main PC, profile,
/// 11-09) — so it waits for the raster, and is asked from main alone.
void main() {
  test('main opens the engine once the first frame is rastered, and only '
      'there', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      RegExp(
        r'waitUntilFirstFrameRasterized\.then\(\s*\(_\)\s*=>\s*'
        r'openAppGpuEngine\(\),?\s*\)',
      ).hasMatch(source),
      isTrue,
      reason: 'main asks for the engine once the first frame is rastered',
    );
    expect(
      'openAppGpuEngine('.allMatches(source).length,
      1,
      reason: 'main asks for the engine in one place',
    );
  });
}
