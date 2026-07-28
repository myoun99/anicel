import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
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
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';

void main() {
  late Directory temp;

  setUp(() {
    AppExport.settings.value = AppExportSettings();
    temp = Directory.systemTemp.createTempSync('qa-export-queue');
  });

  tearDown(() {
    AppExport.settings.value = AppExportSettings();
    try {
      temp.deleteSync(recursive: true);
    } on Object {
      // Windows can hold a handle a beat.
    }
  });

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

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
              duration: 2,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                Layer(
                  id: const LayerId('layer'),
                  name: 'A',
                  frames: [frame('f1'), frame('f2')],
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

  Future<ExportDialogState> pumpDialog(
    WidgetTester tester,
    EditorSessionManager manager, {
    String? location,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: manager,
            exportDirectoryPicker: () async => location ?? temp.path,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    final state = tester.state<ExportDialogState>(find.byType(ExportDialog));
    await tester.tap(
      find.byKey(const ValueKey<String>('export-browse-button')),
    );
    await tester.pump();
    await tester.pump();
    return state;
  }

  Future<void> pickPng(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('export-format-still-png')),
    );
    await tester.pump();
  }

  List<String> filesIn(Directory directory) => directory
      .listSync(recursive: true)
      .whereType<File>()
      .map(
        (file) => file.path
            .substring(directory.path.length + 1)
            .replaceAll('\\', '/'),
      )
      .toList()
    ..sort();

  testWidgets('Add to Queue freezes specs; Render All runs them in order '
      'and restores the setup', (tester) async {
    final state = await pumpDialog(tester, session());
    await pickPng(tester);

    // Job 1: base name 'frame'. Then edit the base and queue job 2.
    await tester.tap(
      find.byKey(const ValueKey<String>('export-queue-add-button')),
    );
    await tester.pump();

    await tester.ensureVisible(find.textContaining('Naming'));
    await tester.tap(find.textContaining('Naming'));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('export-naming-base-field')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('export-naming-base-field')),
      'shot',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-queue-add-button')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('export-queue-job-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('export-queue-job-2')),
      findsOneWidget,
    );

    await tester.runAsync(state.runQueue);
    await tester.pump();

    expect(filesIn(temp), [
      'frame_0001.png',
      'frame_0002.png',
      'shot_0001.png',
      'shot_0002.png',
    ]);
    expect(find.textContaining('Done'), findsNWidgets(2));
    // The user's own setup (base 'shot') survives the batch.
    final baseField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('export-naming-base-field')),
    );
    expect(baseField.controller?.text, 'shot');
    expect(
      find.textContaining('Queue: 2 jobs done'),
      findsOneWidget,
    );
  });

  testWidgets('a failing job marks itself and the rest still run',
      (tester) async {
    final state = await pumpDialog(tester, session());
    await pickPng(tester);

    // Job 1 aims INSIDE A FILE — the write must fail.
    final blocker = File('${temp.path}/blocker')..createSync();
    final broken = '${blocker.path}/nested';
    state.debugSetLocationForTests(broken);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-queue-add-button')),
    );
    await tester.pump();

    state.debugSetLocationForTests(temp.path);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-queue-add-button')),
    );
    await tester.pump();

    await tester.runAsync(state.runQueue);
    await tester.pump();

    expect(find.textContaining('Failed'), findsOneWidget);
    expect(find.textContaining('Done'), findsOneWidget);
    expect(
      find.textContaining('1 job done, 1 failed'),
      findsOneWidget,
    );
    expect(filesIn(temp), [
      'blocker',
      'frame_0001.png',
      'frame_0002.png',
    ]);
  });

  testWidgets('clicking a queued job restores its setup and removes it',
      (tester) async {
    final state = await pumpDialog(tester, session());
    await pickPng(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('export-queue-add-button')),
    );
    await tester.pump();

    // Drift back to video, then restore the queued PNG job.
    await tester.tap(
      find.byKey(const ValueKey<String>('export-format-container-mp4')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-queue-job-1')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('export-queue-job-1')),
      findsNothing,
    );
    final output = tester.widget<Text>(
      find.byKey(const ValueKey<String>('export-output-line')),
    );
    expect(output.data, contains('frame_0001.png'));
    expect(state.debugImageFrame, isNotNull);
  });
}
