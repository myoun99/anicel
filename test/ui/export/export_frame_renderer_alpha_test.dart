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

  testWidgets('a selected-track gap COVERED by another track bakes that '
      'track\'s stage (R3a): the stack replaces the background-only frame, '
      'so an alpha master carries the covering track\'s opaque paper',
      (tester) async {
    await tester.runAsync(() async {
      EditorSessionManager twoTracks({required int coverDuration}) =>
          EditorSessionManager(
            initialProject: Project(
              id: const ProjectId('project-stack'),
              name: 'Project',
              cameraSize: const CanvasSize(width: 16, height: 12),
              tracks: [
                Track(
                  id: const TrackId('track-a'),
                  name: 'A',
                  cuts: [
                    Cut(
                      id: const CutId('cut-a'),
                      name: 'A1',
                      duration: 1,
                      // The cut sits at global 4; its leading gap holds
                      // global 0..3.
                      leadingGapFrames: 4,
                      canvasSize: const CanvasSize(width: 8, height: 8),
                      layers: [
                        Layer(
                          id: const LayerId('a'),
                          name: 'A',
                          frames: const [],
                        ),
                        createCameraLayer(cutId: const CutId('cut-a')),
                      ],
                    ),
                  ],
                ),
                Track(
                  id: const TrackId('track-b'),
                  name: 'B',
                  cuts: [
                    Cut(
                      id: const CutId('cut-b'),
                      name: 'B1',
                      duration: coverDuration,
                      canvasSize: const CanvasSize(width: 16, height: 12),
                      layers: [
                        Layer(
                          id: const LayerId('b'),
                          name: 'B',
                          frames: const [],
                        ),
                        createCameraLayer(cutId: const CutId('cut-b')),
                      ],
                    ),
                  ],
                ),
              ],
              createdAt: DateTime.utc(2026),
            ),
          );

      // Track A's gap task one frame before its cut = global 3. Track B
      // covers it (duration 8): the stack bakes B's paper — opaque.
      final covered = twoTracks(coverDuration: 8);
      final coveredRenderer = ExportFrameRenderer(
        session: covered,
        background: const ui.Color(0x00000000),
      );
      final coveredFrame = await coveredRenderer.renderCompositeForVideo(
        ExportFrameTask(
          cut: covered.repository
              .requireProject()
              .tracks
              .first
              .cuts
              .single,
          frameIndex: -1,
        ),
        ExportSizeMode.camera,
        preserveAlpha: true,
      );
      expect(
        await cornerAlpha(coveredFrame),
        255,
        reason: 'track B\'s stage covers global 3',
      );
      coveredFrame.dispose();
      covered.dispose();

      // Shrink B to end before global 3: nothing covers, the alpha master
      // keeps the frame transparent — the old gap contract, still true
      // where the stage is genuinely empty.
      final uncovered = twoTracks(coverDuration: 2);
      final uncoveredRenderer = ExportFrameRenderer(
        session: uncovered,
        background: const ui.Color(0x00000000),
      );
      final uncoveredFrame = await uncoveredRenderer.renderCompositeForVideo(
        ExportFrameTask(
          cut: uncovered.repository
              .requireProject()
              .tracks
              .first
              .cuts
              .single,
          frameIndex: -1,
        ),
        ExportSizeMode.camera,
        preserveAlpha: true,
      );
      expect(
        await cornerAlpha(uncoveredFrame),
        0,
        reason: 'no track covers global 3 any more',
      );
      uncoveredFrame.dispose();
      uncovered.dispose();
    });
  });
}
