import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `CustomPaint` that paints the playback view's FRAME.
///
/// Found by what it paints: the bar at the view's foot paints too (유저 답
/// F-296-Q5 — its seat is always there), so 「the CustomPaint under the
/// view」 is two. Three tests spelled that finder out, and all three broke
/// the day the bar stayed.
CustomPaint playbackFramePaint(WidgetTester tester) =>
    tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('canvas-playback-view')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is PlaybackFramePainter,
        ),
      ),
    );

/// What that paint paints with.
PlaybackFramePainter playbackFramePainter(WidgetTester tester) =>
    playbackFramePaint(tester).painter! as PlaybackFramePainter;
