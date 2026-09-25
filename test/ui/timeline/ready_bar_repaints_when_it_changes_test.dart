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
void main() {
  Future<RenderCustomPaint> mount(
    WidgetTester tester, {
    required Listenable signal,
    required Set<int> ready,
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
              isFrameReady: ready.contains,
            ),
          ),
        ),
      ),
    );
    return tester.renderObject<RenderCustomPaint>(
      find.byKey(const ValueKey<String>('ready-bar-probe')),
    );
  }

  List<({int startIndex, int endIndexExclusive})> drawnRuns(
    RenderCustomPaint strip,
  ) => (strip.painter! as TimelineRulerCursorOverlayPainter).readyRuns();

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
    expect(drawnRuns(strip), [(startIndex: 0, endIndexExclusive: 4)]);
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
      (startIndex: 0, endIndexExclusive: 1),
      (startIndex: 2, endIndexExclusive: 3),
    ]);
  });
}
