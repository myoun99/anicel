import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/canvas_viewport_pan_metrics.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';

/// [CanvasViewportPanMetrics] is the panbar's AXIS PROJECTION and nothing
/// else: the rotated silhouette's span, the paper×3 runway around it, and
/// the pan read as a scroll offset. The THUMB is `AppScrollbarGeometry`,
/// built here the way `AppScrollbar` builds it — the proportional /
/// minimum / round-trip cases belong to `app_scrollbar_test.dart` and are
/// not restated.
void main() {
  AppScrollbarGeometry geometryFor(
    CanvasViewportPanMetrics metrics,
    double trackExtent,
  ) => AppScrollbarGeometry(
    trackExtent: trackExtent,
    viewportExtent: metrics.visibleExtent,
    contentExtent: metrics.scaledContentExtent,
    offset: metrics.scrollOffset,
    minThumbExtent: AppScrollbarThumb.minimum,
  );

  group('CanvasViewportPanMetrics', () {
    test('a tiny track still reads finite through the shared geometry', () {
      for (final trackExtent in <double>[0, 0.5, 1, 12, 23.9]) {
        final metrics = CanvasViewportPanMetrics(
          axis: Axis.horizontal,
          viewport: CanvasViewport(zoom: 4, panX: -10),
          editorViewportSize: const Size(100, 80),
          canvasSize: const CanvasSize(width: 300, height: 200),
        );
        final geometry = geometryFor(metrics, trackExtent);

        expect(geometry.thumbExtent.isFinite, isTrue);
        expect(geometry.thumbStart.isFinite, isTrue);
        expect(geometry.thumbTravel.isFinite, isTrue);
        expect(geometry.thumbExtent, inInclusiveRange(0, trackExtent));
        expect(geometry.thumbStart, inInclusiveRange(0, geometry.thumbTravel));
      }
    });

    test('no-scroll content cannot scroll and drag preserves centered fit '
        'pan', () {
      final viewport = CanvasViewport(zoom: 0.5, panX: 25, panY: 30);
      final metrics = CanvasViewportPanMetrics(
        axis: Axis.horizontal,
        viewport: viewport,
        editorViewportSize: const Size(300, 300),
        canvasSize: const CanvasSize(width: 100, height: 100),
      );

      // Paper×3 runway (UI-R18 #16) still loses to a much larger
      // viewport here (150px span vs 300px panel) — no scroll, and
      // drags keep the centered fit pan untouched.
      expect(geometryFor(metrics, 200).canScroll, isFalse);
      expect(metrics.maxScroll, 0);
      expect(metrics.scaledContentExtent, closeTo(150, 1e-6));
      expect(metrics.viewportForScroll(50), viewport);
    });

    test('a horizontal scroll offset maps to meaningful panX movement', () {
      final metrics = CanvasViewportPanMetrics(
        axis: Axis.horizontal,
        viewport: CanvasViewport(zoom: 2),
        editorViewportSize: const Size(100, 100),
        canvasSize: const CanvasSize(width: 300, height: 300),
      );

      final next = metrics.viewportForScroll(metrics.maxScroll / 2);

      // Content = paper×3 (UI-R18 #16): 600·3 − 100 viewport.
      expect(metrics.maxScroll, 1700);
      expect(next.panX, lessThan(-100));
      expect(next.panY, 0);
    });

    test('a vertical scroll offset maps to meaningful panY movement', () {
      final metrics = CanvasViewportPanMetrics(
        axis: Axis.vertical,
        viewport: CanvasViewport(zoom: 2),
        editorViewportSize: const Size(100, 100),
        canvasSize: const CanvasSize(width: 300, height: 300),
      );

      final next = metrics.viewportForScroll(metrics.maxScroll / 2);

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
      );

      expect(metrics.scaledContentExtent, closeTo(600, 1e-6));
      expect(metrics.maxScroll, closeTo(450, 1e-6));
    });

    test('a thumb position round-trips under rotation/flip', () {
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
      );
      final geometry = geometryFor(metrics, 100);
      expect(geometry.canScroll, isTrue);

      // Panning to a thumb position and re-measuring reads the SAME thumb
      // position back — the offset bookkeeping is consistent.
      final target = geometry.thumbTravel / 2;
      final panned = metrics.viewportForScroll(
        geometry.offsetForThumbStart(target),
      );
      final remeasured = CanvasViewportPanMetrics(
        axis: Axis.horizontal,
        viewport: panned,
        editorViewportSize: const Size(120, 120),
        canvasSize: const CanvasSize(width: 300, height: 200),
      );
      expect(geometryFor(remeasured, 100).thumbStart, closeTo(target, 1e-6));
      // Rotation and flip survive the panbar drag untouched.
      expect(panned.rotationDegrees, viewport.rotationDegrees);
      expect(panned.flipHorizontal, viewport.flipHorizontal);
    });
  });
}
