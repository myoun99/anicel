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
/// The window's side of it: when it asks and through which window (one
/// file — the save window; several — a folder), what it does with the
/// answer, and the line that says which order this export takes. Every
/// OS's road is driven from the Windows workstation through the OS seam.
void main() {
  /// What a hand-over's window is asked when it is backed out of
  /// (`a_backed_out_hand_over_is_asked_about_test` has the law).
  const question = ValueKey<String>('hand-over-pending-dialog');
  const everyTime = 1 << 30;

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
    FolderPicker.debugOperatingSystem = null;
    AppStorage.debugAllFilesAccessOverride = null;
    FolderPicker.debugFolderPicker = null;
    FolderPicker.debugFileExporter = null;
    FolderPicker.debugFilesExporter = null;
    FolderPicker.debugSaveDestinationPicker = null;
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
    // Both seams: the door reads the first, and what a pick GRANTS is read
    // from the picker's own. Inherited, the host would answer the second —
    // and a macOS runner answers it differently from this workstation.
    FolderPicker.debugOperatingSystem = operatingSystem;
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
  /// writing down what it was handed — once it has been backed out of
  /// [backedOut] times.
  List<List<String>> iosPickerPlaces({int backedOut = 0}) {
    final handed = <List<String>>[];
    FolderPicker.debugFilesExporter = (sourcePaths) async {
      handed.add(namesOf(sourcePaths));
      if (handed.length <= backedOut) {
        return const FolderGrant.cancelled();
      }
      for (final source in sourcePaths) {
        moveIntoFolder(source, placed.path);
      }
      return FolderGrant.granted(path: placed.path);
    };
    return handed;
  }

  /// Starts [run] and comes back once [reached] — in real time, as a run
  /// writes its files — with the future of the whole of it: a run that
  /// stops at a window of its own to be answered.
  Future<({Future<void> whole})> begun(
    WidgetTester tester,
    Future<void> Function() run,
    bool Function() reached,
  ) async {
    late Future<void> whole;
    await tester.runAsync(() async {
      whole = run();
      while (!reached()) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pump();
    await tester.pump();
    return (whole: whole);
  }

  /// Lets [whole] run to its end.
  ///
  /// ⚠️With a limit of its own: a run left standing at a window nobody
  /// answers never ends, and without one the test would wait out the
  /// binding's ten minutes — each of them (measured 2026-10-07, a mutant
  /// that swapped the two answers held the machine for twenty).
  Future<void> ended(WidgetTester tester, Future<void> whole) async {
    await tester.runAsync(() => whole.timeout(const Duration(seconds: 30)));
    await tester.pump();
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

    testWidgets('Android asks a FOLDER first for several files, and the run '
        'writes straight into it', (tester) async {
      AppStorage.debugAllFilesAccessOverride = true;
      List<String>? madeWhenAsked;
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
        madeWhenAsked = leftIn(outbox());
        return FolderGrant.granted(path: placed.path);
      };
      final state = await open(tester, 'android');
      await pickPngSequence(tester);

      await tester.runAsync(state.export);
      await tester.pump();

      expect(madeWhenAsked, isEmpty);
      expect(filesWrittenUnder(placed), ['frame_0001.png', 'frame_0002.png']);
      expect(leftIn(outbox()), isEmpty);
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

  group('ONE file is asked the SAVE window, where the platform has one to '
      'ask before the file exists', () {
    /// A desktop's two windows, written down as they are asked: the save
    /// window answering [saveAs] in [placed] — or backed out of, when null
    /// — and the folder window answering [placed].
    ({
      List<String> names,
      List<String?> openedAt,
      List<List<String>> madeWhenAsked,
      List<String?> folders,
    })
    desktopWindows({required String? saveAs}) {
      final names = <String>[];
      final openedAt = <String?>[];
      final madeWhenAsked = <List<String>>[];
      final folders = <String?>[];
      FolderPicker.debugSaveDestinationPicker = ({
        required String suggestedName,
        String? initialDirectory,
      }) async {
        names.add(suggestedName);
        openedAt.add(initialDirectory);
        madeWhenAsked.add([
          ...filesWrittenUnder(placed),
          ...leftIn(outbox()),
        ]);
        return saveAs == null
            ? const FolderGrant.cancelled()
            : FolderGrant.granted(
                path: '${placed.path}/$saveAs',
                kind: GrantKind.file,
              );
      };
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
        folders.add(initialDirectory);
        return FolderGrant.granted(path: placed.path);
      };
      return (
        names: names,
        openedAt: openedAt,
        madeWhenAsked: madeWhenAsked,
        folders: folders,
      );
    }

    Future<void> showTab(WidgetTester tester, String tab) async {
      await tester.tap(find.byKey(ValueKey<String>('export-tab-$tab')));
      await tester.pump();
    }

    testWidgets('🎯a desktop: Export of ONE file opens the save window with '
        'its name in it before the file is made — and the run writes it at '
        'the path the window answers, under the name given there', (
      tester,
    ) async {
      final windows = desktopWindows(saveAs: 'renamed.png');
      final state = await open(tester, 'windows');
      await showTab(tester, 'image');
      expect(windows.names, isEmpty, reason: 'nothing is asked until Export');

      await tester.runAsync(state.export);
      await tester.pump();

      expect(windows.names, ['Project.png']);
      expect(windows.folders, isEmpty, reason: 'one file asks no folder');
      expect(windows.madeWhenAsked.single, isEmpty);
      expect(filesWrittenUnder(placed), ['renamed.png']);
      expect(leftIn(outbox()), isEmpty, reason: 'it wrote straight there');
      expect(status(tester), AppText.strings.exDoneFile('renamed.png'));
    });

    testWidgets('the COUNT decides the window, not the format: stills '
        'trimmed to ONE frame are asked the save window by the name their '
        'rule gives, and written under the one given there', (tester) async {
      final windows = desktopWindows(saveAs: 'only.png');
      final state = await open(tester, 'windows');
      await pickPngSequence(tester);
      await tester.typeExportRange(inFrame: '2');

      await tester.runAsync(state.export);
      await tester.pump();

      expect(windows.names, ['frame_0001.png']);
      expect(windows.folders, isEmpty);
      expect(filesWrittenUnder(placed), ['only.png']);
    });

    testWidgets('a video is encoded AT the path the window answers', (
      tester,
    ) async {
      final windows = desktopWindows(saveAs: 'rush.mp4');
      List<String>? encoderArguments;
      final state = await open(
        tester,
        'windows',
        video: VideoExportService(
          processStarter: (executable, arguments) async {
            encoderArguments = arguments;
            return FakeFfmpegProcess();
          },
        ),
      );

      await tester.runAsync(state.export);
      await tester.pump();

      expect(windows.names, ['Project.mp4']);
      expect(encoderArguments!.last, '${placed.path}/rush.mp4');
    });

    testWidgets('🎯macOS asks ONE file its save window first, as Windows '
        'does — and the file, made in the run\'s room, is MOVED onto the '
        'place the window answered, under the name given there', (
      tester,
    ) async {
      final windows = desktopWindows(saveAs: 'renamed.png');
      final state = await open(tester, 'macos');
      await showTab(tester, 'image');
      expect(orderLine(tester), AppText.strings.exOrderAsksFirst);

      await tester.runAsync(state.export);
      await tester.pump();

      expect(windows.names, ['Project.png']);
      expect(windows.folders, isEmpty);
      expect(windows.madeWhenAsked.single, isEmpty);
      expect(filesWrittenUnder(placed), ['renamed.png']);
      expect(leftIn(outbox()), isEmpty, reason: 'the room keeps nothing');
      expect(status(tester), AppText.strings.exDoneFile('renamed.png'));
    });

    testWidgets('macOS: the place is the one path the app may write, so the '
        'WRITERS are pointed at the run\'s room — a video\'s encoder is '
        'handed a path there, under the name the file will wear', (
      tester,
    ) async {
      desktopWindows(saveAs: 'rush.mp4');
      List<String>? encoderArguments;
      final state = await open(
        tester,
        'macos',
        video: VideoExportService(
          processStarter: (executable, arguments) async {
            encoderArguments = arguments;
            return FakeFfmpegProcess();
          },
        ),
      );

      await tester.runAsync(state.export);
      await tester.pump();

      final room = outbox().path.replaceAll(r'\', '/');
      final handed = encoderArguments!.last.replaceAll(r'\', '/');
      expect(handed, startsWith('$room/'));
      expect(handed, endsWith('/rush.mp4'));
      expect(leftIn(outbox()), isEmpty);
    });

    testWidgets('macOS: a run that is STOPPED puts nothing at the place — '
        'what it had made so far goes with its room', (tester) async {
      desktopWindows(saveAs: 'rush.mp4');
      late ExportDialogState state;
      state = await open(
        tester,
        'macos',
        video: VideoExportService(
          processStarter: (executable, arguments) async {
            // What an encoder leaves when it is cut short: a file begun.
            File(arguments.last).writeAsStringSync('half a movie');
            return FakeFfmpegProcess(
              onFrame: (framesSoFar) {
                if (framesSoFar >= 1) {
                  state.cancelExport();
                }
              },
            );
          },
        ),
      );

      await tester.runAsync(state.export);
      await tester.pump();

      expect(filesWrittenUnder(placed), isEmpty);
      expect(leftIn(outbox()), isEmpty);
    });

    testWidgets('backing out of the save window runs nothing — and says '
        'nothing', (tester) async {
      final windows = desktopWindows(saveAs: null);
      final state = await open(tester, 'windows');
      await showTab(tester, 'image');

      await tester.runAsync(state.export);
      await tester.pump();

      expect(windows.names, hasLength(1));
      expect(filesWrittenUnder(placed), isEmpty);
      expect(status(tester), '');
      expect(exportLive(tester), isTrue);
    });

    testWidgets('the next window opens in the folder the last place stands '
        'in — a file\'s as a folder\'s', (tester) async {
      final windows = desktopWindows(saveAs: 'renamed.png');
      final state = await open(tester, 'windows');
      await showTab(tester, 'image');
      await tester.runAsync(state.export);
      await tester.pump();

      await showTab(tester, 'sequence');
      await pickPngSequence(tester);
      await tester.runAsync(state.export);
      await tester.pump();

      await showTab(tester, 'image');
      await tester.runAsync(state.export);
      await tester.pump();

      expect(
        windows.folders,
        [placed.path.replaceAll(r'\', '/')],
        reason: 'the folder window, after a file was placed',
      );
      expect(
        windows.openedAt,
        [null, placed.path],
        reason: 'the save window: first of all, then after a folder',
      );
    });

    testWidgets('a lone file is asked its save window when it is QUEUED, '
        'and the queue writes it there — asking nothing more', (tester) async {
      final windows = desktopWindows(saveAs: 'queued.png');
      final state = await open(tester, 'windows');
      await showTab(tester, 'image');

      await tapKey(tester, 'export-queue-add-button');
      expect(windows.names, ['Project.png'], reason: 'asked as it is queued');
      expect(filesWrittenUnder(placed), isEmpty);

      await tester.runAsync(state.runQueue);
      await tester.pump();

      expect(windows.names, hasLength(1), reason: 'the run asks nothing');
      expect(windows.folders, isEmpty);
      expect(filesWrittenUnder(placed), ['queued.png']);
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

    testWidgets('🎯a hand-over the user backs out of is ASKED about, the '
        'outputs still in the run\'s room — and 다시 고르기 hands them to '
        'the same window, where they are placed (F-221-Q6)', (tester) async {
      final handed = iosPickerPlaces(backedOut: 1);
      final state = await open(tester, 'ios');
      await pickPngSequence(tester);

      final (whole: exporting) = await begun(
        tester,
        state.export,
        () => handed.length == 1,
      );

      expect(find.byKey(question), findsOneWidget);
      expect(namesOf(filesWrittenUnder(outbox())), [
        'frame_0001.png',
        'frame_0002.png',
      ], reason: 'backing out let nothing go');
      await tapKey(tester, 'hand-over-pending-pick-again');
      await ended(tester, exporting);

      expect(handed, [
        ['frame_0001.png', 'frame_0002.png'],
        ['frame_0001.png', 'frame_0002.png'],
      ]);
      expect(filesWrittenUnder(placed), ['frame_0001.png', 'frame_0002.png']);
      expect(leftIn(outbox()), isEmpty);
      expect(status(tester), isNot(AppText.strings.exHandOverDeclined));
    });

    testWidgets('버리기 at that question lets the outputs go, and the run '
        'says so', (tester) async {
      final handed = iosPickerPlaces(backedOut: everyTime);
      final state = await open(tester, 'ios');
      await pickPngSequence(tester);

      final (whole: exporting) = await begun(
        tester,
        state.export,
        () => handed.length == 1,
      );
      await tapKey(tester, 'hand-over-pending-discard');
      await ended(tester, exporting);

      expect(status(tester), AppText.strings.exHandOverDeclined);
      expect(handed, hasLength(1), reason: 'the window was not opened again');
      expect(leftIn(outbox()), isEmpty);
      expect(filesWrittenUnder(placed), isEmpty);
    });

    testWidgets('🗣️outputs that fail on their way are ASKED about, the '
        'failure said (F-221-Q7) — and 버리기 lets them go', (tester) async {
      var tried = 0;
      FolderPicker.debugFilesExporter = (sourcePaths) async {
        tried += 1;
        throw const FileSystemException('the picker lost them');
      };
      final state = await open(tester, 'ios');
      await pickPngSequence(tester);

      final (whole: exporting) = await begun(
        tester,
        state.export,
        () => tried == 1,
      );
      expect(
        find.textContaining(
          AppText.strings.exFailed(
            const FileSystemException('the picker lost them'),
          ),
        ),
        findsOneWidget,
        reason: 'the failure is said in the question',
      );
      expect(leftIn(outbox()), isNotEmpty, reason: 'nothing is let go unasked');
      await tapKey(tester, 'hand-over-pending-discard');
      await ended(tester, exporting);

      expect(status(tester), AppText.strings.exHandOverDeclined);
      expect(tried, 1, reason: 'the window was not opened again');
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

    testWidgets('🚨two jobs that each made a file of ONE name hand them over '
        'under names of their own — the later is bumped as a run bumps its '
        'own, where it would have landed on the earlier and left one', (
      tester,
    ) async {
      final handed = iosPickerPlaces();
      final state = await open(tester, 'ios');
      await tester.tap(find.byKey(const ValueKey<String>('export-tab-image')));
      await tester.pump();
      await tapKey(tester, 'export-queue-add-button');
      await tapKey(tester, 'export-queue-add-button');

      await tester.runAsync(state.runQueue);
      await tester.pump();

      expect(handed, [
        ['Project.png', 'Project_2.png'],
      ]);
      expect(filesWrittenUnder(placed), ['Project.png', 'Project_2.png']);
      expect(leftIn(outbox()), isEmpty);
    });

    testWidgets('names that differ only by CASE are one name on the disks '
        'these land on: the later is bumped all the same', (tester) async {
      final handed = iosPickerPlaces();
      final state = await open(tester, 'ios');
      await tester.tap(find.byKey(const ValueKey<String>('export-tab-image')));
      await tester.pump();
      await tapKey(tester, 'export-queue-add-button');
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('export-file-name-field')),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('export-file-name-field')),
        'project',
      );
      await tester.pump();
      await tapKey(tester, 'export-queue-add-button');

      await tester.runAsync(state.runQueue);
      await tester.pump();

      expect(handed, [
        ['Project.png', 'project_2.png'],
      ]);
    });

    testWidgets('Android: the same two reach the folder its window answers '
        'as TWO files', (tester) async {
      AppStorage.debugAllFilesAccessOverride = true;
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
          FolderGrant.granted(path: placed.path);
      final state = await open(tester, 'android');
      await tester.tap(find.byKey(const ValueKey<String>('export-tab-image')));
      await tester.pump();
      await tapKey(tester, 'export-queue-add-button');
      await tapKey(tester, 'export-queue-add-button');

      await tester.runAsync(state.runQueue);
      await tester.pump();

      expect(filesWrittenUnder(placed), ['Project.png', 'Project_2.png']);
      expect(leftIn(outbox()), isEmpty);
    });

    testWidgets('Android: a queue of single files hands them over in ONE '
        'folder window once the last is done — the save window takes one '
        'file, and these are two', (tester) async {
      AppStorage.debugAllFilesAccessOverride = true;
      final folders = <String?>[];
      var saved = 0;
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
        folders.add(initialDirectory);
        return FolderGrant.granted(path: placed.path);
      };
      FolderPicker.debugFileExporter = ({
        required String sourcePath,
        String? suggestedName,
      }) async {
        saved += 1;
        return FolderGrant.granted(path: sourcePath, kind: GrantKind.file);
      };
      final state = await open(tester, 'android');
      await tester.tap(find.byKey(const ValueKey<String>('export-tab-image')));
      await tester.pump();
      await tapKey(tester, 'export-queue-add-button');
      await tester.tap(
        find.byKey(const ValueKey<String>('export-tab-sequence')),
      );
      await tester.pump();
      await pickPngSequence(tester);
      await tester.typeExportRange(inFrame: '2');
      await tapKey(tester, 'export-queue-add-button');
      expect(folders, isEmpty, reason: 'one file each: nothing asked first');

      await tester.runAsync(state.runQueue);
      await tester.pump();

      expect(folders, hasLength(1));
      expect(saved, 0);
      expect(filesWrittenUnder(placed), ['Project.png', 'frame_0001.png']);
      expect(leftIn(outbox()), isEmpty);
    });

    testWidgets('🎯a queue whose hand-over is backed out of is asked ONCE, '
        'for every job\'s outputs — 다시 고르기 hands them all to one window '
        'again', (tester) async {
      final handed = iosPickerPlaces(backedOut: 1);
      final state = await open(tester, 'ios');
      await pickPngSequence(tester);
      await tapKey(tester, 'export-queue-add-button');
      await tester.tap(find.byKey(const ValueKey<String>('export-tab-image')));
      await tester.pump();
      await tapKey(tester, 'export-queue-add-button');

      final (whole: running) = await begun(
        tester,
        state.runQueue,
        () => handed.length == 1,
      );

      expect(find.byKey(question), findsOneWidget);
      await tapKey(tester, 'hand-over-pending-pick-again');
      await ended(tester, running);

      const all = ['Project.png', 'frame_0001.png', 'frame_0002.png'];
      expect(handed, [all, all]);
      expect(filesWrittenUnder(placed), all);
      expect(leftIn(outbox()), isEmpty);
      expect(status(tester), isNot(AppText.strings.exHandOverDeclined));
    });

    testWidgets('a queue let go at that question says so', (tester) async {
      final handed = iosPickerPlaces(backedOut: everyTime);
      final state = await open(tester, 'ios');
      await pickPngSequence(tester);
      await tapKey(tester, 'export-queue-add-button');

      final (whole: running) = await begun(
        tester,
        state.runQueue,
        () => handed.length == 1,
      );
      await tapKey(tester, 'hand-over-pending-discard');
      await ended(tester, running);

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
