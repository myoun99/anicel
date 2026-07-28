import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_anchor_policy.dart';

/// Shared zoom anchoring: the playhead pins its on-screen spot through a
/// zoom step when visible; off-screen (or absent) playheads fall back to
/// leading-edge anchoring.
void main() {
  double anchorScreenCenter({
    required int frame,
    required double pixelsPerFrame,
    required double offset,
  }) => (frame + 0.5) * pixelsPerFrame - offset;

  test('a visible playhead keeps its exact on-screen position', () {
    const oldPpf = 8.0;
    const newPpf = 16.0;
    const oldOffset = 100.0;
    const viewport = 720.0;
    const playhead = 30; // center at 244 - 100 = 144 on screen

    final next = zoomAnchoredScrollOffset(
      oldOffset: oldOffset,
      oldPixelsPerFrame: oldPpf,
      newPixelsPerFrame: newPpf,
      viewportExtent: viewport,
      anchorFrame: playhead,
    );

    expect(
      anchorScreenCenter(frame: playhead, pixelsPerFrame: newPpf, offset: next),
      anchorScreenCenter(
        frame: playhead,
        pixelsPerFrame: oldPpf,
        offset: oldOffset,
      ),
    );
  });

  test('zooming OUT with a visible playhead also pins it', () {
    const oldPpf = 32.0;
    const newPpf = 8.0;
    const oldOffset = 600.0;
    const viewport = 500.0;
    const playhead = 24; // center at 784 - 600 = 184 on screen

    final next = zoomAnchoredScrollOffset(
      oldOffset: oldOffset,
      oldPixelsPerFrame: oldPpf,
      newPixelsPerFrame: newPpf,
      viewportExtent: viewport,
      anchorFrame: playhead,
    );

    expect(
      anchorScreenCenter(frame: playhead, pixelsPerFrame: newPpf, offset: next),
      anchorScreenCenter(
        frame: playhead,
        pixelsPerFrame: oldPpf,
        offset: oldOffset,
      ),
    );
  });

  test('an off-screen playhead falls back to leading-edge anchoring', () {
    // Playhead far right of the viewport.
    final beyond = zoomAnchoredScrollOffset(
      oldOffset: 0,
      oldPixelsPerFrame: 8,
      newPixelsPerFrame: 16,
      viewportExtent: 400,
      anchorFrame: 500,
    );
    expect(beyond, 0, reason: 'offset scales proportionally (0 stays 0)');

    // Playhead scrolled off to the left.
    final before = zoomAnchoredScrollOffset(
      oldOffset: 800,
      oldPixelsPerFrame: 8,
      newPixelsPerFrame: 16,
      viewportExtent: 400,
      anchorFrame: 2,
    );
    expect(before, 1600, reason: 'proportional: 800 * (16/8)');
  });

  test('no playhead means leading-edge anchoring', () {
    expect(
      zoomAnchoredScrollOffset(
        oldOffset: 120,
        oldPixelsPerFrame: 12,
        newPixelsPerFrame: 6,
        viewportExtent: 400,
        anchorFrame: null,
      ),
      60,
    );
  });

  test('the anchored offset never goes negative', () {
    // Playhead near frame 0, zooming out: pinning would want a negative
    // offset; it clamps to the track start instead.
    final next = zoomAnchoredScrollOffset(
      oldOffset: 10,
      oldPixelsPerFrame: 48,
      newPixelsPerFrame: 4,
      viewportExtent: 800,
      anchorFrame: 0,
    );
    expect(next, 0);
  });

  test('a zero viewport falls back to leading-edge anchoring', () {
    expect(
      zoomAnchoredScrollOffset(
        oldOffset: 100,
        oldPixelsPerFrame: 10,
        newPixelsPerFrame: 20,
        viewportExtent: 0,
        anchorFrame: 3,
      ),
      200,
    );
  });
}
