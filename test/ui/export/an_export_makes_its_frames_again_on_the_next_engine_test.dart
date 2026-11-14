import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/frame_shots.dart' show pictureOfLaid;

import '../../helpers/the_apps_engine_let_go.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」. The frames an export holds on the
/// engine are kept for the engine they were made on (`KeptOnTheAppsEngine`,
/// 관제 2026-11-12 08:43): a frame asked for again once the app has let
/// that engine go is made again on the next, not handed from the one let
/// go — whose every job is refused.
///
/// On the app's own engine, which the test loses: alone in its file.
void main() {
  const cutId = CutId('cut');

  EditorSessionManager session() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: const CanvasSize(width: 16, height: 12),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: cutId,
              name: 'Cut',
              duration: 3,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                Layer(id: const LayerId('a'), name: 'A', frames: const []),
                createCameraLayer(cutId: cutId),
              ],
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    ),
  );

  Future<Uint8List> bytesOf(ui.Image image) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  testWidgets('🚨a frame held as the app lets its engine go is made again '
      'on the next — the same picture — not handed from the one let go', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final manager = session();
      addTearDown(manager.dispose);
      final renderer = ExportFrameRenderer(session: manager);
      addTearDown(renderer.dispose);
      final cut = manager.requireActiveCut;
      final run = renderer.videoRun([
        for (var index = 0; index < 3; index += 1)
          ExportFrameTask(cut: cut, frameIndex: index),
      ], ExportSizeMode.camera);

      final first = await run.frame(0);
      final before = await bytesOf(pictureOfLaid(appGpuExport, first));
      expect(
        await run.frame(1),
        same(first),
        reason: 'LIVENESS: held while its engine is the app\'s',
      );

      theAppsEngineLostAndLetGo();

      final again = await run.frame(2);
      expect(again, isNot(same(first)), reason: 'made on the next engine');
      expect(await bytesOf(pictureOfLaid(appGpuExport, again)), before);
    });
  });
}
