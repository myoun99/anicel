import 'package:anicel/src/ui/playback/canvas_playback_view.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `CustomPaint` that paints the composite view's FRAME.
///
/// Found by what it paints, under the view that paints it: the run's bar
/// paints too (유저 답 F-296-Q5 — its seat is always there), so 「the
/// CustomPaint under the view」 was two, and three tests spelled that
/// finder out and broke the day the bar stayed. ↩️It looked under the run's
/// press (`canvas-playback-view`) while the view held the run's layer; the
/// layer sits over every run in one place now, and the view is a picture
/// alone (playback-plays-the-screen-material).
CustomPaint playbackFramePaint(WidgetTester tester) =>
    tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(CanvasPlaybackView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is PlaybackFramePainter,
        ),
      ),
    );

/// What that paint paints with.
PlaybackFramePainter playbackFramePainter(WidgetTester tester) =>
    playbackFramePaint(tester).painter! as PlaybackFramePainter;
