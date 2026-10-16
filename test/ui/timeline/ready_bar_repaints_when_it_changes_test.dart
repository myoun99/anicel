import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';

/// F-166 (2026-09-26): warm progress ticks once per frame the prerender
/// finishes, and between two strokes it walks the whole cut — nearly every
/// frame of it already green. Every tick repainted the ruler's overlay, and
/// a repaint anywhere in the timeline dock throws the dock's still image
/// away; on the real app the next stroke then painted the whole timeline on
/// every frame. The overlay repaints for a tick only when the runs it would
/// draw differ from the runs it drew.
/// [ready]'s frames in `[start, end)` as stretches — the answer a cache
/// gives the overlay — red where a frame is [unreadable] too.
List<ReadyRun> runsOf(
  Set<int> ready,
  int start,
  int end, {
  Set<int> unreadable = const {},
}) {
  final runs = <ReadyRun>[];
  for (var frame = start; frame < end; frame += 1) {
    if (!ready.contains(frame)) {
      continue;
    }
    final red = unreadable.contains(frame);
    final last = runs.isEmpty ? null : runs.last;
    if (last != null &&
        last.endIndexExclusive == frame &&
        last.unreadable == red) {
      runs.last = (
        startIndex: last.startIndex,
        endIndexExclusive: frame + 1,
        unreadable: red,
      );
    } else {
      runs.add((
        startIndex: frame,
        endIndexExclusive: frame + 1,
        unreadable: red,
      ));
    }
  }
  return runs;
}

void main() {
  Future<RenderCustomPaint> mount(
    WidgetTester tester, {
    required Listenable signal,
    required Set<int> ready,
    Set<int> unreadable = const {},
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 80,
            height: 20,
            child: TimelineRulerCursorOverlay(
              keyValue: 'ready-bar-probe',
              playhead: null,
              repaintSignal: signal,
              windowBucket: ValueNotifier<int>(0),
              viewportMainExtent: 0,
              renderedFrames: 10,
              cellWidth: 8,
              readyRunsIn: (start, end) =>
                  runsOf(ready, start, end, unreadable: unreadable),
            ),
          ),
        ),
      ),
    );
    return tester.renderObject<RenderCustomPaint>(
      find.byKey(const ValueKey<String>('ready-bar-probe')),
    );
  }

  List<ReadyRun> drawnRuns(RenderCustomPaint strip) =>
      (strip.painter! as TimelineRulerCursorOverlayPainter).readyRuns();

  testWidgets('a tick that turns nothing green asks for no paint', (
    tester,
  ) async {
    final signal = ValueNotifier<int>(0);
    final ready = {0, 1, 2};
    final strip = await mount(tester, signal: signal, ready: ready);
    expect(strip.debugNeedsPaint, isFalse);

    signal.value += 1;

    expect(
      strip.debugNeedsPaint,
      isFalse,
      reason: 'the runs read now are the runs on screen — a paint would '
          'draw the same strip and cost the timeline dock its image',
    );
  });

  testWidgets('a tick that turns a frame green repaints the strip', (
    tester,
  ) async {
    final signal = ValueNotifier<int>(0);
    final ready = {0, 1, 2};
    final strip = await mount(tester, signal: signal, ready: ready);

    ready.add(3);
    signal.value += 1;

    expect(strip.debugNeedsPaint, isTrue);
    await tester.pump();
    expect(drawnRuns(strip), [
      (startIndex: 0, endIndexExclusive: 4, unreadable: false),
    ]);
  });

  testWidgets('and one that takes a frame away (a cel edit) repaints it '
      'too', (tester) async {
    final signal = ValueNotifier<int>(0);
    final ready = {0, 1, 2};
    final strip = await mount(tester, signal: signal, ready: ready);

    ready.remove(1);
    signal.value += 1;

    expect(strip.debugNeedsPaint, isTrue);
    await tester.pump();
    expect(drawnRuns(strip), [
      (startIndex: 0, endIndexExclusive: 1, unreadable: false),
      (startIndex: 2, endIndexExclusive: 3, unreadable: false),
    ]);
  });

  // 유저 2026-10-16 (frame-picture-indicator-Q1 b): a cel whose picture data
  // cannot be read paints its frames' stretch of the bar red.
  testWidgets('🚨a tick that turns a green frame red repaints the strip — '
      'the same stretch, another colour', (tester) async {
    final signal = ValueNotifier<int>(0);
    final ready = {0, 1, 2};
    final unreadable = <int>{};
    final strip = await mount(
      tester,
      signal: signal,
      ready: ready,
      unreadable: unreadable,
    );

    unreadable.add(1);
    signal.value += 1;

    expect(
      strip.debugNeedsPaint,
      isTrue,
      reason: 'a gate that compared only where the runs are would keep the '
          'green on screen over a cel that cannot be read',
    );
    await tester.pump();
    expect(drawnRuns(strip), [
      (startIndex: 0, endIndexExclusive: 1, unreadable: false),
      (startIndex: 1, endIndexExclusive: 2, unreadable: true),
      (startIndex: 2, endIndexExclusive: 3, unreadable: false),
    ]);
  });

  testWidgets('🚨a red run is painted red, and the green ones beside it '
      'green', (tester) async {
    final strip = await mount(
      tester,
      signal: ValueNotifier<int>(0),
      ready: {0, 1, 2},
      unreadable: {1},
    );

    expect(
      strip,
      paints
        ..rect(color: TimelineRulerCursorOverlayPainter.readyBarColor)
        ..rect(color: TimelineRulerCursorOverlayPainter.unreadableBarColor)
        ..rect(color: TimelineRulerCursorOverlayPainter.readyBarColor),
    );
  });
}
