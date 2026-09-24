import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/video_export_service.dart';

import 'fake_ffmpeg_process.dart';
import '../../helpers/temp_dir.dart';

/// 🚨A STOPPED EXPORT SAYS HOW MUCH IT KEPT, IN THE RIGHT PLURAL.
///
/// Six export routines wrote that sentence out by hand before the audit
/// folded them into one; the mutation that made the folded sentence stop
/// pluralising SURVIVED, because every test in the suite ran an export to
/// completion (2026-09-04). One frame reads the same either way, so this
/// stops the encoder after TWO.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('anicel-export-cancel');
  });

  tearDown(() => deleteTempQuietly(temp));

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  /// Four frames — enough that stopping after two leaves work undone.
  EditorSessionManager session() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: const CanvasSize(width: 32, height: 18),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: const CutId('cut'),
              name: 'Cut',
              duration: 4,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                Layer(
                  id: const LayerId('layer'),
                  name: 'A',
                  frames: [frame('f1'), frame('f2'), frame('f3'), frame('f4')],
                ),
                createCameraLayer(cutId: const CutId('cut')),
              ],
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    ),
  );

  testWidgets('an export stopped after two frames says frames, not frame', (
    tester,
  ) async {
    late ExportDialogState state;
    final fake = FakeFfmpegProcess(
      onFrame: (framesSoFar) {
        if (framesSoFar >= 2) {
          state.cancelExport();
        }
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session(),
            exportDirectoryPicker: () async => temp.path,
            videoExportService: VideoExportService(
              processStarter: (executable, arguments) async => fake,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    state = tester.state<ExportDialogState>(find.byType(ExportDialog));
    await tester.tap(
      find.byKey(const ValueKey<String>('export-browse-button')),
    );
    await tester.pump();
    await tester.pump();
    await tester.runAsync(state.export);
    await tester.pump();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('export-status')))
          .data,
      'Export cancelled after 2 frames (partial video kept).',
      reason:
          'the shared sentence must pluralise what it kept — an export '
          'that stopped after two frames does not say "2 frame"',
    );
  });
}
