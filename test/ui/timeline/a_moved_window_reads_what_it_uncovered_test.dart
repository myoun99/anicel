import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';

/// 🚨I-22 ②: A MOVED WINDOW ASKS FOR WHAT IT UNCOVERED.
///
/// A fast scroll moves the ruler's window on every frame, and every move
/// asked how ready all of it is: 161ms of the 374ms a fast scroll's frames
/// took (24 rows, 480 frames, 8px a frame, profile build). What the old and
/// the new window share was read a moment ago, and what turns a frame ready
/// or not arrives on the signal
/// (`a_playhead_tick_reads_no_ready_runs_test.dart`).
void main() {
  const frames = 400;
  const viewport = 160.0;
  const cell = 8.0;

  /// 0–29 ready, a hole, 34–49 ready, 50–51 red, 52 on ready, past 200 not.
  List<ReadyRun> answer(int start, int end) {
    final runs = <ReadyRun>[];
    for (var frame = start; frame < end; frame += 1) {
      if ((frame >= 30 && frame < 34) || frame >= 200) {
        continue;
      }
      appendReadyRun(runs, (
        startIndex: frame,
        endIndexExclusive: frame + 1,
        unreadable: frame == 50 || frame == 51,
      ));
    }
    return runs;
  }

  ({int startIndex, int endIndexExclusive}) windowAt(int bucket) =>
      frameWindowAtBucket(
        bucket,
        viewportMainExtent: viewport,
        cellExtent: cell,
        frames: (startIndex: 0, endIndexExclusive: frames),
      );

  Future<
    ({
      ValueNotifier<int> bucket,
      ValueNotifier<int> signal,
      List<(int, int)> asked,
      List<ReadyRun> Function() drawn,
    })
  >
  mount(WidgetTester tester) async {
    final bucket = ValueNotifier<int>(0);
    final signal = ValueNotifier<int>(0);
    final asked = <(int, int)>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 3200,
            height: 20,
            child: TimelineRulerCursorOverlay(
              keyValue: 'ready-bar-probe',
              playhead: null,
              repaintSignal: signal,
              windowBucket: bucket,
              viewportMainExtent: viewport,
              renderedFrames: frames,
              cellWidth: cell,
              readyRunsIn: (start, end) {
                asked.add((start, end));
                return answer(start, end);
              },
            ),
          ),
        ),
      ),
    );
    final strip = tester.renderObject<RenderCustomPaint>(
      find.byKey(const ValueKey<String>('ready-bar-probe')),
    );
    return (
      bucket: bucket,
      signal: signal,
      asked: asked,
      drawn: () =>
          (strip.painter! as TimelineRulerCursorOverlayPainter).runsToDraw!(),
    );
  }

  test('a red run stays apart from the ready one it meets', () {
    const ready = (startIndex: 0, endIndexExclusive: 2, unreadable: false);
    const red = (startIndex: 2, endIndexExclusive: 4, unreadable: true);
    final runs = <ReadyRun>[];
    appendReadyRun(runs, ready);
    appendReadyRun(runs, red);
    expect(runs, [ready, red]);
  });

  testWidgets('a move asks for the frames it uncovered and no others', (
    tester,
  ) async {
    final probe = await mount(tester);
    final before = windowAt(0);
    final after = windowAt(1);
    expect(
      after.startIndex,
      greaterThan(before.startIndex),
      reason: 'premise: the bucket moves the window',
    );
    expect(
      after.startIndex,
      lessThan(before.endIndexExclusive),
      reason: 'premise: the two windows share frames',
    );

    probe.asked.clear();
    probe.bucket.value = 1;
    await tester.pump();
    expect(probe.asked, [(before.endIndexExclusive, after.endIndexExclusive)]);

    probe.asked.clear();
    probe.bucket.value = 0;
    await tester.pump();
    expect(probe.asked, [(before.startIndex, after.startIndex)]);
  });

  testWidgets('a move past everything it read asks for its whole window', (
    tester,
  ) async {
    final probe = await mount(tester);
    final far = windowAt(40);
    expect(
      far.startIndex,
      greaterThan(windowAt(0).endIndexExclusive),
      reason: 'premise: nothing shared',
    );

    probe.asked.clear();
    probe.bucket.value = 40;
    await tester.pump();
    expect(probe.asked, [(far.startIndex, far.endIndexExclusive)]);
  });

  testWidgets('every window walked to draws what a fresh read would', (
    tester,
  ) async {
    final probe = await mount(tester);
    for (final bucket in [1, 2, 3, 4, 5, 6, 7, 6, 5, 3, 1, 0, 2, 9, 8, 0]) {
      probe.bucket.value = bucket;
      await tester.pump();
      final window = windowAt(bucket);
      expect(
        probe.drawn(),
        answer(window.startIndex, window.endIndexExclusive),
        reason: 'bucket $bucket: the runs a move carried are the runs a read '
            'gives, cut and joined the same — the gate compares them',
      );
    }
  });

  testWidgets('a signal after a move reads the whole window again', (
    tester,
  ) async {
    final probe = await mount(tester);
    probe.bucket.value = 1;
    await tester.pump();

    probe.asked.clear();
    probe.signal.value += 1;
    final window = windowAt(1);
    expect(
      probe.asked,
      contains((window.startIndex, window.endIndexExclusive)),
      reason: 'what it carried may be what the signal turned',
    );
  });
}
