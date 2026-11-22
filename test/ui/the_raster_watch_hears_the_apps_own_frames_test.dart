import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/raster_watch.dart';

/// [RasterWatch] is fed by the app's own frames once `main` installs it:
/// each frame built is one handed over, and what the engine says drawn is
/// heard (board a-real-gpu-reset-went-unheard-on-the-main-pc).
///
/// ⚠️In a file of its own: what is installed stays for the isolate — a
/// persistent frame callback cannot be removed — and would count the
/// frames of every test beside it.
void main() {
  test('main installs it before the app is run', () {
    final source = File('lib/main.dart').readAsStringSync();
    final (installed, run) = (
      source.indexOf('RasterWatch.install();'),
      source.indexOf('runApp('),
    );
    expect(installed, isNonNegative, reason: 'main installs it');
    expect(installed, lessThan(run), reason: 'from the first frame');
  });

  testWidgets('a frame built is one handed over, and what the engine says '
      'drawn — the newest of a batch, in whatever order — is what the '
      'raster thread is back from', (tester) async {
    RasterWatch.install();
    addTearDown(RasterWatch.debugForget);
    final frame = tester.binding.platformDispatcher.frameData.frameNumber;

    /// As the engine says frames drawn: a batch, a timing each.
    void saidDrawn(List<int> frames) =>
        tester.binding.platformDispatcher.onReportTimings!([
          for (final frame in frames)
            FrameTiming(
              vsyncStart: 0,
              buildStart: 0,
              buildFinish: 0,
              rasterStart: 0,
              rasterFinish: 0,
              rasterFinishWallTime: 0,
              frameNumber: frame,
            ),
        ]);

    await tester.pump();
    saidDrawn([frame]);
    await tester.binding.delayed(RasterWatch.patience * 2);
    expect(RasterWatch.stood.value, isNull, reason: 'said drawn');

    RasterWatch.handedOver(frame + 9);
    saidDrawn([frame + 3, frame + 9, frame + 5]);
    await tester.binding.delayed(RasterWatch.patience * 2);
    expect(RasterWatch.stood.value, isNull, reason: 'the newest of them');

    await tester.pump();
    await tester.binding.delayed(RasterWatch.patience);
    expect(
      RasterWatch.stood.value?.handedOver,
      frame,
      reason: 'handed over, and never said drawn',
    );
  });
}
