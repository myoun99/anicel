import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

import '../helpers/collect_garbage.dart';

/// What a thing the engine hands out counts of the live bytes is off as
/// its free returns, though the engine's thread stands still: a free the GC
/// calls waits for none of what is ahead of it there (rust/src/device.rs,
/// `let_go_unwaited`), so the count rides beside the thing in its hand and
/// is counted off on the free's own thread (`Engine::hands_counted`).
/// ↩️Each such free counted off its own by hand till 2026-11-17
/// (live-bytes-are-counted-by-hand-in-four-places).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a mask freed while the engine stands still is off as the free '
      'returns', () {
    final before = GpuMask.liveBytes;
    final mask = GpuMask(
      appGpuComposite,
      Uint8List(64 * 32),
      x: 0,
      y: 0,
      width: 64,
      height: 32,
    );
    expect(GpuMask.liveBytes - before, 64 * 32, reason: 'counted');

    appGpuEngine.debugStandStill(const Duration(seconds: 2));
    mask.free();

    expect(GpuMask.liveBytes, before);
  });

  test('a stamp\'s picture is counted while it lives, and off once the GC '
      'lets it go', () async {
    final before = GpuStampPicture.liveBytes;
    // In a call of its own: a picture is Finalizable, and one named here
    // would be kept alive to the end of this function.
    void makeAndDrop() {
      GpuStampPicture(appGpuEngine, Uint8List(16 * 8 * 4), 16, 8);
      expect(
        GpuStampPicture.liveBytes - before,
        16 * 8 * 4,
        reason: 'counted',
      );
    }

    makeAndDrop();
    await collectGarbageUntil(() => GpuStampPicture.liveBytes == before);

    expect(GpuStampPicture.liveBytes, before);
  });
}
