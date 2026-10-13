import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';

/// A track above the stage thins its names with its picture
/// ([PlaybackFramePainter.imageOpacity]) — through the camera as well,
/// wherever the camera looks on the canvas.
void main() {
  testWidgets('🎯through a camera looking away from the canvas\'s corner, '
      'names thinned to a half are laid at a half — not cut away', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const canvas = CanvasSize(width: 640, height: 360);
      const frame = CanvasSize(width: 320, height: 180);
      // Its frame on the canvas is nowhere near the canvas's own corner.
      final pose = CameraPose(center: CanvasPoint(x: 480, y: 270));
      const cutId = CutId('cut');
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
                  canvasSize: canvas,
                  camera: CutCamera(keyframes: {0: pose}),
                  layers: [createCameraLayer(cutId: cutId)],
                ),
              ],
              seLayers: [
                Layer(
                  id: const LayerId('se'),
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
      final tags = s.seEntries.seNameTagsForCutFrame(s.requireActiveCut, 0);
      expect(tags, hasLength(1), reason: 'LIVENESS: somebody is named');

      /// The most opaque pixel of the names laid at [opacity].
      Future<int> densest(double opacity) async {
        final recorder = ui.PictureRecorder();
        PlaybackFramePainter(
          canvasSize: canvas,
          cameraPose: pose,
          cameraFrameSize: frame,
          paintPaper: false,
          paintLetterbox: false,
          seNameTags: tags,
          imageOpacity: opacity,
        ).paint(ui.Canvas(recorder), const Size(320, 180));
        final image = await recorder.endRecording().toImage(320, 180);
        final data = await image.toByteData();
        image.dispose();
        final bytes = data!.buffer.asUint8List();
        var most = 0;
        for (var i = 3; i < bytes.length; i += 4) {
          if (bytes[i] > most) {
            most = bytes[i];
          }
        }
        return most;
      }

      expect(await densest(1), 255, reason: 'LIVENESS: the names, whole');
      expect(await densest(0.5), inInclusiveRange(120, 135));
    });
  });
}
