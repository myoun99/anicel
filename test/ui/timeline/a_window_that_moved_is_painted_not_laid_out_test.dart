import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';

/// 🚨frame-axis-box-at-window-size (2026-10-30): a crossing past the window's
/// margin moves where the window stands along the content and nothing else,
/// so a row's axis box and its span layers answer it with a paint — and
/// every piece is still drawn, hit, measured and clipped where the window
/// stands NOW. ↩️Every one of them was laid out again at each crossing,
/// measuring its semantics again with it: 43 on the timeline, 76 on the
/// sheet (24 layers).
void main() {
  // A thousand frames ten pixels each; the window 1200px wide.
  const content = TimelineFrameGeometry(
    frameCellExtent: 10,
    frameStartIndex: 0,
    frameEndIndexExclusive: 1000,
    viewExtentPx: 800,
  );
  TimelineFrameGeometry windowAt(double originPx) =>
      content.windowed(originPx: originPx, extentPx: 1200);

  group('what a layout reads', () {
    final laid = windowAt(2000);
    TimelineFrameGeometry contentWith({
      double cell = 10,
      int start = 0,
      int end = 1000,
      double lead = 0,
      double trail = 0,
      double view = 800,
    }) => TimelineFrameGeometry(
      frameCellExtent: cell,
      frameStartIndex: start,
      frameEndIndexExclusive: end,
      leadingFrameSpacerWidth: lead,
      trailingFrameSpacerWidth: trail,
      viewExtentPx: view,
    );

    test('a change to it is laid out again', () {
      final changes = {
        'a zoom step': contentWith(cell: 11),
        'a row that starts a frame later': contentWith(start: 1),
        'a row that ends a frame sooner': contentWith(end: 999),
        'a lead before the frames': contentWith(lead: 5),
        'a tail after them': contentWith(trail: 5),
      };
      for (final MapEntry(key: what, value: changed) in changes.entries) {
        final geometry = changed.windowed(originPx: 2000, extentPx: 1200);
        expect(geometry.laysOutAs(laid), isFalse, reason: what);
      }
      expect(
        content.windowed(originPx: 2000, extentPx: 1300).laysOutAs(laid),
        isFalse,
        reason: 'a window of another breadth',
      );
      expect(content.laysOutAs(laid), isFalse, reason: 'no window at all');
    });

    test('where the window stands and how far the view reaches are '
        'painted only', () {
      expect(windowAt(1600).laysOutAs(laid), isTrue);
      expect(
        contentWith(
          view: 801,
        ).windowed(originPx: 2000, extentPx: 1200).laysOutAs(laid),
        isTrue,
      );
    });

    test('a lead the origin cannot be added back to exactly stands as '
        'it was', () {
      final lead = contentWith(lead: 0.1);
      final from = lead.windowed(originPx: 1234.5, extentPx: 1200);
      final to = lead.windowed(originPx: 987.6, extentPx: 1200);
      expect(
        from.leadingFrameSpacerWidth + from.windowOriginPx,
        isNot(to.leadingFrameSpacerWidth + to.windowOriginPx),
        reason: 'LIVENESS: adding the origin back is not exact here',
      );

      expect(to.laysOutAs(from), isTrue);
    });
  });

  for (final axis in Axis.values) {
    group(axis.name, () {
      // Frames 210..212 stand at 2100..2120 of the content, 300px into the
      // screen; 190..205 at 1900..2050; 270..290 at 2700..2900.
      late ValueNotifier<TimelineFrameGeometry> handle;
      late List<Rect> spanBClips;
      late List<Rect> spanDClips;
      late List<Offset> spanADrawnAt;
      late int spanATaps;

      Future<void> pumpRow(WidgetTester tester) async {
        handle = ValueNotifier(windowAt(2000));
        addTearDown(handle.dispose);
        spanBClips = [];
        spanDClips = [];
        spanADrawnAt = [];
        spanATaps = 0;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: offsetAlong(axis, along: -1800, across: 0),
                  child: TimelineFrameAxisBox(
                    geometry: handle,
                    crossAxisExtent: 40,
                    axis: axis,
                    child: Semantics(
                      container: true,
                      key: const ValueKey('window'),
                      label: 'window',
                      child: TimelineFrameSpanLayout(
                        geometry: handle,
                        crossAxisExtent: 40,
                        axis: axis,
                        children: [
                          TimelineFrameSpan(
                            placement: const TimelineFrameSpanPlacement(
                              startIndex: 210,
                              endIndexExclusive: 212,
                            ),
                            child: Semantics(
                              container: true,
                              key: const ValueKey('A'),
                              label: 'A',
                              child: GestureDetector(
                                onTap: () => spanATaps += 1,
                                child: CustomPaint(
                                  painter: _PlaceReader(spanADrawnAt),
                                ),
                              ),
                            ),
                          ),
                          TimelineFrameSpan(
                            placement: const TimelineFrameSpanPlacement(
                              startIndex: 190,
                              endIndexExclusive: 205,
                            ),
                            child: CustomPaint(
                              painter: _ClipReader(spanBClips),
                            ),
                          ),
                          TimelineFrameSpan(
                            placement: const TimelineFrameSpanPlacement(
                              startIndex: 270,
                              endIndexExclusive: 290,
                            ),
                            child: CustomPaint(
                              painter: _ClipReader(spanDClips),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      List<RenderBox> rowBoxes(WidgetTester tester) => [
        tester.renderObject<RenderBox>(find.byType(TimelineFrameAxisBox)),
        tester.renderObject<RenderBox>(find.byType(TimelineFrameSpanLayout)),
      ];

      /// Moves the window and says whether the row was left to paint only.
      Future<void> moveTheWindowTo(WidgetTester tester, double origin) async {
        handle.value = windowAt(origin);
        for (final box in rowBoxes(tester)) {
          expect(box.debugNeedsLayout, isFalse, reason: '$box laid out');
          expect(box.debugNeedsPaint, isTrue, reason: '$box painted');
        }
        await tester.pump();
      }

      testWidgets('a window that moved is painted, never laid out, and its '
          'span is drawn, placed and hit where it stood', (tester) async {
        await pumpRow(tester);
        final spanA = find.byKey(const ValueKey('A'));
        expect(partAlong(axis, spanADrawnAt.last), closeTo(300, 1e-6));
        expect(partAlong(axis, tester.getTopLeft(spanA)), closeTo(300, 1e-6));

        for (final origin in [1600.0, 2000.0]) {
          spanADrawnAt.clear();
          await moveTheWindowTo(tester, origin);

          final where = 'window at $origin';
          expect(spanADrawnAt, isNotEmpty, reason: 'LIVENESS: $where');
          final drawn = partAlong(axis, spanADrawnAt.last);
          expect(drawn, closeTo(300, 1e-6), reason: where);
          final placed = partAlong(axis, tester.getTopLeft(spanA));
          expect(placed, closeTo(300, 1e-6), reason: where);
          final taps = spanATaps;
          await tester.tapAt(offsetAlong(axis, along: 310, across: 20));
          await tester.pump();
          expect(spanATaps, taps + 1, reason: where);
        }
      });

      testWidgets('the clip follows the window to the end a span runs past',
          (tester) async {
        await pumpRow(tester);

        // 1600..2800: the 2700..2900 span runs past the window's end.
        await moveTheWindowTo(tester, 1600);
        expect(endAlong(axis, spanDClips.last), closeTo(100, 1));
        expect(startAlong(axis, spanBClips.last), closeTo(-300, 1));

        // 2000..3200: the 1900..2050 span runs in from before its start.
        await moveTheWindowTo(tester, 2000);
        expect(startAlong(axis, spanBClips.last), closeTo(100, 1));
        expect(endAlong(axis, spanDClips.last), closeTo(500, 1));
      });

      testWidgets('the semantics stand where the window moved to', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpRow(tester);
        final window = find.byKey(const ValueKey('window'));
        final spanA = find.byKey(const ValueKey('A'));

        await moveTheWindowTo(tester, 1600);

        expect(
          partAlong(axis, tester.getRect(window).topLeft),
          closeTo(-200, 1e-6),
          reason: 'LIVENESS: the window box is drawn at 1600',
        );
        for (final piece in [window, spanA]) {
          final seen = _seenBySemantics(tester, tester.getSemantics(piece));
          final drawn = tester.getTopLeft(piece);
          expect(seen, offsetMoreOrLessEquals(drawn));
        }
        semantics.dispose();
      });

      testWidgets('a zoom step is laid out', (tester) async {
        await pumpRow(tester);

        handle.value = const TimelineFrameGeometry(
          frameCellExtent: 11,
          frameStartIndex: 0,
          frameEndIndexExclusive: 1000,
          viewExtentPx: 800,
        ).windowed(originPx: 2000, extentPx: 1200);

        for (final box in rowBoxes(tester)) {
          expect(box.debugNeedsLayout, isTrue, reason: '$box');
        }
      });
    });
  }
}

/// Where a semantics node stands on screen: its tree's transforms read up
/// to the root, in device pixels — the root's child carries the device's
/// scale — so back by it.
Offset _seenBySemantics(WidgetTester tester, SemanticsNode node) {
  var rect = node.rect;
  for (SemanticsNode? at = node; at != null; at = at.parent) {
    final transform = at.transform;
    if (transform != null) {
      rect = MatrixUtils.transformRect(transform, rect);
    }
  }
  return rect.topLeft / tester.view.devicePixelRatio;
}

/// Reads, at each paint, where on screen its box is drawn.
class _PlaceReader extends CustomPainter {
  _PlaceReader(this.drawnAt);

  final List<Offset> drawnAt;

  @override
  void paint(Canvas canvas, Size size) => drawnAt.add(
    MatrixUtils.transformPoint(
      Matrix4.fromFloat64List(canvas.getTransform()),
      Offset.zero,
    ),
  );

  @override
  bool shouldRepaint(_PlaceReader oldDelegate) => true;
}

/// Reads, at each paint, the part of its box its canvas can show.
class _ClipReader extends CustomPainter {
  _ClipReader(this.seen);

  final List<Rect> seen;

  @override
  void paint(Canvas canvas, Size size) => seen.add(canvas.getLocalClipBounds());

  @override
  bool shouldRepaint(_ClipReader oldDelegate) => true;
}
