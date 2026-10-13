import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';

/// 🚨I-57 (10-13, profile, the user's project): a span longer than its row's
/// window — a sound running on far past the cut — is drawn as far as the
/// window, so a painter that reads its canvas's clip knows what of it can be
/// seen. The waveform built a long sound's whole band at every paint: 6–20ms
/// of a cut crossing's frame.
///
/// Past the window is off-screen by construction, so the clip may hide
/// nothing anyone sees: only a WINDOWED row is clipped, only along the frame
/// axis, and a span inside the window is drawn as it always was.
void main() {
  // A thousand frames ten pixels each; the window 300px wide, 200px in.
  const content = TimelineFrameGeometry(
    frameCellExtent: 10,
    frameStartIndex: 0,
    frameEndIndexExclusive: 1000,
  );
  final windowed = content.windowed(originPx: 200, extentPx: 300);

  for (final axis in Axis.values) {
    final horizontal = axis == Axis.horizontal;
    double from(Rect clip) => horizontal ? clip.left : clip.top;
    double to(Rect clip) => horizontal ? clip.right : clip.bottom;
    double fromAcross(Rect clip) => horizontal ? clip.top : clip.left;

    Future<Rect> clipSeenBy(
      WidgetTester tester,
      TimelineFrameGeometry geometry, {
      int startIndex = 0,
      int endIndexExclusive = 1000,
    }) async {
      final seen = <Rect>[];
      final main = geometry.mainExtent;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: horizontal ? main : 40,
              height: horizontal ? 40 : main,
              child: TimelineFrameSpanLayout(
                geometry: ValueNotifier(geometry),
                crossAxisExtent: 40,
                axis: axis,
                children: [
                  TimelineFrameSpan(
                    placement: TimelineFrameSpanPlacement(
                      startIndex: startIndex,
                      endIndexExclusive: endIndexExclusive,
                    ),
                    child: CustomPaint(painter: _ClipReader(seen)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(seen, isNotEmpty, reason: 'LIVENESS: the span painted');
      return seen.last;
    }

    testWidgets('${axis.name}: a span past a windowed row\'s box is drawn '
        'as far as the window', (tester) async {
      final clip = await clipSeenBy(tester, windowed);

      // The span starts 200px before the window, so the window is 200..500
      // of the span's own box.
      expect(from(clip), closeTo(200, 1));
      expect(to(clip), closeTo(500, 1));
      expect(
        fromAcross(clip),
        lessThan(-1000),
        reason: 'across the axis the span reaches as far as it always did',
      );
    });

    testWidgets('${axis.name}: a span that runs past one end of the window '
        'is clipped at that end', (tester) async {
      // Frames 10..30 stand at -100..100 of the window: in from before it.
      final comingIn = await clipSeenBy(
        tester,
        windowed,
        startIndex: 10,
        endIndexExclusive: 30,
      );
      expect(from(comingIn), closeTo(100, 1));

      // Frames 40..60 stand at 200..400: out past its end.
      final goingOut = await clipSeenBy(
        tester,
        windowed,
        startIndex: 40,
        endIndexExclusive: 60,
      );
      expect(to(goingOut), closeTo(100, 1));
    });

    testWidgets('${axis.name}: a span inside the window is not clipped', (
      tester,
    ) async {
      // Frames 25..45 stand at 50..250 of the window.
      final clip = await clipSeenBy(
        tester,
        windowed,
        startIndex: 25,
        endIndexExclusive: 45,
      );

      expect(from(clip), lessThan(-1000));
    });

    testWidgets('${axis.name}: a box that is not windowed draws its spans '
        'whole', (tester) async {
      final clip = await clipSeenBy(tester, content);

      expect(from(clip), lessThan(-1000));
      expect(to(clip), greaterThan(10000));
    });
  }
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
