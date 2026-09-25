import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_size_mode.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_image_encoder.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart'
    show GrantedDirectory;
import 'package:anicel/src/services/persistence/folder_grant.dart'
    show FolderGrant, FolderPicker;
import 'package:anicel/src/services/persistence/app_export_settings_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/export/video_export_service.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/project_scratch_folder.dart' show deleteAfterSessionEnds;
import 'fake_ffmpeg_process.dart';
import '../../helpers/temp_dir.dart';

void main() {
  late Directory temp;

  setUp(() {
    AppExport.settings.value = AppExportSettings();
    temp = Directory.systemTemp.createTempSync('qa-export-dialog');
  });

  tearDown(() {
    AppExport.settings.value = AppExportSettings();
    deleteTempQuietly(temp);
  });

  // Cels are numbered by their frame NAME (an unnamed frame is the
  // in-between mark and exports no file), so the fixture ids' digits double
  // as the cel numbers: 'f1' is cel 1.
  Frame frame(String id) => Frame(
    id: FrameId(id),
    duration: 1,
    strokes: const [],
    name: id.replaceAll(RegExp('[^0-9]'), ''),
  );

  /// Two cuts (2 + 3 frames) on the active track, a third cut on another
  /// track that exports must never touch. The first cut's drawing layer
  /// carries two authored cels (no brush artwork — surfaces stay empty).
  EditorSessionManager exportSession() {
    return EditorSessionManager(
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
                    mark: const LayerMark(process: LayerProcess.key),
                    frames: [frame('f1'), frame('f2')],
                  ),
                  createCameraLayer(cutId: const CutId('cut')),
                ],
              ),
              Cut(
                id: const CutId('cut-b'),
                name: 'Cut B',
                duration: 3,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  Layer(
                    id: const LayerId('layer-b'),
                    name: 'A',
                    mark: const LayerMark(process: LayerProcess.key),
                    frames: const [],
                  ),
                  createCameraLayer(cutId: const CutId('cut-b')),
                ],
              ),
            ],
          ),
          Track(
            id: const TrackId('other-track'),
            name: 'Other',
            cuts: [
              Cut(
                id: const CutId('cut-c'),
                name: 'Cut C',
                duration: 10,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [createCameraLayer(cutId: const CutId('cut-c'))],
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
  }

  Future<ExportDialogState> pumpDialog(
    WidgetTester tester,
    EditorSessionManager session, {
    ExportDirectoryPicker? exportDirectoryPicker,
    VideoExportService videoExportService = const VideoExportService(),
    AppExportSettingsStore? settingsStore,
    ExportFormatAvailability? formatAvailability,
    Key? dialogKey,
    TextStyle face = const TextStyle(),
  }) async {
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Unmount at teardown: the dialog's dispose cancels the preview
    // debounce timer — otherwise every test ends with a pending Timer.
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DefaultTextStyle.merge(
            style: face,
            child: ExportDialog(
              // A distinct key forces a COLD State — same-type pumps reuse
              // the element and skip initState (the store-restore path).
              key: dialogKey,
              session: session,
              exportDirectoryPicker: exportDirectoryPicker,
              videoExportService: videoExportService,
              settingsStore: settingsStore,
              // Permissive by default: the fake ffmpeg carries any pair in
              // tests; availability-gating gets its own dedicated test.
              formatAvailability:
                  formatAvailability ?? ExportFormatAvailability.permissive(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

  Future<void> browseTo(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('export-browse-button')));
    await tester.pump();
    await tester.pump();
  }

  Future<void> pickStillPng(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('export-format-still-png')),
    );
    await tester.pump();
  }

  Future<void> switchTab(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey<String>('export-tab-$tab')));
    await tester.pump();
  }

  bool exportEnabled(WidgetTester tester) {
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('export-run-button')),
    );
    return button.onPressed != null;
  }

  String statusText(WidgetTester tester) {
    final status = tester.widget<Text>(
      find.byKey(const ValueKey<String>('export-status')),
    );
    return status.data ?? '';
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

  int pngSignatureCount(Uint8List bytes) {
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    var count = 0;
    for (var i = 0; i + signature.length <= bytes.length; i += 1) {
      var match = true;
      for (var j = 0; j < signature.length; j += 1) {
        if (bytes[i + j] != signature[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        count += 1;
      }
    }
    return count;
  }

  group('shell', () {
    testWidgets('R27 #31: the window OPENS while the playhead is parked in a '
        'gap — no active cut is a position, not a crash', (tester) async {
      final session = exportSession();
      // Park in the leading gap by seeking a global frame the axis has no
      // cut for: the session deselects the cut (UI-R9 #3 gap state).
      session.selectGlobalFrame(500);
      expect(session.activeCutOrNull, isNull);
      expect(session.activeCutSpan.exportAnchorIsFallback, isTrue);
      // …and the fallback is the FIRST cut on the axis, not "no film".
      expect(
        session.activeCutSpan.exportAnchorCutOrNull?.id,
        session.repository.requireProject().tracks.first.cuts.first.id,
      );

      final state = await pumpDialog(tester, session);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('export-dialog-no-cuts')),
        findsNothing,
      );
      // Gap-anchored windows open PROJECT-scoped: "active cut" would name
      // a cut the user is not standing on.
      expect(state.debugSpecs.sequence.scope, ExportScopeKind.project);
    });

    testWidgets('export stays disabled until a location is chosen',
        (tester) async {
      await pumpDialog(tester, exportSession());
      expect(exportEnabled(tester), isFalse);
      expect(find.text('Choose a folder…'), findsOneWidget);

      await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await browseTo(tester);
      expect(exportEnabled(tester), isTrue);
    });

    testWidgets('plan headline covers the active cut by default',
        (tester) async {
      await pumpDialog(tester, exportSession());
      final headline = tester.widget<Text>(
        find.byKey(const ValueKey<String>('export-plan-headline')),
      );
      expect(headline.data, contains('2 frames'));
      expect(headline.data, contains('32×18'));
    });

    testWidgets('drawers collapse to strips and reopen', (tester) async {
      await pumpDialog(tester, exportSession());
      await tester.tap(
        find.byKey(const ValueKey<String>('export-presets-collapse')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('export-presets-strip')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('export-presets-strip')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('export-preset-save-current')),
        findsOneWidget,
      );
    });
  });

  group('sequence stills', () {
    testWidgets('numbered PNG files land in the location', (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await browseTo(tester);
      await pickStillPng(tester);
      await tester.runAsync(state.export);
      await tester.pump();

      expect(filesIn(temp), ['frame_0001.png', 'frame_0002.png']);
      expect(statusText(tester), 'Exported 2 frames.');
    });

    testWidgets('naming module renames the base', (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await browseTo(tester);
      await pickStillPng(tester);
      // The Naming accordion is collapsed by default — open, then edit.
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
      await tester.runAsync(state.export);
      await tester.pump();

      expect(filesIn(temp), ['shot_0001.png', 'shot_0002.png']);
    });

    testWidgets('in/out trims the cut scope; a reversed range disables',
        (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await browseTo(tester);
      await pickStillPng(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('export-range-start-field')),
        '2',
      );
      await tester.pump();
      await tester.runAsync(state.export);
      await tester.pump();
      expect(filesIn(temp), ['frame_0001.png']);

      await tester.enterText(
        find.byKey(const ValueKey<String>('export-range-start-field')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('export-range-end-field')),
        '1',
      );
      await tester.pump();
      expect(exportEnabled(tester), isFalse);
    });

    testWidgets(
        'project scope walks the active track in order and forces camera',
        (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await browseTo(tester);
      await pickStillPng(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('export-scope-project')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('export-size-canvas')),
        findsNothing,
      );
      await tester.runAsync(state.export);
      await tester.pump();

      expect(filesIn(temp), [
        'frame_0001.png',
        'frame_0002.png',
        'frame_0003.png',
        'frame_0004.png',
        'frame_0005.png',
      ]);
    });
  });

  group('sequence video', () {
    testWidgets('MP4 pipes every planned frame to the encoder',
        (tester) async {
      final fake = FakeFfmpegProcess();
      late List<String> capturedArgs;
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
        videoExportService: VideoExportService(
          processStarter: (executable, arguments) async {
            capturedArgs = arguments;
            return fake;
          },
        ),
      );
      await browseTo(tester);
      await tester.runAsync(state.export);
      await tester.pump();

      expect(
        pngSignatureCount(Uint8List.fromList(fake.collectedStdin.toBytes())),
        2,
      );
      expect(capturedArgs, contains('24'));
      expect(
        capturedArgs.last.replaceAll('\\', '/'),
        endsWith('/Project.mp4'),
      );
      expect(statusText(tester), 'Exported video (2 frames).');
    });

    testWidgets('audio accordion reports the toggle in its summary',
        (tester) async {
      await pumpDialog(tester, exportSession());
      expect(find.textContaining('SE muxed'), findsOneWidget);
      await tester.ensureVisible(find.textContaining('Audio'));
      await tester.tap(find.textContaining('Audio'));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('export-audio-toggle')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('export-audio-toggle')),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Audio'));
      await tester.tap(find.text('Audio'));
      await tester.pump();
      expect(find.textContaining('Audio — Off'), findsOneWidget);
    });
  });

  group('image tab', () {
    testWidgets('exports the current frame as a single file', (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'image');
      await browseTo(tester);
      await tester.runAsync(state.export);
      await tester.pump();

      expect(filesIn(temp), ['Project.png']);
      expect(statusText(tester), 'Exported Project.png.');
    });

    testWidgets('the size accordion offers the cut\'s canvas (one cut, no '
        'project scope) and the pick writes the spec', (tester) async {
      final state = await pumpDialog(tester, exportSession());
      await switchTab(tester, 'image');
      final canvasChip = find.byKey(
        const ValueKey<String>('export-size-canvas'),
      );
      await tester.ensureVisible(canvasChip);
      expect(canvasChip, findsOneWidget);
      // The one canvas size on the table is the active cut's own.
      expect(find.textContaining('Canvas 8×8'), findsOneWidget);
      expect(state.debugSpecs.image.sizeMode, ExportSizeMode.camera);
      await tester.tap(canvasChip);
      await tester.pump();
      expect(state.debugSpecs.image.sizeMode, ExportSizeMode.canvas);
    });
  });

  group('F-124: the window speaks the program language', () {
    // The English rows are the tests above; these read the same runs in
    // Korean. Every expectation is the Korean table's sentence spelled out,
    // so a surface that goes back to hardcoding English turns one red.
    setUp(
      () => AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      ),
    );
    tearDown(() => AppText.settings.value = const AppLanguageSettings());

    testWidgets('sequence stills: the file bar, the plan, the presets and the '
        'finished sentence', (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      // The tab opens on video — one file, so the bar names a file; the
      // still format numbers them, and the bar names the pattern instead.
      expect(find.text('파일'), findsOneWidget);
      expect(find.text('위치'), findsOneWidget);
      expect(find.text('폴더 선택…'), findsOneWidget);
      expect(find.text('프리셋 · 시퀀스'), findsOneWidget);
      final headline = tester.widget<Text>(
        find.byKey(const ValueKey<String>('export-plan-headline')),
      );
      expect(headline.data, '카메라를 거쳐 32×18로 2프레임.');

      await browseTo(tester);
      await pickStillPng(tester);
      expect(find.text('패턴'), findsOneWidget);
      await tester.runAsync(state.export);
      await tester.pump();
      expect(statusText(tester), '2프레임 내보냈습니다.');
    });

    testWidgets('image tab: the file label, the size pills and the file '
        'sentence', (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'image');
      expect(find.text('파일'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('export-size-canvas')),
      );
      expect(find.textContaining('캔버스 8×8'), findsOneWidget);
      expect(find.textContaining('카메라 32×18'), findsOneWidget);

      await browseTo(tester);
      await tester.runAsync(state.export);
      await tester.pump();
      expect(statusText(tester), 'Project.png 내보냈습니다.');
    });

    testWidgets('the sheet image counts sheet pages', (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'timesheet');
      await browseTo(tester);
      await tester.runAsync(state.export);
      await tester.pump();
      expect(statusText(tester), '시트 1페이지 내보냈습니다.');
    });

    testWidgets('XDTS counts its sheets', (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'timesheet');
      await browseTo(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('export-tsformat-xdts')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('export-scope-project')),
      );
      await tester.pump();
      await tester.runAsync(state.export);
      await tester.pump();
      expect(statusText(tester), 'XDTS 시트 2장 내보냈습니다.');
    });

    testWidgets('video: the audio summary and the finished sentence', (
      tester,
    ) async {
      final fake = FakeFfmpegProcess();
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
        videoExportService: VideoExportService(
          processStarter: (executable, arguments) async => fake,
        ),
      );
      expect(find.textContaining('SE 먹싱 · AAC'), findsOneWidget);

      await browseTo(tester);
      await tester.runAsync(state.export);
      await tester.pump();
      expect(statusText(tester), '영상을 내보냈습니다(2프레임).');
    });

    testWidgets('a stopped video says how much it kept', (tester) async {
      late ExportDialogState state;
      final fake = FakeFfmpegProcess(
        onFrame: (framesSoFar) {
          if (framesSoFar >= 2) {
            state.cancelExport();
          }
        },
      );
      state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
        videoExportService: VideoExportService(
          processStarter: (executable, arguments) async => fake,
        ),
      );
      // The project's five frames, so stopping after two leaves work undone.
      await tester.tap(
        find.byKey(const ValueKey<String>('export-scope-project')),
      );
      await tester.pump();
      await browseTo(tester);
      await tester.runAsync(state.export);
      await tester.pump();
      expect(
        statusText(tester),
        '2프레임 내보낸 뒤 취소했습니다(중간까지의 영상은 남겼습니다).',
      );
    });

    testWidgets('the render queue: its header, a job, the job states and the '
        'resting sentence', (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await browseTo(tester);
      await pickStillPng(tester);
      expect(find.text('렌더 대기열'), findsOneWidget);
      expect(find.text('모두 렌더'), findsOneWidget);

      // Job 1 aims inside a FILE, so its write fails; job 2 lands.
      final blocker = File('${temp.path}/blocker')..createSync();
      state.debugSetLocationForTests('${blocker.path}/nested');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('export-queue-add-button')),
      );
      await tester.pump();
      expect(find.text('작업 1 · 시퀀스'), findsOneWidget);
      state.debugSetLocationForTests(temp.path);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('export-queue-add-button')),
      );
      await tester.pump();

      await tester.runAsync(state.runQueue);
      await tester.pump();
      expect(find.text('실패'), findsOneWidget);
      expect(find.text('완료'), findsOneWidget);
      expect(statusText(tester), '대기열: 작업 1개 완료, 1개 실패.');
    });
  });

  group('cels tab', () {
    testWidgets('pattern preview names the first cel; empty cels skip',
        (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'cels');
      final pattern = tester.widget<Text>(
        find.byKey(const ValueKey<String>('export-pattern-preview')),
      );
      expect(pattern.data, 'A1.png');

      await browseTo(tester);
      await tester.runAsync(state.export);
      await tester.pump();
      // The fixture cels carry no strokes — renders resolve empty, files
      // skip, and the summary says so.
      expect(statusText(tester), contains('empty skipped'));
    });
  });

  group('timesheet tab', () {
    testWidgets('the default Sheet PNG writes the panel paper per cut',
        (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'timesheet');
      await browseTo(tester);
      await tester.runAsync(state.export);
      await tester.pump();

      // The sheet is filed under the cut's NAME — its number, whatever the
      // user called it — not its position in the track.
      expect(filesIn(temp), ['CUTCut.png']);
      final bytes = File('${temp.path}/CUTCut.png').readAsBytesSync();
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      expect(statusText(tester), 'Exported 1 sheet page.');
    });

    // 유저 2026-09-26: 「다 통일해줘. 기능은 어차피 생길수있어」 — the sheet
    // exported no ink at all, where the conte's and the envelope's rode.
    testWidgets('what was written on the sheet rides its PNG, where it was '
        'written', (tester) async {
      final session = exportSession();
      addTearDown(session.dispose);
      session.renderCaches.timesheetInkPageStore.storeBakedSurface(
        timesheetInkPageKey(const CutId('cut'), 0),
        _redSurface(),
      );
      final state = await pumpDialog(
        tester,
        session,
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'timesheet');
      await browseTo(tester);
      await tester.runAsync(state.export);
      await tester.pump();

      final image = (await tester.runAsync(
        () => decodeImageFromList(
          File('${temp.path}/CUTCut.png').readAsBytesSync(),
        ),
      ))!;
      addTearDown(image.dispose);
      final data = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      // The page ink's surface pixel (0, 0) sits on the page's corner: the
      // 16px stroke is 4 sheet units, 8 pixels at the export's 2×.
      expect(data.getUint8(0), greaterThan(200), reason: 'red, from the store');
      expect(data.getUint8(1), lessThan(80));
    });

    testWidgets('writes one xdts per cut under the project scope',
        (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'timesheet');
      await browseTo(tester);
      // XDTS is a chip now (Sheet PNG became the default).
      await tester.tap(
        find.byKey(const ValueKey<String>('export-tsformat-xdts')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('export-scope-project')),
      );
      await tester.pump();
      await tester.runAsync(state.export);
      await tester.pump();

      expect(filesIn(temp), ['CUTCut B.xdts', 'CUTCut.xdts']);
      expect(statusText(tester), 'Exported 2 XDTS sheets.');
      final content = File('${temp.path}/CUTCut.xdts').readAsStringSync();
      expect(content, contains('exchangeDigitalTimeSheet'));
    });
  });

  group('preview & nav (EX3)', () {
    testWidgets('the image tab exports the frame the nav points at',
        (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'image');
      expect(state.debugImageFrame, 0);
      await tester.tap(find.byKey(const ValueKey<String>('export-nav-next')));
      await tester.pump();
      expect(state.debugImageFrame, 1);
      final transport = tester.widget<Text>(
        find.byKey(const ValueKey<String>('export-transport-line')),
      );
      expect(transport.data, 'F2 / 2 · Cut');

      await browseTo(tester);
      await tester.runAsync(state.export);
      await tester.pump();
      expect(filesIn(temp), ['Project.png']);
    });

    testWidgets('project scope: in/out trims by whole-track positions',
        (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await browseTo(tester);
      await pickStillPng(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('export-scope-project')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('export-range-start-field')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('export-range-end-field')),
        '4',
      );
      await tester.pump();
      await tester.runAsync(state.export);
      await tester.pump();
      expect(filesIn(temp), [
        'frame_0001.png',
        'frame_0002.png',
        'frame_0003.png',
      ]);
    });

    testWidgets('sequence scrub moves the playhead caption', (tester) async {
      await pumpDialog(tester, exportSession());
      final scrub = find.byKey(const ValueKey<String>('export-nav-scrub'));
      final rect = tester.getRect(scrub);
      await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
      await tester.pump();
      final transport = tester.widget<Text>(
        find.byKey(const ValueKey<String>('export-transport-line')),
      );
      expect(transport.data, contains('F2 · Cut'));
    });

    testWidgets('an OUT typed past the axis reads as the axis end — the '
        'label says the span the export runs', (tester) async {
      await pumpDialog(tester, exportSession());
      await tester.enterText(
        find.byKey(const ValueKey<String>('export-range-start-field')),
        '1',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('export-range-end-field')),
        '9',
      );
      await tester.pump();

      final transport = tester.widget<Text>(
        find.byKey(const ValueKey<String>('export-transport-line')),
      );
      expect(transport.data, 'in 1 – out 2 (2f) · F1 · Cut');
      final headline = tester.widget<Text>(
        find.byKey(const ValueKey<String>('export-plan-headline')),
      );
      expect(headline.data, contains('2 frames'));
    });

    testWidgets('the timesheet tab scrubs cut/page (EX6)', (tester) async {
      await pumpDialog(tester, exportSession());
      await switchTab(tester, 'timesheet');
      expect(
        find.byKey(const ValueKey<String>('export-nav-scrub')),
        findsOneWidget,
      );
      final transport = tester.widget<Text>(
        find.byKey(const ValueKey<String>('export-transport-line')),
      );
      expect(transport.data, contains('CUTCut · p1/1'));
    });

    /// 🚨THE FILE-BAR PREVIEW AND THE OUTPUT LINE ARE ONE ANSWER.
    ///
    /// They used to work out 「what comes out」 separately, and the copies had
    /// drifted: the preview printed a hardcoded `CUT1.xdts` for every
    /// project, whatever the cut was called (감사 2026-09-09). Nothing
    /// measured it — the whole branch could be deleted and the suite stayed
    /// green. This pins the NAME, so a second implementation cannot come
    /// back and lie again.
    testWidgets('the XDTS name reads the cut, and the output line says the '
        'same thing', (tester) async {
      await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'timesheet');
      await browseTo(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('export-tsformat-xdts')),
      );
      await tester.pump();

      // The fixture's cut is named 'Cut', so the file is CUTCut.xdts — the
      // same name the timesheet export actually writes.
      final pattern = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('export-pattern-preview')),
          )
          .data;
      expect(pattern, 'CUTCut.xdts');
      final line = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('export-output-line')),
          )
          .data;
      expect(line, contains('CUTCut.xdts'));
    });

    testWidgets('a flushed preview shows the rendered picture',
        (tester) async {
      final state = await pumpDialog(tester, exportSession());
      expect(
        find.byKey(const ValueKey<String>('export-preview-image')),
        findsNothing,
      );
      await tester.runAsync(state.debugFlushPreview);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('export-preview-image')),
        findsOneWidget,
      );
    });
  });

  group('codec lineup (EX4)', () {
    testWidgets('H.265 rides the ffmpeg fallback with libx265',
        (tester) async {
      final fake = FakeFfmpegProcess();
      late List<String> capturedArgs;
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
        videoExportService: VideoExportService(
          processStarter: (executable, arguments) async {
            capturedArgs = arguments;
            return fake;
          },
        ),
      );
      await browseTo(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('export-format-codec-h265')),
      );
      await tester.pump();
      await tester.runAsync(state.export);
      await tester.pump();
      expect(capturedArgs, contains('libx265'));
      expect(
        capturedArgs.last.replaceAll('\\', '/'),
        endsWith('/Project.mp4'),
      );
    });

    testWidgets('MOV ProRes 4444 α: prores_ks profile 4, PCM, .mov name',
        (tester) async {
      final fake = FakeFfmpegProcess();
      late List<String> capturedArgs;
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
        videoExportService: VideoExportService(
          processStarter: (executable, arguments) async {
            capturedArgs = arguments;
            return fake;
          },
        ),
      );
      await browseTo(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('export-format-container-mov')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('export-format-codec-prores4444'),
        ),
      );
      await tester.pump();
      // 4444 exposes the channel choice; RGBA is the default already.
      expect(
        find.byKey(const ValueKey<String>('export-format-channels-rgba')),
        findsNothing,
        reason: 'video channels stay internal — wantsAlpha follows 4444',
      );
      await tester.runAsync(state.export);
      await tester.pump();
      expect(capturedArgs, containsAllInOrder(['-profile:v', '4']));
      expect(capturedArgs, contains('yuva444p10le'));
      // The fixture has no SE audio — no audio codec at all, and never
      // the AAC an H.26x run would carry (the PCM pairing is pinned in
      // video_export_codec_args_test).
      expect(capturedArgs, isNot(contains('aac')));
      expect(
        capturedArgs.last.replaceAll('\\', '/'),
        endsWith('/Project.mov'),
      );
    });

    testWidgets('a restrictive availability grays the pair with a reason',
        (tester) async {
      final restrictive = ExportFormatAvailability(
        encoderResolver: () => null,
        ffmpegCheck: () async => false,
        jpgSupported: false,
      );
      addTearDown(restrictive.dispose);
      await pumpDialog(
        tester,
        exportSession(),
        formatAvailability: restrictive,
      );
      await tester.pump();
      final h265 = find.byKey(
        const ValueKey<String>('export-format-codec-h265'),
      );
      expect(h265, findsOneWidget);
      expect(
        find.ancestor(of: h265, matching: find.byType(AppTooltip)),
        findsOneWidget,
        reason: 'a grayed chip explains itself',
      );
      // The tap is a no-op on a grayed chip — H.264 stays selected.
      await tester.tap(h265);
      await tester.pump();
      final h264Chip = tester.widget<ExportPill>(
        find.byKey(const ValueKey<String>('export-format-codec-h264')),
      );
      expect(h264Chip.selected, isTrue);
    });

    testWidgets('JPG sequence writes .jpg files through the native encoder',
        (tester) async {
      final enginePath = nativeEngineLibraryPathOrNull();
      if (enginePath == null) {
        markTestSkipped(nativeEngineMissingSkipReason);
        return;
      }
      QaImageEncoder.debugResetForTests();
      debugQaEngineLibraryPathOverride = enginePath;
      addTearDown(() {
        debugQaEngineLibraryPathOverride = null;
        QaImageEncoder.debugResetForTests();
      });
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await browseTo(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('export-format-still-jpg')),
      );
      await tester.pump();
      await tester.runAsync(state.export);
      await tester.pump();
      expect(filesIn(temp), ['frame_0001.jpg', 'frame_0002.jpg']);
      final bytes = File('${temp.path}/frame_0001.jpg').readAsBytesSync();
      expect(bytes.sublist(0, 2), [0xFF, 0xD8]);
    });
  });

  group('presets', () {
    testWidgets('save current, drift away, apply snaps back', (tester) async {
      await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await browseTo(tester);
      await pickStillPng(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('export-preset-save-current')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const ValueKey<String>('export-preset-name-field')),
        '납품 PNG',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('export-preset-name-save')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('납품 PNG'), findsOneWidget);

      // Drift back to video, then apply the preset — PNG returns.
      await tester.tap(
        find.byKey(const ValueKey<String>('export-format-container-mp4')),
      );
      await tester.pump();
      expect(find.textContaining('frame_0001.png …'), findsNothing);
      await tester.tap(find.text('납품 PNG'));
      await tester.pump();
      final output = tester.widget<Text>(
        find.byKey(const ValueKey<String>('export-output-line')),
      );
      expect(output.data, contains('frame_0001.png'));
    });

    testWidgets('presets persist through the injected store', (tester) async {
      final store = AppExportSettingsStore(
        filePath: '${temp.path.replaceAll('\\', '/')}/export_settings.json',
      );
      await pumpDialog(tester, exportSession(), settingsStore: store);
      await tester.pump();
      await pickStillPng(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('export-preset-save-current')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const ValueKey<String>('export-preset-name-field')),
        'p1',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('export-preset-name-save')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(File(store.filePath).existsSync(), isTrue);
      expect(File(store.filePath).readAsStringSync(), contains('p1'));
      final reloaded = await store.load();
      expect(reloaded?.presets.map((preset) => preset.name), ['p1']);

      // A cold dialog (fresh in-memory state) restores from the store.
      AppExport.settings.value = AppExportSettings();
      await pumpDialog(
        tester,
        exportSession(),
        settingsStore: store,
        dialogKey: const ValueKey<String>('cold-dialog'),
      );
      await tester.pump();
      expect(
        AppExport.settings.value.presets.map((preset) => preset.name),
        ['p1'],
        reason: 'the second dialog should adopt the store on open',
      );
      expect(find.text('p1'), findsOneWidget);
    });

    testWidgets('🚨 the replayed location reopens its grant on open, and a '
        'moved folder is followed and persisted', (tester) async {
      // Q-scoped-folder-settings: `lastLocation` is written to at the
      // NEXT launch's exports — on macOS a stored path without its
      // resolved token is refused at the first write, silently.
      final store = AppExportSettingsStore(
        filePath: '${temp.path.replaceAll('\\', '/')}/export_settings.json',
      );
      await store.save(
        AppExportSettings(
          lastLocation: const GrantedDirectory(
            path: '/old/deliver',
            bookmark: 'TOK==',
          ),
        ),
      );
      FolderPicker.debugBookmarkResolver = (base64, kind) async =>
          const FolderGrant.granted(
            path: '/mounted/deliver',
            bookmark: 'FRESH==',
          );
      addTearDown(() => FolderPicker.debugBookmarkResolver = null);
      AppExport.settings.value = AppExportSettings();

      await pumpDialog(tester, exportSession(), settingsStore: store);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        AppExport.settings.value.lastLocation,
        const GrantedDirectory(path: '/mounted/deliver', bookmark: 'FRESH=='),
        reason: 'the pair moved together — a fresh token for the folder the '
            'user renamed, persisted so the NEXT launch starts right',
      );
    });
  });

  group('the documents export in the window\'s face '
      '(documents-in-which-face-Q1)', () {
    // 🗣️유저 2026-09-24 「둘다 앱글꼴로 통일」: the export window hands the
    // face it stands in to every sheet and envelope it renders — the files
    // and the preview. Rendered in two faces the pictures must differ: a
    // render handed no face comes out the same both times.
    Future<Map<String, List<int>>> filesExportedIn(
      WidgetTester tester, {
      required String tab,
      required String family,
    }) async {
      // A folder of its own each time, so the second export writes where
      // the first did not.
      final folder = Directory.systemTemp.createTempSync('qa-export-face');
      deleteAfterSessionEnds(folder);
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => folder.path,
        face: TextStyle(fontFamily: family),
        dialogKey: ValueKey<String>('files-$tab-$family'),
      );
      await switchTab(tester, tab);
      await browseTo(tester);
      await tester.runAsync(state.export);
      await tester.pump();
      return {
        for (final name in filesIn(folder))
          name: File('${folder.path}/$name').readAsBytesSync(),
      };
    }

    Future<List<int>> previewIn(
      WidgetTester tester, {
      required String tab,
      required String family,
    }) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        face: TextStyle(fontFamily: family),
        dialogKey: ValueKey<String>('preview-$tab-$family'),
      );
      await switchTab(tester, tab);
      await tester.runAsync(state.debugFlushPreview);
      await tester.pump();
      final image = tester
          .widget<RawImage>(
            find.byKey(const ValueKey<String>('export-preview-image')),
          )
          .image!;
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      return bytes!.buffer.asUint8List().toList();
    }

    for (final tab in ['timesheet', 'envelope']) {
      testWidgets('$tab: the files', (tester) async {
        await loadTheAppFaces();
        final biz = await filesExportedIn(
          tester,
          tab: tab,
          family: 'BIZ UDPGothic',
        );
        final nanum = await filesExportedIn(
          tester,
          tab: tab,
          family: 'Nanum Gothic',
        );
        expect(biz.keys, isNotEmpty, reason: 'the premise: files were written');
        expect(nanum.keys, biz.keys);
        for (final name in biz.keys) {
          expect(biz[name], isNot(nanum[name]), reason: name);
        }
      });

      testWidgets('$tab: the preview', (tester) async {
        await loadTheAppFaces();
        expect(
          await previewIn(tester, tab: tab, family: 'BIZ UDPGothic'),
          isNot(await previewIn(tester, tab: tab, family: 'Nanum Gothic')),
        );
      });
    }
  });
}

/// A 16px surface inked solid red — what a landed stroke leaves in a store.
BitmapSurface _redSurface() {
  final pixels = Uint8List(8 * 8 * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 0xFF;
    pixels[i + 3] = 0xFF;
  }
  return BitmapSurface(
    canvasSize: const CanvasSize(width: 16, height: 16),
    tileSize: 8,
    tiles: {
      for (var y = 0; y < 2; y += 1)
        for (var x = 0; x < 2; x += 1)
          TileCoord(x: x, y: y): BitmapTile(size: 8, pixels: pixels),
    },
  );
}
