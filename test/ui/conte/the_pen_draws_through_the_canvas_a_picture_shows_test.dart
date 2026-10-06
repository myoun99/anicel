import 'dart:ui' show Offset, Rect;

import 'package:flutter/painting.dart' show MatrixUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/layer_pose_paint.dart';
import 'package:anicel/src/services/viewport_transform_matrix.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/conte/conte_picture_ink.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/sheet_painting.dart' show pictureCanvasViewport;
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// The pen goes through a picture onto the very canvas the picture shows:
/// the camera's view at its frame — or, where the cell's camera moves, the
/// canvas that camera sweeps (유저 2026-09-29: 「일단 카메라 팬대로 해당
/// 코마에서 보여주고」), which is where the print lays the picture too.
void main() {
  // The camera's shape, as every picture's frame is (`contePictureOf`).
  const frame = Rect.fromLTWH(100, 50, 320, 180);
  final camera = (
    pose: CameraPose(center: CanvasPoint(x: 80, y: 45)),
    frameSize: const CanvasSize(width: 160, height: 90),
  );

  SheetPicture pictureOver(Rect? region) => SheetPicture(
    SheetPaintLayer.picture,
    cutId: 'c',
    pictureFrame: 0,
    slot: frame,
    frame: frame,
    canvasRegion: region,
  );

  void expectLands(Offset actual, Offset expected, String reason) {
    expect(actual.dx, closeTo(expected.dx, 1e-9), reason: reason);
    expect(actual.dy, closeTo(expected.dy, 1e-9), reason: reason);
  }

  test('a still camera\'s picture: the camera\'s frame fills the picture', () {
    final toPaper = conteCanvasToPaper(pictureOver(null), camera);
    expectLands(
      MatrixUtils.transformPoint(toPaper, Offset.zero),
      frame.topLeft,
      'the camera frame\'s corner',
    );
    expectLands(
      MatrixUtils.transformPoint(toPaper, const Offset(160, 90)),
      frame.bottomRight,
      'and the opposite one',
    );
  });

  test('a moving camera\'s picture: the region it sweeps fills the picture, '
      'whatever the camera shows at the picture\'s frame', () {
    const region = Rect.fromLTRB(40, 20, 680, 380);
    final toPaper = conteCanvasToPaper(pictureOver(region), camera);
    expectLands(
      MatrixUtils.transformPoint(toPaper, region.topLeft),
      frame.topLeft,
      'the region\'s corner',
    );
    expectLands(
      MatrixUtils.transformPoint(toPaper, region.bottomRight),
      frame.bottomRight,
      'and the opposite one',
    );
    expectLands(
      MatrixUtils.transformPoint(toPaper, region.center),
      frame.center,
      'square to it: its middle in the middle',
    );
  });
  test('a picture window moved a page on keeps the canvas its picture shows '
      '— the picture moves, what it shows does not', () {
    const region = Rect.fromLTRB(40, 20, 680, 380);
    final overlay = ActiveStrokeOverlayModel();
    addTearDown(overlay.dispose);
    final window = SheetPictureWindow(
      id: 'p',
      key: const BrushFrameKey(
        projectId: ProjectId('p'),
        trackId: TrackId('t'),
        cutId: CutId('c'),
        layerId: LayerId('l'),
        frameId: FrameId('f'),
      ),
      picture: (
        picture: pictureOver(region),
        canvas: const [Offset.zero, Offset(10, 0), Offset(10, 10)],
        canvasToPaper: Matrix4.identity(),
      ),
      placement: null,
      overlay: overlay,
    );
    const by = Offset(0, 900);
    final moved = window.shiftedBy(by).picture.picture;
    expect(moved.slot, frame.shift(by));
    expect(moved.frame, frame.shift(by));
    expect(moved.canvasRegion, region);
    expect(moved.key, pictureOver(region).key);
  });

  // 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y(마이너스 =
  // 반전)」. A row's placement is no longer a zoom, a turn and a move, so
  // the pen's way to its cel is no viewport.
  group('through the row\'s placement', () {
    final panel = CanvasViewport(zoom: 1.5, panX: 12, panY: -7);
    final toPaper = conteCanvasToPaper(pictureOver(null), camera);

    SheetPictureWindow windowOf(LayerPlacement? placement) {
      final overlay = ActiveStrokeOverlayModel();
      addTearDown(overlay.dispose);
      return SheetPictureWindow(
        id: 'p',
        key: const BrushFrameKey(
          projectId: ProjectId('p'),
          trackId: TrackId('t'),
          cutId: CutId('c'),
          layerId: LayerId('l'),
          frameId: FrameId('f'),
        ),
        picture: (
          picture: pictureOver(null),
          canvas: const [Offset.zero, Offset(160, 0), Offset(160, 90)],
          canvasToPaper: toPaper,
        ),
        placement: placement,
        overlay: overlay,
      );
    }

    test('🚨the view, laid, puts a pixel of the cel where the print lays it '
        '— a row stretched along one axis, flipped along the other and '
        'turned', () {
      final placement = placementOf((
        pose: TransformPose(
          center: CanvasPoint(x: 70, y: 50),
          scaleX: 1.5,
          scaleY: -0.75,
          rotationDegrees: 30,
        ),
        anchorPoint: null,
      ), camera.frameSize);
      final window = windowOf(placement);

      // The print's way: the panel, the camera in its slot, the row.
      final printed = viewportTransformMatrix(panel)
          .multiplied(toPaper)
          .multiplied(placementMatrix(placement));
      // The brush's: its view's own viewport, and how that view is laid.
      final drawn = window
          .viewLaidBy(panel)
          .multiplied(viewportTransformMatrix(window.inkViewport(panel)));
      for (final pixel in const [Offset.zero, Offset(160, 0), Offset(40, 70)]) {
        final lands = MatrixUtils.transformPoint(drawn, pixel);
        final shown = MatrixUtils.transformPoint(printed, pixel);
        expect(lands.dx, closeTo(shown.dx, 1e-6), reason: 'cel pixel $pixel');
        expect(lands.dy, closeTo(shown.dy, 1e-6), reason: 'cel pixel $pixel');
      }
    });

    test('the view sees the cut\'s CANVAS, whatever the row\'s placement: the '
        'viewport its live composite is drawn through', () {
      final stretched = placementOf((
        pose: TransformPose(center: CanvasPoint(x: 80, y: 45), scaleX: 3),
        anchorPoint: null,
      ), camera.frameSize);
      final canvas = pictureCanvasViewport(panel, toPaper);

      expect(windowOf(null).inkViewport(panel), canvas);
      expect(windowOf(stretched).inkViewport(panel), canvas);
    });

    test('a row that lies as it is drawn is laid by the identity — never by '
        'nothing, so its view keeps one parent when a key gives the row a '
        'placement', () {
      expect(windowOf(null).viewLaidBy(panel), Matrix4.identity());
    });

    test('an outline on the paper is read in the cel\'s own pixels through '
        'the same placement, and with none through the camera alone', () {
      final placement = placementOf((
        pose: TransformPose(
          center: CanvasPoint(x: 70, y: 50),
          scaleX: 1.5,
          scaleY: -0.75,
          rotationDegrees: 30,
        ),
        anchorPoint: null,
      ), camera.frameSize);
      const pixels = [Offset(10, 10), Offset(120, 20), Offset(40, 70)];
      List<Offset> onPaper(Matrix4 celToPaper) => [
        for (final pixel in pixels)
          MatrixUtils.transformPoint(celToPaper, pixel),
      ];
      void expectReadsBack(SheetPictureWindow window, Matrix4 celToPaper) {
        final read = window.surfaceShapeOf(onPaper(celToPaper)).points;
        for (var at = 0; at < pixels.length; at += 1) {
          expect(read[at].x, closeTo(pixels[at].dx, 1e-6));
          expect(read[at].y, closeTo(pixels[at].dy, 1e-6));
        }
      }

      expectReadsBack(
        windowOf(placement),
        toPaper.multiplied(placementMatrix(placement)),
      );
      expectReadsBack(windowOf(null), toPaper);
    });

    test('a row its placement has COLLAPSED shows no pixel of its cel '
        'under the pen — where the same row unplaced shows them', () {
      final collapsed = placementOf((
        pose: TransformPose(center: CanvasPoint(x: 80, y: 45), scaleX: 0),
        anchorPoint: null,
      ), camera.frameSize);

      expect(windowOf(null).shows, isNotNull, reason: 'fixture');
      expect(windowOf(collapsed).shows, isNull);
    });

    test('a picture window moved a page on keeps its row\'s placement', () {
      final placement = placementOf((
        pose: TransformPose(center: CanvasPoint(x: 80, y: 45), scaleX: -1),
        anchorPoint: null,
      ), camera.frameSize);

      expect(
        windowOf(placement).shiftedBy(const Offset(0, 900)).placement,
        placement,
      );
    });
  });
}
