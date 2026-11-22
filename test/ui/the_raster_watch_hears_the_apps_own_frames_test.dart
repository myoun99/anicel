import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/raster_watch.dart';

/// [RasterWatch] is fed by the app's own frames once `main` installs it:
/// each frame built is one handed over, and what the engine says drawn is
/// heard (board a-real-gpu-reset-went-unheard-on-the-main-pc).
void main() {
  /// A frame of the app's, built. ⚠️The test binding draws a frame only
  /// where one was asked for, and a test's body starts with none: a bare
  /// pump builds nothing.
  Future<void> built(WidgetTester tester) async {
    tester.binding.scheduleFrame();
    await tester.pump();
  }

  /// As the engine says frames drawn: a batch, a timing each.
  void saidDrawn(WidgetTester tester, List<int> frames) =>
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

    await built(tester);
    expect(
      RasterWatch.handedOverAt,
      isNot(DateTime(0)),
      reason: 'LIVENESS — a frame was built, and handed over',
    );
    saidDrawn(tester, [frame]);
    await tester.binding.delayed(RasterWatch.patience * 2);
    expect(RasterWatch.stood.value, isNull, reason: 'said drawn');

    RasterWatch.handedOver(frame + 9);
    saidDrawn(tester, [frame + 3, frame + 9, frame + 5]);
    await tester.binding.delayed(RasterWatch.patience * 2);
    expect(RasterWatch.stood.value, isNull, reason: 'the newest of them');

    await built(tester);
    await tester.binding.delayed(RasterWatch.patience);
    expect(
      RasterWatch.stood.value?.handedOver,
      frame,
      reason: 'handed over, and never said drawn',
    );
  });

  testWidgets('forgotten, it hears no frame and no word of one — a test '
      'leaves the next no wait of its frames — till it is installed again', (
    tester,
  ) async {
    RasterWatch.install();
    addTearDown(RasterWatch.debugForget);
    final frame = tester.binding.platformDispatcher.frameData.frameNumber;
    RasterWatch.debugForget();

    // The binding says the frame all the same: what it was asked once is
    // asked for good.
    await built(tester);
    expect(RasterWatch.handedOverAt, DateTime(0), reason: 'no frame heard');
    saidDrawn(tester, [frame + 50]);

    RasterWatch.install();
    await built(tester);
    await tester.binding.delayed(RasterWatch.patience);
    expect(
      RasterWatch.stood.value?.handedOver,
      frame,
      reason: 'installed again, a frame is heard',
    );
    expect(
      RasterWatch.stood.value?.drawn,
      -1,
      reason: 'what was said drawn while it was forgotten was not heard',
    );
  });
}
