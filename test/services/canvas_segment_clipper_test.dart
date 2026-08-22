import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/canvas_segment_clipper.dart';

/// The stroke segment clipper clips to the PASTEBOARD, not the stage:
/// off-canvas drawing is real drawing (user feedback — the pointer must
/// work outside the stage exactly like inside it); only the pasteboard's
/// hard wall (one canvas size beyond every edge) cuts segments.
void main() {
  const clipper = CanvasSegmentClipper();
  const size = CanvasSize(width: 100, height: 80);
  // Pasteboard (3×3, H2 유저 확정 2026-08-22): x ∈ [-100, 200),
  // y ∈ [-80, 160). It was 5×5 — the wall moved in, so every figure
  // below moved with it.

  test('crossing the STAGE edge does not clip — off-canvas travel is '
      'drawable pasteboard', () {
    final segment = clipper.clip(
      previous: CanvasPoint(x: 50, y: 40),
      current: CanvasPoint(x: 150, y: 40),
      canvasSize: size,
    );

    expect(segment, isNotNull);
    expect(segment!.start.x, 50);
    expect(segment.end.x, 150, reason: 'no cut at the stage edge (x=100)');
    expect(segment.startsNewVisibleSegment, isFalse);
  });

  test('a segment fully OUTSIDE the stage but on the pasteboard passes '
      'through whole', () {
    final segment = clipper.clip(
      previous: CanvasPoint(x: -50, y: -40),
      current: CanvasPoint(x: -10, y: -20),
      canvasSize: size,
    );

    expect(segment, isNotNull);
    expect(segment!.start.x, -50);
    expect(segment.end.x, -10);
    expect(segment.startsNewVisibleSegment, isFalse);
  });

  test('the pasteboard WALL clips: inside to beyond cuts at the wall', () {
    final segment = clipper.clip(
      previous: CanvasPoint(x: 50, y: 40),
      current: CanvasPoint(x: 450, y: 40),
      canvasSize: size,
    );

    expect(segment, isNotNull);
    expect(segment!.start.x, 50);
    expect(segment.end.x, 200, reason: 'pasteboard right wall = 2×width');
    expect(segment.startsNewVisibleSegment, isFalse);
  });

  test('re-entering from beyond the wall starts a NEW visible segment at '
      'the wall', () {
    final segment = clipper.clip(
      previous: CanvasPoint(x: -350, y: 40),
      current: CanvasPoint(x: 0, y: 40),
      canvasSize: size,
    );

    expect(segment, isNotNull);
    expect(segment!.start.x, -100, reason: 'pasteboard left wall = -1×width');
    expect(segment.end.x, 0);
    expect(segment.startsNewVisibleSegment, isTrue);
  });

  test('fully beyond the wall produces no segment', () {
    final segment = clipper.clip(
      previous: CanvasPoint(x: -500, y: -300),
      current: CanvasPoint(x: -410, y: -270),
      canvasSize: size,
    );

    expect(segment, isNull);
  });
}
