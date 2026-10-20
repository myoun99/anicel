import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_effect.dart'
    show EffectKind, ResolvedLayerEffect;
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show LayerPlacement;
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart'
    show debugLastSubtreeRaster;
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';

/// An SE tag that has to be one picture — its row's effects on it (F-387)
/// — rasters at the scale its route shows a canvas pixel at, as a folder
/// does: a tag rastered at 1 and shown magnified would blur its letters.
void main() {
  const canvas = CanvasSize(width: 640, height: 360);
  const frame = CanvasSize(width: 320, height: 180);
  final blurred = ResolvedSeNameTag(
    layerId: 's1',
    widthBudget: 300,
    shot: const LayerPlacement.identity(),
    effects: [
      ResolvedLayerEffect(kind: EffectKind.blur, values: const [2, 2]),
    ],
    content: const TextCelContent(
      text: 'タモツ',
      style: SeNameTag.defaultStyle,
      position: Offset(320, 180),
    ),
  );

  test('playback: the view\'s scale, and through the camera its zoom', () {
    debugLastSubtreeRaster = null;
    final recorder = ui.PictureRecorder();
    PlaybackFramePainter(
      canvasSize: canvas,
      viewport: CanvasViewport(zoom: 1.5),
      devicePixelRatio: 2,
      cameraPose: CameraPose(center: CanvasPoint(x: 320, y: 180), zoom: 2),
      cameraFrameSize: frame,
      paintPaper: false,
      paintLetterbox: false,
      seNameTags: [blurred],
    ).paint(ui.Canvas(recorder), const Size(960, 540));
    recorder.endRecording().dispose();

    expect(debugLastSubtreeRaster?.rasterScale, 1.5 * 2 * 2);
  });

  test('a render through the camera hands its overlay the projection\'s '
      'scale', () async {
    double? handed;
    final image = await const CameraFrameRenderService().renderThroughCamera(
      pose: CameraPose(center: CanvasPoint(x: 320, y: 180), zoom: 3),
      cameraFrameSize: frame,
      overlayPass: (canvas, rasterScale) => handed = rasterScale,
    );
    image.dispose();

    expect(handed, 3);
  });
}
