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
import '../../helpers/export_preview_probe.dart';
import '../../helpers/files_written_under.dart';
import '../../helpers/temp_dir.dart';

/// WHERE AN EXPORT GOES IS ASKED WHEN IT IS PRESSED (F-221, 유저 2026-10-06:
/// 「어차피 내보내기누르면 OS창 뜨게하는 최종통일안으로 통일할거니
/// 문제없어보임」) — and the OS says in what order: a platform that can be
/// asked before the files exist is asked first, and one that cannot makes
/// them in the run's room and hands them over once the run is done
/// (drive-folder-windows-Q1, 유저 2026-09-27: 「내보내기가 끝나면 드라이브로
/// 넘긴다 — 파일 창을 거쳐」 — the one way an export reaches Google Drive on
/// iOS).
///
/// The window's side of it: when it asks, what it does with the answer, and
/// the line that says which order this export takes. Every OS's road is
/// driven from the Windows workstation through the OS seam.
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

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pump();
    await tester.pump();
  }

  /// Opens the window as [operatingSystem] shows it.
  Future<ExportDialogState> open(
    WidgetTester tester,
    String operatingSystem, {
    VideoExportService video = const VideoExportService(),
  }) async {
    debugOperatingSystemOverride = operatingSystem;
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session(),
            videoExportService: video,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

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

  String orderLine(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('export-order-line')))
      .data!;

  bool exportLive(WidgetTester tester) =>
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('export-run-button')),
          )
          .onPressed !=
      null;

  /// The iOS export picker: moves whatever it is handed into [placed],
  /// writing down what it was handed.
  List<List<String>> iosPickerPlaces() {
    final handed = <List<String>>[];
    FolderPicker.debugFilesExporter = (sourcePaths) async {
      handed.add(namesOf(sourcePaths));
      for (final source in sourcePaths) {
        moveIntoFolder(source, placed.path);
      }
      return FolderGrant.granted(path: placed.path);
    };
    return handed;
  }

  group('asked FIRST, where the platform can be asked before the files '
      'exist', () {
    testWidgets('🚨a desktop: Export opens the folder window before a file is '
        'made, and the run writes straight into the folder it answers', (
      tester,
    ) async {
      List<String>? madeWhenAsked;
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
        madeWhenAsked = [
          ...filesWrittenUnder(placed),
          ...leftIn(outbox()),
        ];
        return FolderGrant.granted(path: placed.path);
      };
      final state = await open(tester, 'windows');
      await pickPngSequence(tester);
      expect(exportLive(tester), isTrue, reason: 'no place is chosen ahead');
      expect(madeWhenAsked, isNull, reason: 'nothing is asked until Export');

      await tester.runAsync(state.export);
      await tester.pump();

      expect(madeWhenAsked, isEmpty, reason: 'asked before anything was made');
      expect(filesWrittenUnder(placed), ['frame_0001.png', 'frame_0002.png']);
      expect(leftIn(outbox()), isEmpty, reason: 'it wrote straight there');
    });

    testWidgets('backing out of the folder window runs nothing — and says '
        'nothing', (tester) async {
      var asked = 0;
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
        asked += 1;
        return const FolderGrant.cancelled();
      };
      final state = await open(tester, 'windows');
      await pickPngSequence(tester);

      await tester.runAsync(state.export);
      await tester.pump();

      expect(asked, 1);
      expect(filesWrittenUnder(placed), isEmpty);
      expect(leftIn(outbox()), isEmpty);
      expect(status(tester), '');
      expect(exportLive(tester), isTrue);
    });

    testWidgets('the folder window opens where the last export went', (
      tester,
    ) async {
      final asked = <String?>[];
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
        asked.add(initialDirectory);
        return FolderGrant.granted(path: placed.path);
      };
      final state = await open(tester, 'windows');
      await pickPngSequence(tester);

      await tester.runAsync(state.export);
      await tester.pump();
      await tester.runAsync(state.export);
      await tester.pump();

      expect(asked, [null, placed.path]);
    });

    testWidgets('Android asks a FOLDER first for several files — and nothing '
        'is offered through the share sheet', (tester) async {
      AppStorage.debugAllFilesAccessOverride = true;
      var shared = 0;
      List<String>? madeWhenAsked;
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
        madeWhenAsked = leftIn(outbox());
        return FolderGrant.granted(path: placed.path);
      };
      FolderPicker.debugFileSharer = (paths) async {
        shared += 1;
        return true;
      };
      final state = await open(tester, 'android');
      await pickPngSequence(tester);

      await tester.runAsync(state.export);
      await tester.pump();

      expect(madeWhenAsked, isEmpty);
      expect(filesWrittenUnder(placed), ['frame_0001.png', 'frame_0002.png']);
      expect(shared, 0);
    });

    testWidgets('a queue asks each job its folder when it is QUEUED, and '
        'every job writes into its own', (tester) async {
      final second = Directory('${temp.path}/second')..createSync();
      final folders = [placed.path, second.path];
      var asked = 0;
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
          FolderGrant.granted(path: folders[asked++]);
      final state = await open(tester, 'windows');
      await pickPngSequence(tester);

      await tapKey(tester, 'export-queue-add-button');
      expect(asked, 1, reason: 'asked as the job is queued');
      await tapKey(tester, 'export-queue-add-button');
      expect(asked, 2);

      await tester.runAsync(state.runQueue);
      await tester.pump();

      expect(asked, 2, reason: 'the run asks nothing more');
      expect(filesWrittenUnder(placed), ['frame_0001.png', 'frame_0002.png']);
      expect(filesWrittenUnder(second), ['frame_0001.png', 'frame_0002.png']);
    });

    testWidgets('a job whose folder window is backed out of is not queued', (
      tester,
    ) async {
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
          const FolderGrant.cancelled();
      await open(tester, 'windows');
      await pickPngSequence(tester);

      await tapKey(tester, 'export-queue-add-button');

      expect(
        find.byKey(const ValueKey<String>('export-queue-job-1')),
        findsNothing,
      );
    });
  });

  group('asked AFTERWARDS, where a place can only be asked of what is '
      'made', () {
    testWidgets('🎯iOS: the outputs are made first and handed to ONE export '
        'picker — the mode that reaches Google Drive — and the room keeps '
        'none of them', (tester) async {
      final handed = iosPickerPlaces();
      final state = await open(tester, 'ios');
      await pickPngSequence(tester);

      await tester.runAsync(state.export);
      await tester.pump();

      expect(handed, [
        ['frame_0001.png', 'frame_0002.png'],
      ]);
      expect(filesWrittenUnder(placed), ['frame_0001.png', 'frame_0002.png']);
      expect(leftIn(outbox()), isEmpty);
      expect(status(tester), isNot(AppText.strings.exHandOverDeclined));
    });

    testWidgets('a hand-over the user backs out of lets the outputs go, and '
        'says so', (tester) async {
      FolderPicker.debugFilesExporter = (sourcePaths) async =>
          const FolderGrant.cancelled();
      final state = await open(tester, 'ios');
      await pickPngSequence(tester);

      await tester.runAsync(state.export);
      await tester.pump();

      expect(status(tester), AppText.strings.exHandOverDeclined);
      expect(leftIn(outbox()), isEmpty);
      expect(filesWrittenUnder(placed), isEmpty);
    });

    testWidgets('outputs that fail on their way say the failure, and are let '
        'go all the same', (tester) async {
      FolderPicker.debugFilesExporter = (sourcePaths) async =>
          throw const FileSystemException('the picker lost them');
      final state = await open(tester, 'ios');
      await pickPngSequence(tester);

      await tester.runAsync(state.export);
      await tester.pump();

      expect(status(tester), startsWith(AppText.strings.exFailed('').trim()));
      expect(leftIn(outbox()), isEmpty);
    });

    testWidgets('Android places ONE output through the save window, once it '
        'is made', (tester) async {
      AppStorage.debugAllFilesAccessOverride = true;
      final saved = <String>[];
      var askedFolder = 0;
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
        askedFolder += 1;
        return FolderGrant.granted(path: placed.path);
      };
      FolderPicker.debugFileExporter = ({
        required String sourcePath,
        String? suggestedName,
      }) async {
        saved.add(fileNameOfPath(sourcePath));
        moveIntoFolder(sourcePath, placed.path);
        return FolderGrant.granted(path: placed.path, kind: GrantKind.file);
      };
      final state = await open(tester, 'android');
      await tester.tap(find.byKey(const ValueKey<String>('export-tab-image')));
      await tester.pump();

      await tester.runAsync(state.export);
      await tester.pump();

      expect(askedFolder, 0, reason: 'one file is not asked a folder');
      expect(saved, ['Project.png']);
      expect(filesWrittenUnder(placed), saved);
      expect(leftIn(outbox()), isEmpty);
    });

    testWidgets('a queue hands every job\'s outputs over in ONE window once '
        'the last job is done', (tester) async {
      final handed = iosPickerPlaces();
      final state = await open(tester, 'ios');
      await pickPngSequence(tester);
      await tapKey(tester, 'export-queue-add-button');
      expect(handed, isEmpty, reason: 'queued without being asked');
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
      await tapKey(tester, 'export-queue-add-button');

      await tester.runAsync(state.runQueue);
      await tester.pump();

      expect(handed, [
        ['frame_0001.png', 'frame_0002.png', 'shot_0001.png', 'shot_0002.png'],
      ]);
      expect(leftIn(outbox()), isEmpty);
    });

    testWidgets('a queue whose hand-over is backed out of says so', (
      tester,
    ) async {
      FolderPicker.debugFilesExporter = (sourcePaths) async =>
          const FolderGrant.cancelled();
      final state = await open(tester, 'ios');
      await pickPngSequence(tester);
      await tapKey(tester, 'export-queue-add-button');

      await tester.runAsync(state.runQueue);
      await tester.pump();

      expect(status(tester), AppText.strings.exHandOverDeclined);
      expect(leftIn(outbox()), isEmpty);
    });

    testWidgets('a run that is stopped hands nothing over and keeps nothing', (
      tester,
    ) async {
      final handed = iosPickerPlaces();
      late ExportDialogState state;
      final fake = FakeFfmpegProcess(
        onFrame: (framesSoFar) {
          if (framesSoFar >= 1) {
            state.cancelExport();
          }
        },
      );
      state = await open(
        tester,
        'ios',
        video: VideoExportService(
          processStarter: (executable, arguments) async => fake,
        ),
      );

      await tester.runAsync(state.export);
      await tester.pump();

      expect(handed, isEmpty);
      expect(leftIn(outbox()), isEmpty);
    });

    testWidgets('a run that fails hands nothing over and keeps nothing', (
      tester,
    ) async {
      final handed = iosPickerPlaces();
      final state = await open(
        tester,
        'ios',
        video: VideoExportService(
          processStarter: (executable, arguments) async =>
              FakeFfmpegProcess(exitCodeValue: 1),
        ),
      );

      await tester.runAsync(state.export);
      await tester.pump();

      expect(status(tester), startsWith(AppText.strings.exFailed('').trim()));
      expect(handed, isEmpty);
      expect(leftIn(outbox()), isEmpty);
    });
  });

  group('the order line beside Export says which this export takes', () {
    testWidgets('a desktop asks first; iOS asks afterwards', (tester) async {
      await open(tester, 'windows');
      expect(orderLine(tester), AppText.strings.exOrderAsksFirst);
      await tester.pumpWidget(const SizedBox.shrink());

      await open(tester, 'ios');
      expect(orderLine(tester), AppText.strings.exOrderAsksAfter);
    });

    testWidgets('Android: a folder is asked first, one file afterwards — the '
        'line follows what the tab writes', (tester) async {
      await open(tester, 'android');
      expect(
        orderLine(tester),
        AppText.strings.exOrderAsksAfter,
        reason: 'the tab opens on a video — one file',
      );

      await pickPngSequence(tester);
      expect(orderLine(tester), AppText.strings.exOrderAsksFirst);

      await tester.tap(find.byKey(const ValueKey<String>('export-tab-image')));
      await tester.pump();
      expect(orderLine(tester), AppText.strings.exOrderAsksAfter);
    });

    testWidgets('the COUNT decides, not the format: stills trimmed to one '
        'frame are one file, and Android asks afterwards', (tester) async {
      await open(tester, 'android');
      await pickPngSequence(tester);
      expect(orderLine(tester), AppText.strings.exOrderAsksFirst);

      await tester.typeExportRange(inFrame: '2');
      expect(orderLine(tester), AppText.strings.exOrderAsksAfter);
    });
  });
}
