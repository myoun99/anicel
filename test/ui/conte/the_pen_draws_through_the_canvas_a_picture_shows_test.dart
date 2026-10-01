import 'dart:ui' show Offset, Rect;

import 'package:flutter/painting.dart' show MatrixUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/conte/conte_picture_ink.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
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
      artworkToCanvas: Matrix4.identity(),
      overlay: overlay,
    );
    const by = Offset(0, 900);
    final moved = window.shiftedBy(by).picture.picture;
    expect(moved.slot, frame.shift(by));
    expect(moved.frame, frame.shift(by));
    expect(moved.canvasRegion, region);
    expect(moved.key, pictureOver(region).key);
  });
}
