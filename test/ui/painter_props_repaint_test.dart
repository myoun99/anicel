// EVERY PAINTER'S INPUTS ARE ONE VALUE. A changed input repaints; a
// rebuilt-but-equal painter does not; and an input declared to compare by
// IDENTITY repaints even for an equal-by-value instance — the three
// questions `props` answers, asked here of the real painters.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/selection_ants_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

const _size = CanvasSize(width: 100, height: 100);

CameraFramePainter _camera({double dim = 0.5, bool handles = false}) =>
    CameraFramePainter(
      pose: CameraPose(center: CanvasPoint(x: 10, y: 10)),
      cameraFrameSize: _size,
      viewport: CanvasViewport(),
      dimOpacity: dim,
      outlineColor: const Color(0xFF00FF00),
      showHandles: handles,
    );

TimelineGridSheetPainter _sheet({
  double cell = 8,
  int fps = 24,
  Color activeRow = const Color(0xFF303030),
}) => TimelineGridSheetPainter(
  frameCellExtent: cell,
  framesPerSecond: fps,
  colorScheme: const ColorScheme.light(),
  ground: const Color(0xFF202020),
  // A FRESH list every call, as every grid build hands one over.
  rows: TimelineGridRows([
    (extent: 28, ground: const Color(0xFF202020)),
    (extent: 28, ground: activeRow),
  ]),
);

SelectionAntsPainter _ants(List<CanvasSelectionShape> shapes) =>
    SelectionAntsPainter(
      repaint: const AlwaysStoppedAnimation<double>(0),
      viewport: CanvasViewport(),
      committedRegion: null,
      screenOffset: Offset.zero,
      marqueeShapes: shapes,
      openTrail: const <CanvasPoint>[],
    );

void main() {
  group('a changed prop repaints, an equal one does not', () {
    test('CameraFramePainter', () {
      final old = _camera();
      expect(_camera().shouldRepaint(old), isFalse);
      expect(_camera(dim: 0.6).shouldRepaint(old), isTrue);
      expect(_camera(handles: true).shouldRepaint(old), isTrue);
    });

    test('TimelineGridSheetPainter', () {
      final old = _sheet();
      expect(_sheet().shouldRepaint(old), isFalse);
      expect(_sheet(cell: 9).shouldRepaint(old), isTrue);
      expect(_sheet(fps: 30).shouldRepaint(old), isTrue);
      // I-44: the rows are a VALUE — the grid rebuilds its area for reasons
      // that move no ground (a row window sliding), and a list compared by
      // identity would re-record the content-long sheet every time. A
      // ground that did move repaints.
      expect(
        _sheet(activeRow: const Color(0xFF404040)).shouldRepaint(old),
        isTrue,
      );
    });
  });

  group('a painter with ONE input still declares it', () {
    TimelineFrameRulerPainter ruler({int currentFrameIndex = -1}) =>
        TimelineFrameRulerPainter(
          scale: TimelineRulerScale(
            frameStartIndex: 0,
            frameEndIndexExclusive: 30,
            currentFrameIndex: currentFrameIndex,
            playbackFrameCount: 30,
            leadingFrameSpacer: 0,
            axis: Axis.horizontal,
            crossExtent: TimelineGridMetrics.defaults.layerRowHeight,
            metrics: TimelineGridMetrics.defaults,
            colorScheme: const ColorScheme.light(),
            face: const TextStyle(),
            numberType: TimelineFrameRulerPainter.numberType,
          ),
        );

    test(
      'TimelineFrameRulerPainter: a rebuilt equal scale does not repaint',
      () {
        final old = ruler();
        expect(ruler().shouldRepaint(old), isFalse);
        expect(ruler(currentFrameIndex: 3).shouldRepaint(old), isTrue);
      },
    );
  });

  group('an identity-declared prop repaints for an equal-by-value one', () {
    test('BitmapSurfacePainter: two surfaces of the same shape', () {
      // THE LAW `ByIdentity` EXISTS FOR: these two surfaces hold the same
      // (empty) tiles and would compare EQUAL by value, which is exactly
      // the megabytes-per-pointer-move comparison the painter refuses.
      final surface = BitmapSurface(canvasSize: _size);
      final twin = BitmapSurface(canvasSize: _size);
      expect(
        BitmapSurfacePainter(
          surface: surface,
        ).shouldRepaint(BitmapSurfacePainter(surface: surface)),
        isFalse,
      );
      expect(
        BitmapSurfacePainter(
          surface: twin,
        ).shouldRepaint(BitmapSurfacePainter(surface: surface)),
        isTrue,
      );
      // And a plain value prop beside it still decides on its own.
      expect(
        BitmapSurfacePainter(
          surface: surface,
          showTransparentBackground: false,
        ).shouldRepaint(BitmapSurfacePainter(surface: surface)),
        isTrue,
      );
    });
  });

  group('a list-declared prop compares element-wise', () {
    test('SelectionAntsPainter: a rebuilt marquee list is the same input', () {
      final shape = CanvasSelectionShape.rect(
        left: 0,
        top: 0,
        right: 10,
        bottom: 10,
      );
      final old = _ants(<CanvasSelectionShape>[shape]);
      expect(_ants(<CanvasSelectionShape>[shape]).shouldRepaint(old), isFalse);
      expect(_ants(const <CanvasSelectionShape>[]).shouldRepaint(old), isTrue);
    });
  });
}
