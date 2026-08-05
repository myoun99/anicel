import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_body_cut_end_boundary.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_grid_stack.dart';

void main() {
  const rowsBodyKey = ValueKey<String>('test-rows-body');
  const playheadKey = ValueKey<String>('test-playhead');
  const cutEndBoundaryKey = ValueKey<String>('timeline-cut-end-boundary');

  group('TimelineFrameGridStack', () {
    testWidgets('renders the provided rows body', (tester) async {
      await _pumpFrameGridStack(tester);

      expect(find.byKey(rowsBodyKey), findsOneWidget);
    });

    testWidgets('renders the body cut-end boundary', (tester) async {
      await _pumpFrameGridStack(tester);

      expect(find.byKey(cutEndBoundaryKey), findsOneWidget);
    });

    testWidgets('passes cut-end boundary left through', (tester) async {
      await _pumpFrameGridStack(tester, cutEndBoundaryLeft: 240);

      final positioned = tester.widget<Positioned>(
        find.descendant(
          of: find.byKey(cutEndBoundaryKey),
          matching: find.byType(Positioned),
        ),
      );

      expect(positioned.left, 240);
    });

    testWidgets('renders the playhead overlay when showPlayhead is true', (
      tester,
    ) async {
      await _pumpFrameGridStack(tester, showPlayhead: true);

      expect(find.byKey(playheadKey), findsOneWidget);
    });

    testWidgets(
      'does not render the playhead overlay when showPlayhead is false',
      (tester) async {
        await _pumpFrameGridStack(tester, showPlayhead: false);

        expect(find.byKey(playheadKey), findsNothing);
      },
    );

    testWidgets('passes playhead overlay position and width through', (
      tester,
    ) async {
      await _pumpFrameGridStack(tester, showPlayhead: true, playheadWidth: 480);

      final positioned = tester.widget<Positioned>(
        find.ancestor(
          of: find.byKey(playheadKey),
          matching: find.byType(Positioned),
        ),
      );

      expect(positioned.left, 0);
      expect(positioned.top, 0);
      expect(positioned.width, 480);
    });

    testWidgets('preserves stack child order', (tester) async {
      await _pumpFrameGridStack(tester, showPlayhead: true);

      final stack = tester.widget<Stack>(find.byType(Stack));

      // The user's layer order (2026-08-02): where the film STOPS is stated
      // over everything, so the out-of-cut wash and the cut-end line are the
      // top layers and the cursor/selection sits under them. (No wash child
      // here — this harness leaves frameCellExtent at 0, which is the
      // "geometry unknown" case the wash stands down for.)
      expect(stack.children, hasLength(3));
      expect(stack.children[0].key, rowsBodyKey);
      final playheadPositioned = stack.children[1] as Positioned;
      // The playhead rides its OWN RepaintBoundary: a cursor move repaints
      // just that layer instead of re-rasterizing the whole grid (the beat
      // lines already had one; the playhead was the odd overlay without).
      final playheadBoundary = playheadPositioned.child as RepaintBoundary;
      expect(playheadBoundary.child!.key, playheadKey);
      expect(stack.children[2], isA<TimelineBodyCutEndBoundary>());
    });

    testWidgets('does not duplicate stable keys', (tester) async {
      await _pumpFrameGridStack(tester);

      expect(find.byKey(cutEndBoundaryKey), findsOneWidget);
      expect(find.byKey(rowsBodyKey), findsOneWidget);
      expect(find.byKey(playheadKey), findsOneWidget);
    });
  });
}

Future<void> _pumpFrameGridStack(
  WidgetTester tester, {
  double cutEndBoundaryLeft = 240,
  bool showPlayhead = true,
  double playheadWidth = 480,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: SizedBox(
          width: 480,
          height: 120,
          child: TimelineFrameGridStack(
            rowsBody: const SizedBox(
              key: ValueKey<String>('test-rows-body'),
              width: 480,
              height: 120,
            ),
            cutEndBoundaryLeft: cutEndBoundaryLeft,
            showPlayhead: showPlayhead,
            playheadWidth: playheadWidth,
            playhead: const SizedBox(
              key: ValueKey<String>('test-playhead'),
              width: 480,
              height: 120,
            ),
          ),
        ),
      ),
    ),
  );
}
