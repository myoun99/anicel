import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/debug/frame_stats.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';

/// 🔬The frame statistics' GPU and memory lines, read of the app's engine
/// itself (card the-galaxy-tab-canvas-went-slow-on-build-1095, 관제
/// 2026-11-23 23:24: 쌓인 걸음 · 메모리): the submits it has not heard
/// finished, whether its device stamps their GPU time, and what the OS says
/// it uses of its adapter's memory — and what its compiler made and what
/// its pictures hold (관제 2026-11-24: COMPILE · MEMORY 내역). On a file of
/// its own: the engine, once open, stays open for every test after it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FrameStats.install();
    FrameStats.reset();
  });
  tearDown(() {
    FrameStats.reset();
    MeasurementMode.reset();
  });

  test('with the app\'s engine open, the GPU line reads its submits behind '
      'and whether its device stamps them, the memory line its adapter\'s '
      'use', () async {
    final engine = await openAppGpuEngine();
    FrameStats.debugFeed(<FrameTiming>[
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 1000,
        rasterStart: 1000,
        rasterFinish: 2000,
        rasterFinishWallTime: 2000,
      ),
    ]);
    FrameStats.publish();

    final stats = FrameStats.latest.value!;
    expect(stats.gpuBehind, engine.submitsBehind);
    expect(
      stats.gpuBehindWorst,
      stats.gpuBehind,
      reason: 'read as it was published, and at no frame before',
    );
    expect(stats.gpuClocked, engine.clocked);
    final used = appGpuVideoMemory?.used;
    expect(
      stats.videoMegabytes?.used,
      used == null ? isNull : used / 1024 / 1024,
    );
    expect(stats.compiles, engine.compiles);
    expect(stats.picturesMegabytes, engine.pictureBytes / 1024 / 1024);
  });

  test('the engine\'s compile words are read each in its place — and what '
      'the folder answered is none where the OS keeps them and says '
      'nothing', () {
    expect(GpuEngine.compilesSaid([7, 2500000, 900000, 1, 3, 5]), (
      made: 7,
      micros: 2500000,
      longestMicros: 900000,
      underWay: 1,
      stoodIn: 3,
      found: 5,
    ));
    // u64::MAX, as the engine says it on Apple (rust/src/platform/apple.rs).
    expect(
      GpuEngine.compilesSaid([7, 2500000, 900000, 1, 3, -1]).found,
      isNull,
    );
  });
}
