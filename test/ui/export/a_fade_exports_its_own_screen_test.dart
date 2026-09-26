import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

/// 🗣️F-192 (유저 2026-09-27): 「컷의 페이드인은 애초에 쌩 검은화면에서
/// 바뀐단거였음. 화이트인은 쌩 흰화면에서 바뀌는거고 … 백그라운드색을
/// 바꾸는거말고 구조적으로」.
///
/// The video frames a fade exports are its own screen — black for F.O,
/// white for W.O — on both routes a frame can take: the canvas-size bake
/// (↩️where a lone fade was simply missing) and the camera frame's stack.
/// The backdrop is RED so that a fade showing what lies behind it — the old
/// law — could not pass for either.
void main() {
  const green = 0xFF00FF00;
  const cutId = CutId('c');
  const trackId = TrackId('t');

  /// One 10-frame cut on green paper, and a fade [term] over its last five.
  EditorSessionManager session(String term) {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('fade'),
        name: 'Fade',
        createdAt: DateTime.utc(2026),
        cameraSize: const CanvasSize(width: 8, height: 8),
        backdropArgb: 0xFFFF0000,
        tracks: [
          Track(
            id: trackId,
            name: 'V',
            cuts: [
              Cut(
                id: cutId,
                name: 'C',
                duration: 10,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  Layer(id: const LayerId('a'), name: 'A', frames: const []),
                  createCameraLayer(cutId: cutId),
                ],
              ),
            ],
            transitionLayer: createTrackTransitionLayer(trackId).copyWith(
              instructions: SplayTreeMap.of({
                5: InstructionEvent(instructionId: term, length: 5),
              }),
            ),
          ),
        ],
      ),
    );
    manager.projectSettings.setProjectBackground(
      const ProjectBackground.color(green),
    );
    return manager;
  }

  Future<(int, int, int)> centreOf(
    EditorSessionManager manager,
    int frame,
    ExportSizeMode mode,
  ) async {
    final image = await ExportFrameRenderer(session: manager)
        .renderCompositeForVideo(
          ExportFrameTask(cut: manager.requireActiveCut, frameIndex: frame),
          mode,
        );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
    image.dispose();
    return (
      bytes!.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }

  for (final mode in [ExportSizeMode.canvas, ExportSizeMode.camera]) {
    group('${mode.name} frames', () {
      testWidgets('an F.O ends on solid BLACK', (tester) async {
        await tester.runAsync(() async {
          final manager = session('fo');
          addTearDown(manager.dispose);
          expect(await centreOf(manager, 4, mode), (0, 255, 0),
              reason: 'CONTROL: the paper, before the fade');
          expect(await centreOf(manager, 9, mode), (0, 0, 0));
        });
      });

      testWidgets('an F.O halfway is the paper half under black', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final manager = session('fo');
          addTearDown(manager.dispose);
          final (r, g, b) = await centreOf(manager, 7, mode);
          expect(r, lessThan(8), reason: 'no red — nothing behind shows');
          expect(g, closeTo(128, 3));
          expect(b, lessThan(8));
        });
      });

      testWidgets('a W.O ends on solid WHITE', (tester) async {
        await tester.runAsync(() async {
          final manager = session('wo');
          addTearDown(manager.dispose);
          expect(await centreOf(manager, 9, mode), (255, 255, 255));
        });
      });
    });
  }
}
