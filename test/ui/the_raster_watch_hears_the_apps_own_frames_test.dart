import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/lost_screen.dart';
import 'package:anicel/src/ui/look_only_frames.dart';
import 'package:anicel/src/ui/lost_screen_frames.dart';
import 'package:anicel/src/ui/raster_watch.dart';

/// The test binding with the PRODUCTION mixins that decide whether a frame
/// is drawn, in the order the app's binding wears them (`AnicelBinding`):
/// `flutter_test`'s own draws every frame it begins, and a watch that counted
/// frames begun would go green under it.
class _WatchedBinding extends AutomatedTestWidgetsFlutterBinding
    with RasterWatchFrames, LookOnlyFrames, LostScreenFrames {}

/// [RasterWatch] is fed by the app's own frames once `main` installs it:
/// each frame DRAWN is one handed over, and what the engine says drawn is
/// heard (board a-real-gpu-reset-went-unheard-on-the-main-pc).
void main() {
  final binding = _WatchedBinding();

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

  // The order is the law: a mixin's `drawFrame` stands over the ones listed
  // before it, and the watch's is to stand under every one that may not
  // draw. No compiler holds the app's binding to it.
  test('the app\'s binding wears the watch first among its mixins', () {
    final source = File(
      'lib/src/ui/ui_scale_binding.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      source,
      contains(
        'class AnicelBinding extends WidgetsFlutterBinding\n'
        '    with\n'
        '        RasterWatchFrames,\n',
      ),
    );
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

  // 검증 (2026-11-23, board a-frame-handed-over-after-the-loss-word-is-not-
  // said-drawn): the screen said gone, and ten seconds on the watch wrote
  // that the raster thread stood — of frames the app itself did not draw.
  testWidgets('a frame begun and not drawn — the screen gone, or asked for '
      'only to look — is no frame handed over', (tester) async {
    RasterWatch.install();
    addTearDown(RasterWatch.debugForget);
    addTearDown(LostScreen.debugForget);
    await built(tester);
    final frame = tester.binding.platformDispatcher.frameData.frameNumber;
    saidDrawn(tester, [frame]);
    final handedOverAt = RasterWatch.handedOverAt;
    expect(handedOverAt, isNot(DateTime(0)), reason: '⛔premise: heard');

    askOnlyToLook(binding.scheduleFrame);
    await tester.pump();
    expect(
      RasterWatch.handedOverAt,
      handedOverAt,
      reason: 'asked only to look, and not drawn',
    );

    LostScreen.debugGo();
    await built(tester);
    await built(tester);
    expect(RasterWatch.handedOverAt, handedOverAt, reason: 'the screen went');
    await tester.binding.delayed(RasterWatch.patience * 2);
    expect(RasterWatch.stood.value, isNull, reason: 'no raster thread waited');
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
