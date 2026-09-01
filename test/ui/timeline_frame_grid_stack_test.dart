import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_body_cut_end_boundary.dart';
import 'package:anicel/src/ui/timeline/timeline_body_norishiro_boundary.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_grid_stack.dart';

void main() {
  const rowsBodyKey = ValueKey<String>('test-rows-body');
  const playheadKey = ValueKey<String>('test-playhead');
  const beatLinesKey = ValueKey<String>('test-beat-lines');
  const cutEndBoundaryKey = ValueKey<String>('timeline-cut-end-boundary');

  group('TimelineFrameGridStack', () {
    testWidgets('renders the provided rows body', (tester) async {
      await _pumpFrameGridStack(tester);

      expect(find.byKey(rowsBodyKey), findsOneWidget);
    });

    testWidgets('the static cut-end line sits at the cut end', (tester) async {
      // ONE fact, derived: playback frames × cell extent. The stack used to
      // take the same number as a second parameter and trust it to agree.
      await _pumpFrameGridStack(tester, frameCellExtent: 24, frameCount: 10);

      final positioned = tester.widget<Positioned>(
        find.descendant(
          of: find.byKey(cutEndBoundaryKey),
          matching: find.byType(Positioned),
        ),
      );

      expect(positioned.left, 240);
    });

    testWidgets('the playhead spans the frame axis — horizontal', (
      tester,
    ) async {
      await _pumpFrameGridStack(tester, playheadExtent: 480);

      final positioned = tester.widget<Positioned>(
        find.ancestor(
          of: find.byKey(playheadKey),
          matching: find.byType(Positioned),
        ),
      );

      expect(positioned.left, 0);
      expect(positioned.top, 0);
      expect(positioned.width, 480);
      expect(positioned.height, isNull);
    });

    testWidgets('the playhead spans the frame axis — vertical', (tester) async {
      await _pumpFrameGridStack(
        tester,
        axis: Axis.vertical,
        playheadExtent: 480,
      );

      final positioned = tester.widget<Positioned>(
        find.ancestor(
          of: find.byKey(playheadKey),
          matching: find.byType(Positioned),
        ),
      );

      expect(positioned.left, 0);
      expect(positioned.top, 0);
      expect(positioned.height, 480);
      expect(positioned.width, isNull);
    });

    testWidgets('every overlay is turned with the stack', (tester) async {
      await _pumpFrameGridStack(tester, axis: Axis.vertical);

      final wash =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) =>
                          w is CustomPaint &&
                          w.painter is TimelineOutsideCutWashPainter,
                    ),
                  )
                  .painter
              as TimelineOutsideCutWashPainter;
      expect(wash.axis, Axis.vertical);
      expect(
        tester
            .widget<TimelineBodyNoriShiroBoundary>(
              find.byType(TimelineBodyNoriShiroBoundary),
            )
            .axis,
        Axis.vertical,
      );
      expect(
        tester
            .widget<TimelineBodyCutEndBoundary>(
              find.byType(TimelineBodyCutEndBoundary),
            )
            .axis,
        Axis.vertical,
      );
    });

    testWidgets('preserves stack child order', (tester) async {
      await _pumpFrameGridStack(tester);

      final stack = tester.widget<Stack>(find.byType(Stack));

      // The user's layer order (2026-08-02): where the film STOPS is stated
      // over everything, so the wash, the のりしろ mark and the cut-end line
      // are the top layers and the cursor/selection sits under them. No grip
      // here — nothing is being trimmed.
      expect(stack.children, hasLength(6));
      expect((stack.children[0] as Positioned).child, isA<IgnorePointer>());
      expect(stack.children[1].key, rowsBodyKey);
      final playheadPositioned = stack.children[2] as Positioned;
      // The playhead rides its OWN RepaintBoundary: a cursor move repaints
      // just that layer instead of re-rasterizing the whole grid (the beat
      // lines have one too, from the same hand).
      final playheadBoundary = playheadPositioned.child as RepaintBoundary;
      expect(playheadBoundary.child!.key, playheadKey);
      expect(stack.children[3], isA<Positioned>());
      expect(stack.children[4], isA<TimelineBodyNoriShiroBoundary>());
      expect(stack.children[5], isA<TimelineBodyCutEndBoundary>());
    });

    testWidgets('the beat lines get their repaint boundary from the stack', (
      tester,
    ) async {
      await _pumpFrameGridStack(tester);

      // The DIRECT wrap, not "some ancestor" — MaterialApp puts boundaries
      // of its own above the stack.
      final stack = tester.widget<Stack>(find.byType(Stack));
      final slot = (stack.children[0] as Positioned).child as IgnorePointer;
      final boundary = slot.child as RepaintBoundary;
      expect(boundary.child!.key, beatLinesKey);
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
  Axis axis = Axis.horizontal,
  double playheadExtent = 480,
  double frameCellExtent = 24,
  int frameCount = 10,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: SizedBox(
          width: 480,
          height: 480,
          child: TimelineFrameGridStack(
            axis: axis,
            rowsBody: const SizedBox(
              key: ValueKey<String>('test-rows-body'),
              width: 480,
              height: 480,
            ),
            beatLines: const SizedBox(
              key: ValueKey<String>('test-beat-lines'),
              width: 480,
              height: 480,
            ),
            playheadExtent: playheadExtent,
            playhead: const SizedBox(
              key: ValueKey<String>('test-playhead'),
              width: 480,
              height: 480,
            ),
            frameCellExtent: frameCellExtent,
            playbackFrameCount: frameCount,
          ),
        ),
      ),
    ),
  );
}
