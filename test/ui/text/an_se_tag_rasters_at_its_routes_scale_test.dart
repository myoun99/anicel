import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show LayerPlacement;
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart'
    show debugLastSubtreeRaster;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
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
      ResolvedLayerEffect(kind: EffectKind.blur, values: const [2, 0]),
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
      canvasSize: canvas,
      pose: CameraPose(center: CanvasPoint(x: 320, y: 180), zoom: 3),
      cameraFrameSize: frame,
      overlayPass: (canvas, rasterScale) => handed = rasterScale,
    );
    image.dispose();

    expect(handed, 3);
  });

  testWidgets('an export: the scale of the picture it makes', (tester) async {
    await tester.runAsync(() async {
      const cutId = CutId('cut');
      const se = LayerId('se');
      final s = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'Project',
          cameraSize: frame,
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'V',
              cuts: [
                Cut(
                  id: cutId,
                  name: 'Cut',
                  duration: 24,
                  canvasSize: frame,
                  layers: [createCameraLayer(cutId: cutId)],
                ),
              ],
              seLayers: [
                Layer(
                  id: se,
                  name: 'S1',
                  kind: LayerKind.se,
                  frames: [
                    Frame(
                      id: const FrameId('line'),
                      duration: 24,
                      strokes: const [],
                      name: 'the line',
                      seName: 'who',
                    ),
                  ],
                  timeline: const {
                    0: TimelineExposure.drawing(FrameId('line'), length: 24),
                  },
                ),
              ],
            ),
          ],
          createdAt: DateTime.utc(2026),
        ),
      );
      addTearDown(s.dispose);
      s.effectsAndFx.updateLayerEffects(se, [
        LayerEffect(
          id: const EffectId('blur'),
          kind: EffectKind.blur,
          parameters: {'blurriness': EffectParameter(value: 2)},
        ),
      ]);
      final renderer = ExportFrameRenderer(session: s);
      addTearDown(renderer.dispose);

      debugLastSubtreeRaster = null;
      (await renderer.renderComposite(
        ExportFrameTask(cut: s.requireActiveCut, frameIndex: 0),
        ExportSizeMode.camera,
        outputSize: const CanvasSize(width: 960, height: 540),
        withNameTags: true,
      )).dispose();

      expect(debugLastSubtreeRaster, isNotNull, reason: 'one picture');
      expect(debugLastSubtreeRaster!.rasterScale, 3);
    });
  });
}
