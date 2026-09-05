import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_cut_end_boundary_line.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_playhead.dart';

/// Three timeline pieces the audit left unnamed (2026-09-05): the
/// playhead, the film-end line, and the tint they share an axis rule with.
void main() {
  const metrics = TimelineGridMetrics();

  Future<void> pumpStack(WidgetTester tester, List<Widget> children) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: Stack(children: children),
            ),
          ),
        ),
      );

  Widget playhead({
    int current = 5,
    int start = 0,
    int endExclusive = 20,
    double leading = 0,
    Axis axis = Axis.horizontal,
  }) => TimelinePlayhead(
    currentFrameIndex: current,
    frameStartIndex: start,
    frameEndIndexExclusive: endExclusive,
    leadingFrameSpacerWidth: leading,
    metrics: metrics,
    layerCount: 3,
    axis: axis,
  );

  group('the playhead', () {
    testWidgets('⛔a frame OUTSIDE the built window draws nothing — the '
        'window is what exists, and a playhead pinned to its edge would '
        'lie about where you are', (tester) async {
      await pumpStack(tester, [playhead(current: 40, endExclusive: 20)]);

      expect(
        find.byKey(const ValueKey<String>('timeline-playhead-column')),
        findsNothing,
      );
    });

    testWidgets('a frame inside the window draws the column', (tester) async {
      await pumpStack(tester, [playhead()]);

      expect(
        find.byKey(const ValueKey<String>('timeline-playhead-column')),
        findsOneWidget,
      );
    });

    testWidgets('🚨the offset counts from the window START, not from frame '
        'zero — a scrolled window would otherwise put the playhead a '
        'screenful away', (tester) async {
      await pumpStack(tester, [
        playhead(current: 12, start: 10, endExclusive: 30),
      ]);

      final box = tester.getTopLeft(
        find.byKey(const ValueKey<String>('timeline-playhead-column')),
      );
      expect(box.dx, closeTo(2 * metrics.frameCellWidth, 0.001));
    });

    testWidgets('the leading spacer is added on top of that', (tester) async {
      await pumpStack(tester, [
        playhead(current: 12, start: 10, endExclusive: 30, leading: 50),
      ]);

      final box = tester.getTopLeft(
        find.byKey(const ValueKey<String>('timeline-playhead-column')),
      );
      expect(box.dx, closeTo(50 + 2 * metrics.frameCellWidth, 0.001));
    });

    testWidgets('🚨the X-sheet tints a ROW where the timeline tints a '
        'COLUMN — one offset rule, two axes', (tester) async {
      await pumpStack(tester, [
        playhead(current: 12, start: 10, endExclusive: 30, axis: Axis.vertical),
      ]);

      final box = tester.getTopLeft(
        find.byKey(const ValueKey<String>('timeline-playhead-column')),
      );
      expect(box.dy, closeTo(2 * metrics.frameCellWidth, 0.001));
      expect(box.dx, closeTo(0, 0.001));
    });

    testWidgets('it never takes a pointer — the playhead is a tint, not a '
        'target', (tester) async {
      await pumpStack(tester, [playhead()]);

      expect(
        find.descendant(
          of: find.byType(Stack).first,
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    });

    test('the tint is a LIVE accent read, not a frozen copy', () {
      expect(timelinePlayheadColor, AppColors.accent);
    });
  });

  group('the film-end line', () {
    testWidgets('the horizontal axis puts it at a LEFT offset, full height', (
      tester,
    ) async {
      await pumpStack(tester, [
        timelineCutEndBoundaryLine(left: 120, axis: Axis.horizontal),
      ]);

      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned.left, 120);
      expect(positioned.width, 2);
      expect(positioned.top, 0);
      expect(positioned.bottom, 0);
    });

    testWidgets('🚨the vertical axis puts the SAME number on TOP — the '
        'X-sheet reads the film end down the page', (tester) async {
      await pumpStack(tester, [
        timelineCutEndBoundaryLine(left: 120, axis: Axis.vertical),
      ]);

      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned.top, 120);
      expect(positioned.height, 2);
      expect(positioned.left, 0);
      expect(positioned.right, 0);
    });

    testWidgets('it takes no pointer', (tester) async {
      await pumpStack(tester, [
        timelineCutEndBoundaryLine(left: 10, axis: Axis.horizontal),
      ]);

      expect(
        find.descendant(
          of: find.byType(Stack).first,
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    });

    testWidgets('⛔the NORI-SHIRO boundary is the same drawing in another '
        'colour — what is shared is the drawing, and only that', (
      tester,
    ) async {
      await pumpStack(tester, [
        timelineCutEndBoundaryLine(
          left: 10,
          axis: Axis.horizontal,
          color: AppColors.hairlineStrong,
        ),
      ]);

      final decorated = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
      expect(
        (decorated.decoration as BoxDecoration).color,
        AppColors.hairlineStrong,
      );
    });

    testWidgets('its default is the danger colour — the film STOPS there', (
      tester,
    ) async {
      await pumpStack(tester, [
        timelineCutEndBoundaryLine(left: 10, axis: Axis.horizontal),
      ]);

      final decorated = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
      expect((decorated.decoration as BoxDecoration).color, AppColors.danger);
    });
  });
}
