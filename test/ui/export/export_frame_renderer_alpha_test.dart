import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

void main() {
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
              id: const CutId('cut'),
              name: 'Cut',
              duration: 1,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                Layer(id: const LayerId('a'), name: 'A', frames: const []),
                createCameraLayer(cutId: const CutId('cut')),
              ],
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    ),
  );

  Future<int> cornerAlpha(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List()[3];
  }

  testWidgets('a transparent background keeps the composite RGBA (EX4)',
      (tester) async {
    await tester.runAsync(() async {
      final manager = session();
      final task = ExportFrameTask(
        cut: manager.requireActiveCut,
        frameIndex: 0,
      );

      final opaque = ExportFrameRenderer(session: manager);
      final white = await opaque.renderComposite(task, ExportSizeMode.camera);
      expect(await cornerAlpha(white), 255);
      white.dispose();

      final transparent = ExportFrameRenderer(
        session: manager,
        background: const ui.Color(0x00000000),
      );
      final clear = await transparent.renderComposite(
        task,
        ExportSizeMode.camera,
      );
      expect(await cornerAlpha(clear), 0);
      clear.dispose();
    });
  });

  testWidgets(
      'preserveAlpha video frames skip the opaque bake; the default bakes',
      (tester) async {
    await tester.runAsync(() async {
      final manager = session();
      // A leading-gap task exercises the ground paint directly.
      final gap = ExportFrameTask(
        cut: manager.requireActiveCut,
        frameIndex: -1,
      );
      final renderer = ExportFrameRenderer(
        session: manager,
        background: const ui.Color(0x00000000),
      );
      final baked = await renderer.renderCompositeForVideo(
        gap,
        ExportSizeMode.camera,
      );
      expect(await cornerAlpha(baked), 255);
      baked.dispose();

      final kept = await renderer.renderCompositeForVideo(
        gap,
        ExportSizeMode.camera,
        preserveAlpha: true,
      );
      expect(await cornerAlpha(kept), 0);
      kept.dispose();
    });
  });
}
