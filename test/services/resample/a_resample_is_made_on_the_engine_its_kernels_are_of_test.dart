import 'dart:typed_data';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';
import 'package:anicel/src/services/resample/selection_resample.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/the_apps_engine_let_go.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」 — a picture read through R1
/// ([resampleOnTheEngine]) waits twice before it is made, for the engine
/// and for its kernels, and the app may let its engine go between the two:
/// it is made on the engine the kernels are of.
///
/// 🔬2026-11-13: made on the engine first waited for, it was carried by
/// the next engine's kernels, and wgpu ended the process — `Cannot get
/// BufferId(2,2), found other resource BufferId(2,1)` — a tip's thumbnail
/// on its way as the app opened another engine. ⚠️So the pin is red by the
/// test never ending: there is no error to catch.
///
/// On the app's own engine, which the test loses.
void main() {
  test('a resample on its way as the app lets its engine go is made on '
      'the next, whose kernels it waits for — and reads as it would', () async {
    // As the app compiles: off this isolate, in a wait the app's engine
    // may go in.
    AppKernels.debugCompileHere = false;
    addTearDown(() => AppKernels.debugCompileHere = true);
    await openAppGpuEngine();
    appGpuStampLandingKernels.debugForget();
    const side = 4;
    final source = Uint8List.fromList([
      for (var at = 0; at < side * side; at += 1) ...[at, 2 * at, 3 * at, 255],
    ]);

    // Asked, and waiting for the engine that is open.
    final asked = resampleOnTheEngine(
      src: source,
      srcWidth: side,
      srcHeight: side,
      dstWidth: side,
      dstHeight: side,
      transform: ResampleTransform.identity(),
      mode: ResampleMode.blend,
    );
    final gone = theAppsEngineLostAndLetGo();

    expect(await asked, source, reason: 'carried as it lies');
    expect(isTheAppsEngine(gone), isFalse, reason: '⛔premise: on the next');
  });
}
