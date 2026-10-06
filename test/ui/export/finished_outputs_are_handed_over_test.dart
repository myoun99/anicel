import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/path_names.dart';
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
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/services/persistence/app_export_settings_store.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/move_into_folder.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart'
    show debugOperatingSystemOverride;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/video_export_service.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import 'fake_ffmpeg_process.dart';
import '../../helpers/files_written_under.dart';
import '../../helpers/temp_dir.dart';

/// 「끝나면 고르기」 (drive-folder-windows-Q1, 유저 2026-09-27: 「내보내기가 끝나면
/// 드라이브로 넘긴다 — 파일 창을 거쳐」): the outputs are made first, in the
/// run's room, and handed to the user's pick once the run is done — the one
/// way an export reaches a place no folder window opens, Google Drive above
/// all. Every OS's road is driven from the Windows workstation through the
/// OS seam.
void main() {
  late Directory temp;
  late Directory placed;

  Directory outbox() => Directory(SessionScratch.outboxFolder());

  void clearOutbox() => deleteTempQuietly(outbox());

  setUp(() {
    AppExport.settings.value = AppExportSettings();
    temp = Directory.systemTemp.createTempSync('qa-export-hand-over');
    placed = Directory('${temp.path}/placed')..createSync();
    clearOutbox();
  });

  tearDown(() {
    AppExport.settings.value = AppExportSettings();
    debugOperatingSystemOverride = null;
    AppStorage.debugAllFilesAccessOverride = null;
    FolderPicker.debugFolderPicker = null;
    FolderPicker.debugFileExporter = null;
    FolderPicker.debugFilesExporter = null;
    FolderPicker.debugFileSharer = null;
    FolderPicker.debugBookmarkResolver = null;
    clearOutbox();
    deleteTempQuietly(temp);
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

  Widget dialog({
    VideoExportService video = const VideoExportService(),
    ExportDirectoryPicker? pickFolder,
  }) => MaterialApp(
    home: Scaffold(
      body: ExportDialog(
        session: session(),
        videoExportService: video,
        exportDirectoryPicker: pickFolder,
        formatAvailability: ExportFormatAvailability.permissive(),
      ),
    ),
  );

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pump();
    await tester.pump();
  }

  /// Opens the window and chooses 「끝나면 고르기」 for where the outputs go.
  Future<ExportDialogState> openHandingOver(
    WidgetTester tester, {
    VideoExportService video = const VideoExportService(),
    ExportDirectoryPicker? pickFolder,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(dialog(video: video, pickFolder: pickFolder));
    await tester.pump();
    await tapKey(tester, 'export-hand-over-button');
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

  String? locationLabel(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('export-location-label')))
      .data;

  Future<void> pickPngSequence(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('export-format-still-png')),
    );
    await tester.pump();
  }

  /// What [directory] still holds at its top — a run's own outbox counts,
  /// empty or not.
  List<String> leftIn(Directory directory) => !directory.existsSync()
      ? const []
      : [for (final entry in directory.listSync()) fileNameOfPath(entry.path)];

  List<String> namesOf(List<String> paths) =>
      [for (final path in paths) fileNameOfPath(path)]..sort();

  String? status(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('export-status')))
      .data;

  testWidgets('🎯the outputs are made first and handed to the folder picked '
      'once the run is done — and the room keeps none of them', (
    tester,
  ) async {
    debugOperatingSystemOverride = 'windows';
    List<String>? madeWhenAsked;
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
      madeWhenAsked = namesOf(filesWrittenUnder(outbox()));
      return FolderGrant.granted(path: placed.path);
    };
    final state = await openHandingOver(tester);
    await pickPngSequence(tester);
    expect(madeWhenAsked, isNull, reason: 'choosing it asks for no folder');

    await tester.runAsync(state.export);
    await tester.pump();

    expect(madeWhenAsked, ['frame_0001.png', 'frame_0002.png']);
    expect(filesWrittenUnder(placed), ['frame_0001.png', 'frame_0002.png']);
    expect(leftIn(outbox()), isEmpty);
    expect(status(tester), isNot(AppText.strings.exHandOverDeclined));
  });

  testWidgets('a hand-over the user backs out of lets the outputs go, and '
      'says so', (tester) async {
    debugOperatingSystemOverride = 'windows';
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
        const FolderGrant.cancelled();
    final state = await openHandingOver(tester);
    await pickPngSequence(tester);

    await tester.runAsync(state.export);
    await tester.pump();

    expect(status(tester), AppText.strings.exHandOverDeclined);
    expect(leftIn(outbox()), isEmpty);
    expect(filesWrittenUnder(placed), isEmpty);
  });

  testWidgets('outputs that fail on their way say the failure, and are let '
      'go all the same', (tester) async {
    debugOperatingSystemOverride = 'windows';
    Directory('${placed.path}/frame_0002.png').createSync();
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
        FolderGrant.granted(path: placed.path);
    final state = await openHandingOver(tester);
    await pickPngSequence(tester);

    await tester.runAsync(state.export);
    await tester.pump();

    expect(
      status(tester),
      startsWith(AppText.strings.exFailed('').trim()),
    );
    expect(leftIn(outbox()), isEmpty);
  });

  testWidgets('iOS hands every output to ONE export picker — the mode that '
      'reaches Google Drive — and it moves them', (tester) async {
    debugOperatingSystemOverride = 'ios';
    final handed = <List<String>>[];
    FolderPicker.debugFilesExporter = (sourcePaths) async {
      handed.add(namesOf(sourcePaths));
      for (final source in sourcePaths) {
        moveIntoFolder(source, placed.path);
      }
      return FolderGrant.granted(path: placed.path);
    };
    final state = await openHandingOver(tester);
    await pickPngSequence(tester);

    await tester.runAsync(state.export);
    await tester.pump();

    expect(handed, [
      ['frame_0001.png', 'frame_0002.png'],
    ]);
    expect(filesWrittenUnder(placed), ['frame_0001.png', 'frame_0002.png']);
    expect(leftIn(outbox()), isEmpty);
  });

  testWidgets('Android places ONE output through the save window', (
    tester,
  ) async {
    debugOperatingSystemOverride = 'android';
    AppStorage.debugAllFilesAccessOverride = true;
    final saved = <String>[];
    var shared = 0;
    FolderPicker.debugFileExporter = ({
      required String sourcePath,
      String? suggestedName,
    }) async {
      saved.add(fileNameOfPath(sourcePath));
      moveIntoFolder(sourcePath, placed.path);
      return FolderGrant.granted(path: placed.path, kind: GrantKind.file);
    };
    FolderPicker.debugFileSharer = (paths) async {
      shared += 1;
      return true;
    };
    final state = await openHandingOver(tester);
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-image')));
    await tester.pump();

    await tester.runAsync(state.export);
    await tester.pump();

    expect(saved, hasLength(1));
    expect(shared, 0);
    expect(filesWrittenUnder(placed), saved);
    expect(leftIn(outbox()), isEmpty);
  });

  testWidgets('Android offers SEVERAL through the share sheet, and they stay '
      'for the app that took them to read', (tester) async {
    debugOperatingSystemOverride = 'android';
    List<String>? offered;
    FolderPicker.debugFileSharer = (paths) async {
      offered = paths;
      return true;
    };
    final state = await openHandingOver(tester);
    await pickPngSequence(tester);

    await tester.runAsync(state.export);
    await tester.pump();

    expect(namesOf(offered!), ['frame_0001.png', 'frame_0002.png']);
    expect(offered!.every((path) => File(path).existsSync()), isTrue);
    expect(status(tester), isNot(AppText.strings.exHandOverDeclined));
  });

  testWidgets('a queue hands every job\'s outputs over in ONE window once the '
      'last job is done', (tester) async {
    debugOperatingSystemOverride = 'windows';
    var asked = 0;
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
      asked += 1;
      return FolderGrant.granted(path: placed.path);
    };
    final state = await openHandingOver(tester);
    await pickPngSequence(tester);
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

    await tester.runAsync(state.runQueue);
    await tester.pump();

    expect(asked, 1);
    expect(filesWrittenUnder(placed), [
      'frame_0001.png',
      'frame_0002.png',
      'shot_0001.png',
      'shot_0002.png',
    ]);
    expect(leftIn(outbox()), isEmpty);
  });

  testWidgets('a run that is stopped hands nothing over and keeps nothing', (
    tester,
  ) async {
    debugOperatingSystemOverride = 'windows';
    var asked = 0;
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
      asked += 1;
      return FolderGrant.granted(path: placed.path);
    };
    late ExportDialogState state;
    final fake = FakeFfmpegProcess(
      onFrame: (framesSoFar) {
        if (framesSoFar >= 1) {
          state.cancelExport();
        }
      },
    );
    state = await openHandingOver(
      tester,
      video: VideoExportService(
        processStarter: (executable, arguments) async => fake,
      ),
    );

    await tester.runAsync(state.export);
    await tester.pump();

    expect(asked, 0);
    expect(leftIn(outbox()), isEmpty);
  });

  testWidgets('the choice is remembered in place of the folder — the next '
      'window opens on it', (tester) async {
    await openHandingOver(tester, pickFolder: () async => temp.path);
    await tapKey(tester, 'export-browse-button');
    expect(
      AppExport.settings.value.lastDestination,
      ExportIntoFolder(GrantedDirectory(path: temp.path)),
      reason: 'premise: a folder was the destination',
    );

    await tapKey(tester, 'export-hand-over-button');
    expect(AppExport.settings.value.lastDestination, const ExportHandOver());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(dialog());
    await tester.pump();

    expect(locationLabel(tester), AppText.strings.exHandOverWhenDone);
  });

  testWidgets('a folder chosen after a hand-over takes the next run itself, '
      'with no window', (tester) async {
    debugOperatingSystemOverride = 'windows';
    var asked = 0;
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
      asked += 1;
      return FolderGrant.granted(path: placed.path);
    };
    final direct = Directory('${temp.path}/direct')..createSync();
    final state = await openHandingOver(
      tester,
      pickFolder: () async => direct.path,
    );
    await pickPngSequence(tester);
    await tester.runAsync(state.export);
    await tester.pump();
    expect(asked, 1, reason: 'premise: the first run was handed over');

    await tapKey(tester, 'export-browse-button');
    expect(locationLabel(tester), direct.path);
    await tester.runAsync(state.export);
    await tester.pump();

    expect(asked, 1);
    expect(filesWrittenUnder(direct), ['frame_0001.png', 'frame_0002.png']);
  });

  testWidgets('a run that fails hands nothing over and keeps nothing', (
    tester,
  ) async {
    debugOperatingSystemOverride = 'windows';
    var asked = 0;
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
      asked += 1;
      return FolderGrant.granted(path: placed.path);
    };
    final state = await openHandingOver(
      tester,
      video: VideoExportService(
        processStarter: (executable, arguments) async =>
            FakeFfmpegProcess(exitCodeValue: 1),
      ),
    );

    await tester.runAsync(state.export);
    await tester.pump();

    expect(status(tester), startsWith(AppText.strings.exFailed('').trim()));
    expect(asked, 0);
    expect(leftIn(outbox()), isEmpty);
  });

  testWidgets('a queue whose hand-over is backed out of says so, and the '
      'window stays on 「끝나면 고르기」', (tester) async {
    debugOperatingSystemOverride = 'windows';
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
        const FolderGrant.cancelled();
    final state = await openHandingOver(tester);
    await pickPngSequence(tester);
    await tapKey(tester, 'export-queue-add-button');

    await tester.runAsync(state.runQueue);
    await tester.pump();

    expect(status(tester), AppText.strings.exHandOverDeclined);
    expect(locationLabel(tester), AppText.strings.exHandOverWhenDone);
    expect(leftIn(outbox()), isEmpty);
  });

  testWidgets('a queued job keeps its own destination, and the window goes '
      'back to the one it stood on before the run', (tester) async {
    debugOperatingSystemOverride = 'windows';
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
        FolderGrant.granted(path: placed.path);
    final direct = Directory('${temp.path}/direct')..createSync();
    final state = await openHandingOver(
      tester,
      pickFolder: () async => direct.path,
    );
    await pickPngSequence(tester);
    await tapKey(tester, 'export-queue-add-button');
    await tapKey(tester, 'export-browse-button');

    await tester.runAsync(state.runQueue);
    await tester.pump();

    expect(filesWrittenUnder(placed), ['frame_0001.png', 'frame_0002.png']);
    expect(filesWrittenUnder(direct), isEmpty);
    expect(locationLabel(tester), direct.path);
  });

  testWidgets('a folder\'s token that resolves after 「끝나면 고르기」 was '
      'chosen leaves the choice alone', (tester) async {
    final store = AppExportSettingsStore(
      filePath: '${temp.path.replaceAll('\\', '/')}/export_settings.json',
    );
    await tester.runAsync(
      () => store.save(
        AppExportSettings(
          lastDestination: const ExportIntoFolder(
            GrantedDirectory(path: '/old/deliver', bookmark: 'TOK=='),
          ),
        ),
      ),
    );
    final resolving = Completer<FolderGrant>();
    FolderPicker.debugBookmarkResolver = (base64, kind) => resolving.future;
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session(),
            settingsStore: store,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(locationLabel(tester), '/old/deliver', reason: 'premise');

    await tapKey(tester, 'export-hand-over-button');
    resolving.complete(
      const FolderGrant.granted(path: '/mounted/deliver', bookmark: 'NEW=='),
    );
    await tester.pump();
    await tester.pump();

    expect(locationLabel(tester), AppText.strings.exHandOverWhenDone);
    expect(AppExport.settings.value.lastDestination, const ExportHandOver());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the destination a saved settings file holds opens as '
      '「끝나면 고르기」 too', (tester) async {
    final store = AppExportSettingsStore(
      filePath: '${temp.path.replaceAll('\\', '/')}/export_settings.json',
    );
    await tester.runAsync(
      () => store.save(
        AppExportSettings(lastDestination: const ExportHandOver()),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session(),
            settingsStore: store,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(locationLabel(tester), AppText.strings.exHandOverWhenDone);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
