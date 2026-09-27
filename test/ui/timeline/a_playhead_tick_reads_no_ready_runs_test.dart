import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';

/// 🚨I-22 ③: A PLAYHEAD TICK READS NO READY RUNS.
///
/// The ruler's overlay draws the current-frame tint and the green ready bar
/// in one paint, and every paint read the runs afresh — so every playback
/// tick, which moves only the tint, asked the cache how ready the whole
/// window was (the storyboard at 0.16px, profile build: 50ms of a 908ms
/// tick sample). What turns a frame ready or not arrives on the overlay's
/// signal (F-166), and what it asks about moves with the window; the paint
/// a tick asks for draws the runs read last.
void main() {
  testWidgets('a tick moves the tint and reads nothing; a signal and a '
      'window move read again', (tester) async {
    var reads = 0;
    final playhead = ValueNotifier<int?>(1);
    final signal = ValueNotifier<int>(0);
    final bucket = ValueNotifier<int>(0);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 800,
            height: 20,
            child: TimelineRulerCursorOverlay(
              keyValue: 'ready-bar-probe',
              playhead: playhead,
              repaintSignal: signal,
              windowBucket: bucket,
              viewportMainExtent: 40,
              renderedFrames: 100,
              cellWidth: 8,
              readyRunsIn: (start, end) {
                reads += 1;
                return [(startIndex: start, endIndexExclusive: start + 1)];
              },
            ),
          ),
        ),
      ),
    );
    final strip = tester.renderObject<RenderCustomPaint>(
      find.byKey(const ValueKey<String>('ready-bar-probe')),
    );
    TimelineRulerCursorOverlayPainter painter() =>
        strip.painter! as TimelineRulerCursorOverlayPainter;
    expect(reads, greaterThan(0), reason: 'premise: the first paint read');
    final painted = reads;

    playhead.value = 2;
    await tester.pump();
    playhead.value = 3;
    await tester.pump();
    expect(painter().tintedFrame(), 3, reason: 'premise: the tint followed');
    expect(reads, painted, reason: 'a tick turns nothing ready or not');

    signal.value += 1;
    await tester.pump();
    expect(reads, greaterThan(painted), reason: 'a signal may have');
    final signalled = reads;

    bucket.value = 5;
    await tester.pump();
    expect(
      reads,
      greaterThan(signalled),
      reason: 'the window moved, so it asks about other frames',
    );
  });

  testWidgets('a rebuild with another answer draws that answer at once', (
    tester,
  ) async {
    final bucket = ValueNotifier<int>(0);
    Future<void> mount(ReadyRunsIn answer) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 800,
            height: 20,
            child: TimelineRulerCursorOverlay(
              keyValue: 'ready-bar-probe',
              playhead: null,
              repaintSignal: null,
              windowBucket: bucket,
              viewportMainExtent: 40,
              renderedFrames: 100,
              cellWidth: 8,
              readyRunsIn: answer,
            ),
          ),
        ),
      ),
    );
    await mount((start, end) => [(startIndex: 0, endIndexExclusive: 2)]);
    await mount((start, end) => [(startIndex: 4, endIndexExclusive: 6)]);
    final strip = tester.renderObject<RenderCustomPaint>(
      find.byKey(const ValueKey<String>('ready-bar-probe')),
    );
    // The bar's rects, read back as frames (8px a frame).
    final canvas = TestRecordingCanvas();
    (strip.painter! as TimelineRulerCursorOverlayPainter).paint(
      canvas,
      strip.size,
    );
    final bars = [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawRect)
          call.invocation.positionalArguments.first as Rect,
    ].where(
      (rect) =>
          rect.height == TimelineRulerCursorOverlayPainter.readyBarThickness,
    );
    expect(
      [for (final bar in bars) (bar.left / 8).round()],
      [4],
      reason: 'the strip draws the answer it was rebuilt with',
    );
  });
}
