import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/viewport_point.dart';

/// P8: the view rotation/flip live in the SAME coordinate authority as
/// zoom/pan — round trips, anchored operations and the delta mapping must
/// all agree by construction.
void main() {
  const epsilon = 1e-9;

  final assortedViewports = [
    CanvasViewport(),
    CanvasViewport(zoom: 2, panX: 40, panY: -12),
    CanvasViewport(rotationDegrees: 30),
    CanvasViewport(flipHorizontal: true),
    CanvasViewport(zoom: 0.5, panX: -8, panY: 99, rotationDegrees: -75),
    CanvasViewport(
      zoom: 3.2,
      panX: 17,
      panY: 5,
      rotationDegrees: 143,
      flipHorizontal: true,
    ),
    CanvasViewport(rotationDegrees: 450, flipHorizontal: true),
  ];

  final assortedPoints = [
    CanvasPoint(x: 0, y: 0),
    CanvasPoint(x: 100, y: 50),
    CanvasPoint(x: -33.5, y: 12.25),
    CanvasPoint(x: 0.001, y: -9999),
  ];

  test('canvasToViewport ∘ viewportToCanvas is identity everywhere', () {
    for (final viewport in assortedViewports) {
      for (final point in assortedPoints) {
        final there = viewport.canvasToViewport(point);
        final back = viewport.viewportToCanvas(there);
        expect(back.x, closeTo(point.x, 1e-6), reason: '$viewport $point');
        expect(back.y, closeTo(point.y, 1e-6), reason: '$viewport $point');
      }
    }
  });

  test('90° + flip lands exactly (the P8 landing pin)', () {
    // flip: (3,4) → (−3,4); rotate 90° cw (y-down): (x,y) → (−y,x) =
    // (−4,−3); zoom 2 → (−8,−6); pan (10,20) → (2,14).
    final viewport = CanvasViewport(
      zoom: 2,
      panX: 10,
      panY: 20,
      rotationDegrees: 90,
      flipHorizontal: true,
    );
    final mapped = viewport.canvasToViewport(CanvasPoint(x: 3, y: 4));
    expect(mapped.x, closeTo(2, epsilon));
    expect(mapped.y, closeTo(14, epsilon));
  });

  test('rotation without flip lands exactly', () {
    // rotate 90° cw: (3,4) → (−4,3); zoom 1, pan 0.
    final viewport = CanvasViewport(rotationDegrees: 90);
    final mapped = viewport.canvasToViewport(CanvasPoint(x: 3, y: 4));
    expect(mapped.x, closeTo(-4, epsilon));
    expect(mapped.y, closeTo(3, epsilon));
  });

  test('anchored operations keep the canvas point under the anchor', () {
    final anchor = ViewportPoint(x: 321, y: 87);
    for (final viewport in assortedViewports) {
      final before = viewport.viewportToCanvas(anchor);
      for (final next in [
        viewport.zoomedAround(nextZoom: viewport.zoom * 1.7, anchor: anchor),
        viewport.rotatedAround(
          nextRotationDegrees: viewport.rotationDegrees + 37,
          anchor: anchor,
        ),
        viewport.flippedAround(anchor: anchor),
      ]) {
        final after = next.viewportToCanvas(anchor);
        expect(after.x, closeTo(before.x, 1e-6), reason: '$viewport → $next');
        expect(after.y, closeTo(before.y, 1e-6), reason: '$viewport → $next');
      }
    }
  });

  test('flippedAround toggles the flag both ways', () {
    final anchor = ViewportPoint(x: 10, y: 10);
    final flipped = CanvasViewport().flippedAround(anchor: anchor);
    expect(flipped.flipHorizontal, isTrue);
    expect(flipped.flippedAround(anchor: anchor).flipHorizontal, isFalse);
  });

  test('viewportDeltaToCanvasDelta matches the point mapping difference', () {
    for (final viewport in assortedViewports) {
      const dx = 13.0, dy = -7.5;
      final base = viewport.canvasToViewport(CanvasPoint(x: 5, y: 6));
      final moved = viewport.viewportToCanvas(
        ViewportPoint(x: base.x + dx, y: base.y + dy),
      );
      final delta = viewport.viewportDeltaToCanvasDelta(dx: dx, dy: dy);
      expect(delta.x, closeTo(moved.x - 5, 1e-6), reason: '$viewport');
      expect(delta.y, closeTo(moved.y - 6, 1e-6), reason: '$viewport');
    }
  });

  test('json omits defaults and round-trips rotation/flip', () {
    expect(CanvasViewport().toJson().containsKey('rotation'), isFalse);
    expect(CanvasViewport().toJson().containsKey('flipH'), isFalse);

    final viewport = CanvasViewport(
      zoom: 2,
      panX: 1,
      panY: 2,
      rotationDegrees: -30,
      flipHorizontal: true,
    );
    final restored = CanvasViewport.fromJson(viewport.toJson());
    expect(restored, viewport);

    // A legacy payload (no rotation keys) loads level and unflipped.
    final legacy = CanvasViewport.fromJson({'zoom': 2.0, 'panX': 3.0});
    expect(legacy.rotationDegrees, 0);
    expect(legacy.flipHorizontal, isFalse);
  });

  test('equality and hash include rotation and flip', () {
    expect(
      CanvasViewport(rotationDegrees: 15),
      isNot(equals(CanvasViewport())),
    );
    expect(
      CanvasViewport(flipHorizontal: true),
      isNot(equals(CanvasViewport())),
    );
    expect(
      CanvasViewport(rotationDegrees: 15, flipHorizontal: true),
      CanvasViewport(rotationDegrees: 15, flipHorizontal: true),
    );
  });

  test('fit factories reset rotation and flip (v1: Fit straightens)', () {
    final fitted = CanvasViewport.fitToView(
      canvasWidth: 100,
      canvasHeight: 100,
      viewportWidth: 400,
      viewportHeight: 400,
    );
    expect(fitted.rotationDegrees, 0);
    expect(fitted.flipHorizontal, isFalse);
  });

  test('non-finite rotation throws', () {
    expect(
      () => CanvasViewport(rotationDegrees: double.nan),
      throwsArgumentError,
    );
  });
}
