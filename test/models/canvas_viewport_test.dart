import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/viewport_point.dart';

void main() {
  group('CanvasViewport', () {
    test('default viewport is identity transform', () {
      final viewport = CanvasViewport();
      final canvasPoint = CanvasPoint(x: 3, y: 4);
      final viewportPoint = ViewportPoint(x: 3, y: 4);

      expect(viewport.zoom, 1.0);
      expect(viewport.panX, 0.0);
      expect(viewport.panY, 0.0);
      expect(viewport.canvasToViewport(canvasPoint), viewportPoint);
      expect(viewport.viewportToCanvas(viewportPoint), canvasPoint);
    });

    test('copyWith updates zoom', () {
      final viewport = CanvasViewport();

      expect(viewport.copyWith(zoom: 2).zoom, 2);
      expect(viewport.zoom, 1.0);
    });

    test('copyWith updates panX', () {
      final viewport = CanvasViewport();

      expect(viewport.copyWith(panX: 3).panX, 3);
      expect(viewport.panX, 0.0);
    });

    test('copyWith updates panY', () {
      final viewport = CanvasViewport();

      expect(viewport.copyWith(panY: 4).panY, 4);
      expect(viewport.panY, 0.0);
    });

    test('equality includes zoom, panX, and panY', () {
      final viewport = CanvasViewport(zoom: 2, panX: 3, panY: 4);

      expect(viewport, CanvasViewport(zoom: 2, panX: 3, panY: 4));
      expect(viewport.copyWith(zoom: 5), isNot(viewport));
      expect(viewport.copyWith(panX: 5), isNot(viewport));
      expect(viewport.copyWith(panY: 5), isNot(viewport));
    });

    test('toJson/fromJson round-trips', () {
      final viewport = CanvasViewport(zoom: 1.5, panX: -10.25, panY: 20.5);

      expectJsonRoundTrip(viewport, CanvasViewport.fromJson);
    });

    test('canvasToViewport applies zoom only', () {
      final viewport = CanvasViewport(zoom: 2);

      expect(
        viewport.canvasToViewport(CanvasPoint(x: 3, y: 4)),
        ViewportPoint(x: 6, y: 8),
      );
    });

    test('canvasToViewport applies pan only', () {
      final viewport = CanvasViewport(panX: 10, panY: -5);

      expect(
        viewport.canvasToViewport(CanvasPoint(x: 3, y: 4)),
        ViewportPoint(x: 13, y: -1),
      );
    });

    test('canvasToViewport applies zoom and pan together', () {
      final viewport = CanvasViewport(zoom: 2, panX: 10, panY: -5);

      expect(
        viewport.canvasToViewport(CanvasPoint(x: 3, y: 4)),
        ViewportPoint(x: 16, y: 3),
      );
    });

    test('viewportToCanvas applies inverse zoom only', () {
      final viewport = CanvasViewport(zoom: 2);

      expect(
        viewport.viewportToCanvas(ViewportPoint(x: 6, y: 8)),
        CanvasPoint(x: 3, y: 4),
      );
    });

    test('viewportToCanvas applies inverse pan only', () {
      final viewport = CanvasViewport(panX: 10, panY: -5);

      expect(
        viewport.viewportToCanvas(ViewportPoint(x: 13, y: -1)),
        CanvasPoint(x: 3, y: 4),
      );
    });

    test('viewportToCanvas applies inverse zoom and pan together', () {
      final viewport = CanvasViewport(zoom: 2, panX: 10, panY: -5);

      expect(
        viewport.viewportToCanvas(ViewportPoint(x: 16, y: 3)),
        CanvasPoint(x: 3, y: 4),
      );
    });

    test('canvasToViewport then viewportToCanvas returns original point', () {
      final viewport = CanvasViewport(zoom: 1.25, panX: -10.5, panY: 20.25);
      final point = CanvasPoint(x: 3.2, y: -4.4);
      final roundTrip = viewport.viewportToCanvas(
        viewport.canvasToViewport(point),
      );

      expect(roundTrip.x, closeTo(point.x, 0.000000000001));
      expect(roundTrip.y, closeTo(point.y, 0.000000000001));
    });

    test('viewportToCanvas then canvasToViewport returns original point', () {
      final viewport = CanvasViewport(zoom: 1.25, panX: -10.5, panY: 20.25);
      final point = ViewportPoint(x: 3.2, y: -4.4);
      final roundTrip = viewport.canvasToViewport(
        viewport.viewportToCanvas(point),
      );

      expect(roundTrip.x, closeTo(point.x, 0.000000000001));
      expect(roundTrip.y, closeTo(point.y, 0.000000000001));
    });

    test('fitToView centers canvas and preserves aspect ratio', () {
      final viewport = CanvasViewport.fitToView(
        canvasWidth: 100,
        canvasHeight: 50,
        viewportWidth: 300,
        viewportHeight: 200,
        padding: 0,
      );

      expect(viewport.zoom, 3);
      expect(viewport.panX, 0);
      expect(viewport.panY, 25);
    });

    test('fitToCanvasRect centers an off-origin rect in the viewport', () {
      final viewport = CanvasViewport.fitToCanvasRect(
        left: 50,
        top: 100,
        width: 100,
        height: 50,
        viewportWidth: 300,
        viewportHeight: 200,
        padding: 0,
      );

      expect(viewport.zoom, 3);
      // Rect center (100, 125) lands on the viewport center (150, 100).
      final center = viewport.canvasToViewport(CanvasPoint(x: 100, y: 125));
      expect(center.x, closeTo(150, 0.000001));
      expect(center.y, closeTo(100, 0.000001));
    });

    test('zoomedAround preserves the canvas point under the anchor', () {
      final viewport = CanvasViewport(zoom: 2, panX: 10, panY: 20);
      final anchor = ViewportPoint(x: 30, y: 60);
      final before = viewport.viewportToCanvas(anchor);
      final after = viewport.zoomedAround(nextZoom: 4, anchor: anchor);

      expect(after.viewportToCanvas(anchor).x, closeTo(before.x, 0.000001));
      expect(after.viewportToCanvas(anchor).y, closeTo(before.y, 0.000001));
    });

    test('zero zoom throws', () {
      expect(() => CanvasViewport(zoom: 0), throwsArgumentError);
    });

    test('negative zoom throws', () {
      expect(() => CanvasViewport(zoom: -1), throwsArgumentError);
    });

    test('NaN zoom throws', () {
      expect(() => CanvasViewport(zoom: double.nan), throwsArgumentError);
    });

    test('infinite zoom throws', () {
      expect(() => CanvasViewport(zoom: double.infinity), throwsArgumentError);
    });

    test('NaN panX throws', () {
      expect(() => CanvasViewport(panX: double.nan), throwsArgumentError);
    });

    test('NaN panY throws', () {
      expect(() => CanvasViewport(panY: double.nan), throwsArgumentError);
    });

    test('infinite panX throws', () {
      expect(() => CanvasViewport(panX: double.infinity), throwsArgumentError);
    });

    test('infinite panY throws', () {
      expect(() => CanvasViewport(panY: double.infinity), throwsArgumentError);
    });
  });
}
