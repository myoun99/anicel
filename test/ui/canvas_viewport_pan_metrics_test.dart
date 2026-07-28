import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/canvas_viewport_pan_metrics.dart';

void main() {
  group('CanvasViewportPanMetrics', () {
    test('tiny track extent produces finite thumb values within bounds', () {
      for (final trackExtent in <double>[0, 0.5, 1, 12, 23.9]) {
        final metrics = CanvasViewportPanMetrics(
          axis: Axis.horizontal,
          viewport: CanvasViewport(zoom: 4, panX: -10),
          editorViewportSize: const Size(100, 80),
          canvasSize: const CanvasSize(width: 300, height: 200),
          trackExtent: trackExtent,
        );

        expect(metrics.thumbExtent.isFinite, isTrue);
        expect(metrics.thumbStart.isFinite, isTrue);
        expect(metrics.thumbTravel.isFinite, isTrue);
        expect(metrics.thumbExtent, inInclusiveRange(0, trackExtent));
        expect(metrics.thumbStart, inInclusiveRange(0, metrics.thumbTravel));
      }
    });

    test(
      'no-scroll content cannot scroll and drag preserves centered fit pan',
      () {
        final viewport = CanvasViewport(zoom: 0.5, panX: 25, panY: 30);
        final metrics = CanvasViewportPanMetrics(
          axis: Axis.horizontal,
          viewport: viewport,
          editorViewportSize: const Size(300, 300),
          canvasSize: const CanvasSize(width: 100, height: 100),
          trackExtent: 200,
        );

        // Paper×3 runway (UI-R18 #16) still loses to a much larger
        // viewport here (150px span vs 300px panel) — no scroll, and
        // drags keep the centered fit pan untouched.
        expect(metrics.canScroll, isFalse);
        expect(metrics.maxScroll, 0);
        expect(metrics.scaledContentExtent, closeTo(150, 1e-6));
        expect(metrics.thumbDeltaToPanDelta(100), viewport);
        expect(metrics.panToThumb(50), viewport);
      },
    );

    test('horizontal drag maps thumb delta to meaningful panX movement', () {
      final metrics = CanvasViewportPanMetrics(
        axis: Axis.horizontal,
        viewport: CanvasViewport(zoom: 2),
        editorViewportSize: const Size(100, 100),
        canvasSize: const CanvasSize(width: 300, height: 300),
        trackExtent: 100,
      );

      final next = metrics.thumbDeltaToPanDelta(20);

      // Content = paper×3 (UI-R18 #16): 600·3 − 100 viewport.
      expect(metrics.maxScroll, 1700);
      expect(next.panX, lessThan(-100));
      expect(next.panY, 0);
    });

    test('vertical drag maps thumb delta to meaningful panY movement', () {
      final metrics = CanvasViewportPanMetrics(
        axis: Axis.vertical,
        viewport: CanvasViewport(zoom: 2),
        editorViewportSize: const Size(100, 100),
        canvasSize: const CanvasSize(width: 300, height: 300),
        trackExtent: 100,
      );

      final next = metrics.thumbDeltaToPanDelta(20);

      expect(metrics.maxScroll, 1700);
      expect(next.panY, lessThan(-100));
      expect(next.panX, 0);
    });

    test('a 90° rotated view tracks the rotated AABB (P8)', () {
      // 300×100 canvas rotated 90°: the horizontal footprint becomes the
      // canvas HEIGHT (100·zoom = 200); the paper×3 runway (UI-R18 #16)
      // triples the scrollable span around it.
      final metrics = CanvasViewportPanMetrics(
        axis: Axis.horizontal,
        viewport: CanvasViewport(zoom: 2, rotationDegrees: 90),
        editorViewportSize: const Size(150, 150),
        canvasSize: const CanvasSize(width: 300, height: 100),
        trackExtent: 100,
      );

      expect(metrics.scaledContentExtent, closeTo(600, 1e-6));
      expect(metrics.maxScroll, closeTo(450, 1e-6));
    });

    test('panToThumb round-trips under rotation/flip', () {
      final viewport = CanvasViewport(
        zoom: 2,
        panX: -40,
        panY: 15,
        rotationDegrees: 30,
        flipHorizontal: true,
      );
      final metrics = CanvasViewportPanMetrics(
        axis: Axis.horizontal,
        viewport: viewport,
        editorViewportSize: const Size(120, 120),
        canvasSize: const CanvasSize(width: 300, height: 200),
        trackExtent: 100,
      );
      expect(metrics.canScroll, isTrue);

      // Panning to a thumb position and re-measuring reads the SAME thumb
      // position back — the offset bookkeeping is consistent.
      final target = metrics.thumbTravel / 2;
      final panned = metrics.panToThumb(target);
      final remeasured = CanvasViewportPanMetrics(
        axis: Axis.horizontal,
        viewport: panned,
        editorViewportSize: const Size(120, 120),
        canvasSize: const CanvasSize(width: 300, height: 200),
        trackExtent: 100,
      );
      expect(remeasured.thumbStart, closeTo(target, 1e-6));
      // Rotation and flip survive the panbar drag untouched.
      expect(panned.rotationDegrees, viewport.rotationDegrees);
      expect(panned.flipHorizontal, viewport.flipHorizontal);
    });
  });
}
