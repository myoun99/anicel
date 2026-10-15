import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/convex_clip.dart' show convexContains;
import 'package:anicel/src/ui/playback/camera_shot.dart';

/// 🚨A RUN IS CUT ON WHOLE PIXELS (playback-picture-is-not-the-canvas-picture,
/// 유저 10-13: 「배율따라서 끝에 흰 선」).
///
/// The canvas draws its own edge — a pixel it covers in part is its to draw,
/// by the display law — so the cut a run is seen through lies past it: out
/// to the whole device pixels around the outline, cut hard; a turned
/// outline, which has no whole pixels to grow to, a pixel's diagonal out
/// and still anti-aliased. `a_run_draws_the_picture_the_canvas_draws_test`
/// holds the screens that read it to the canvas standing still.
void main() {
  test('a level outline goes out to the whole pixels around it, cut hard', () {
    // At 1.25 its corners are device (0.125, 0.25) and (59.875, 37.875):
    // each inside a pixel.
    final (:corners, :behavior) = shotClipOnScreen(const [
      Offset(0.1, 0.2),
      Offset(47.9, 0.2),
      Offset(47.9, 30.3),
      Offset(0.1, 30.3),
    ], 1.25);

    expect(corners, const [
      Offset.zero,
      Offset(48, 0),
      Offset(48, 30.4),
      Offset(0, 30.4),
    ]);
    expect(behavior, Clip.hardEdge);
  });

  test('an outline already on whole pixels is cut where it lies', () {
    // Device (5, 1) and (60, 38).
    const whole = [
      Offset(4, 0.8),
      Offset(48, 0.8),
      Offset(48, 30.4),
      Offset(4, 30.4),
    ];

    expect(shotClipOnScreen(whole, 1.25).corners, whole);
  });

  test('a turned outline goes out a pixel\'s diagonal, anti-aliased', () {
    // |x − 5| + |y − 5| ≤ 4 at ratio 2: each edge out by √2 / 2 — to ≤ 5.
    final (:corners, :behavior) = shotClipOnScreen(const [
      Offset(5, 1),
      Offset(9, 5),
      Offset(5, 9),
      Offset(1, 5),
    ], 2);

    expect(behavior, Clip.antiAlias);
    expect(convexContains(corners, const Offset(5, 0.01)), isTrue);
    expect(convexContains(corners, const Offset(5, -0.01)), isFalse);
    expect(convexContains(corners, const Offset(2.51, 2.51)), isTrue);
    expect(convexContains(corners, const Offset(2.49, 2.49)), isFalse);
  });
}
