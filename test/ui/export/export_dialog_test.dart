import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_instruction.dart';
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
import 'package:anicel/src/services/persistence/app_export_settings_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/video_export_service.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/export_cels_board_probe.dart';
import '../../helpers/export_preview_probe.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/project_scratch_folder.dart' show deleteAfterSessionEnds;
import 'fake_ffmpeg_process.dart';
import '../../helpers/temp_dir.dart';

import '../../helpers/files_written_under.dart';
import '../../helpers/export_scope_pick.dart';

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
    await tester.binding.setSurfaceSize(const Size(1280, 660));
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

  Future<void> pickStillPng(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('export-format-still-png')),
    );
    await tester.pump();
  }

  /// Opens [tab]. The timesheet and the cut envelope are no tabs: they are
  /// kinds the Cels tab writes (F-289), so their names open the Cels tab
  /// writing THAT document alone — its row the list's one row, stood on.
  Future<void> switchTab(WidgetTester tester, String tab) async {
    final document = switch (tab) {
      'timesheet' => ExportCelKind.timesheet,
      'envelope' => ExportCelKind.envelope,
      _ => null,
    };
    await tester.tap(
      find.byKey(
        ValueKey<String>('export-tab-${document == null ? tab : 'cels'}'),
      ),
    );
    await tester.pump();
    if (document == null) {
      return;
    }
    final state = tester.state<ExportDialogState>(find.byType(ExportDialog));
    for (final kind in ExportCelKind.values) {
      if (state.debugSpecs.cels.kinds.contains(kind) != (kind == document)) {
        await tester.tap(
          find.byKey(ValueKey<String>('export-cels-kind-${kind.jsonValue}')),
        );
        await tester.pump();
      }
    }
  }

  /// The preview [tab] shows in the face [family], its bytes — of
  /// [session], or of a fresh [exportSession].
  Future<List<int>> previewIn(
    WidgetTester tester, {
    required String tab,
    required String family,
    EditorSessionManager? session,
  }) async {
    await pumpDialog(
      tester,
      session ?? exportSession(),
      face: TextStyle(fontFamily: family),
      dialogKey: ValueKey<String>(
        'preview-$tab-$family-'
        '${AppText.settings.value.notationLanguage.name}-'
        '${session == null ? '' : identityHashCode(session)}',
      ),
    );
    await switchTab(tester, tab);
    await tester.settleExportPreview();
    final image = tester.exportPreviewImage!;
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    return bytes!.buffer.asUint8List().toList();
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

    testWidgets('Export is live with no place chosen ahead: the window '
        'holds no location field, and asks when it is pressed', (tester) async {
      var asked = 0;
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async {
          asked += 1;
          return temp.path;
        },
      );
      expect(exportEnabled(tester), isTrue);
      expect(asked, 0);
      for (final gone in [
        'export-location-label',
        'export-browse-button',
        'export-hand-over-button',
      ]) {
        expect(find.byKey(ValueKey<String>(gone)), findsNothing, reason: gone);
      }

      await tester.runAsync(state.export);
      await tester.pump();
      expect(asked, 1);
    });

    testWidgets('the preview covers the active cut by default: its frames '
        'under the transport, at the pixels they are written at', (
      tester,
    ) async {
      await pumpDialog(tester, exportSession());
      expect(tester.exportTransport.frameCount, 2);
      expect(tester.exportPreviewPageSize, const Size(32, 18));
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
      await pickStillPng(tester);
      await tester.runAsync(state.export);
      await tester.pump();

      expect(filesWrittenUnder(temp), ['frame_0001.png', 'frame_0002.png']);
      expect(statusText(tester), 'Exported 2 frames.');
    });

    testWidgets('naming module renames the base', (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
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

      expect(filesWrittenUnder(temp), ['shot_0001.png', 'shot_0002.png']);
    });

    testWidgets('IN trims the cut scope — and the stills are numbered '
        'through what is kept', (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await pickStillPng(tester);
      await tester.typeExportRange(inFrame: '2');
      expect(state.debugSpecs.sequence.inFrame, 1);
      expect(
        state.debugSpecs.sequence.outFrame,
        isNull,
        reason: 'an end left at its end of the axis is no trim',
      );
      await tester.runAsync(state.export);
      await tester.pump();
      expect(filesWrittenUnder(temp), ['frame_0001.png']);
    });

    testWidgets('IN and OUT cannot cross: the span that is kept is always '
        'one the export can run', (tester) async {
      final state = await pumpDialog(tester, exportSession());
      await pickStillPng(tester);
      await tester.typeExportRange(inFrame: '2');
      await tester.typeExportRange(outFrame: '1');
      final range = tester.exportTransport.range!;
      expect((range.inFrame, range.outFrame), (1, 1));
      expect(state.debugSpecs.sequence.inFrame, 1);
    });

    testWidgets(
        'project scope walks the active track in order and forces camera',
        (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await pickStillPng(tester);
      await tester.pickExportProjectScope();
      expect(
        find.byKey(const ValueKey<String>('export-size-canvas')),
        findsNothing,
      );
      await tester.runAsync(state.export);
      await tester.pump();

      expect(filesWrittenUnder(temp), [
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
      var heldInTheRun = 0;
      final fake = FakeFfmpegProcess(
        onFrame: (_) => heldInTheRun = ExportFrameRenderer.debugPicturesHeld,
      );
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
      await tester.runAsync(state.export);
      await tester.pump();

      // Raw, at the camera frame's own pixels: 32×18 of RGBA a frame.
      expect(fake.receivedFrameCount, 2);
      expect(fake.collectedStdin.length, 2 * 32 * 18 * 4);
      expect(capturedArgs, containsAllInOrder(['-video_size', '32x18']));
      expect(capturedArgs, contains('24'));
      // The pictures a run holds from one frame to the next are its own to
      // let go of.
      expect(heldInTheRun, greaterThan(0), reason: 'LIVENESS: it held some');
      expect(ExportFrameRenderer.debugPicturesHeld, 0);
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
      await tester.runAsync(state.export);
      await tester.pump();

      expect(filesWrittenUnder(temp), ['Project.png']);
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
      // The tab opens on video — one file, so the first module names a
      // file; the still format numbers them, and the same place holds the
      // rule they are named by.
      expect(find.text('이름 — Project.mp4'), findsNothing, reason: 'open');
      expect(find.text('이름'), findsOneWidget);
      expect(find.text('파일'), findsOneWidget);
      expect(find.text('프리셋 · 시퀀스'), findsOneWidget);
      expect(find.text('위치를 지정하고 출력합니다'), findsOneWidget);

      await pickStillPng(tester);
      expect(find.text('이름'), findsNothing);
      expect(find.textContaining('이름 규칙'), findsOneWidget);
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

      await tester.runAsync(state.export);
      await tester.pump();
      expect(statusText(tester), 'Project.png 내보냈습니다.');
    });

    testWidgets('a sheet page is counted with the files of its run', (
      tester,
    ) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'timesheet');
      await tester.runAsync(state.export);
      await tester.pump();
      expect(statusText(tester), '파일 1개 내보냈습니다.');
    });

    testWidgets('…and so are the digital sheets', (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'timesheet');
      await tester.tap(
        find.byKey(const ValueKey<String>('export-tsformat-xdts')),
      );
      await tester.pump();
      await tester.pickExportProjectScope();
      await tester.runAsync(state.export);
      await tester.pump();
      expect(statusText(tester), '파일 2개 내보냈습니다.');
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
      await tester.pickExportProjectScope();
      await tester.runAsync(state.export);
      await tester.pump();
      expect(
        statusText(tester),
        '2프레임 내보낸 뒤 취소했습니다(중간까지의 영상은 남겼습니다).',
      );
    });

    testWidgets('the render queue: its header, a job, the job states and the '
        'resting sentence', (tester) async {
      // Job 1 aims inside a FILE, so its write fails; job 2 lands.
      final blocker = File('${temp.path}/blocker')..createSync();
      final asked = ['${blocker.path}/nested', temp.path];
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => asked.removeAt(0),
      );
      await pickStillPng(tester);
      expect(find.text('렌더 대기열'), findsOneWidget);
      expect(find.text('모두 렌더'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('export-queue-add-button')),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('작업 1 · 시퀀스'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('export-queue-add-button')),
      );
      await tester.pump();
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
      expect(tester.exportFirstFileName, 'A1.png');

      await tester.runAsync(state.export);
      await tester.pump();
      // The fixture cels carry no strokes — renders resolve empty, files
      // skip, and the summary says so.
      expect(statusText(tester), contains('empty skipped'));
    });
  });

  group('the timesheet kind', () {
    testWidgets('by default a sheet is a PNG a page, named TS and its cut '
        'behind the kind\'s prefix', (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'timesheet');
      await tester.runAsync(state.export);
      await tester.pump();

      // The sheet is filed under the cut's NAME — its number, whatever the
      // user called it — not its position in the track (유저 2026-10-05:
      // 「타임시트는 기본적으로 파일이름 TS로서 출력. TS+컷번호 이런식」).
      expect(filesWrittenUnder(temp), ['_TSCut.png']);
      final bytes = File('${temp.path}/_TSCut.png').readAsBytesSync();
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      expect(statusText(tester), 'Exported 1 file.');
    });

    // export-sheet-lacks-transitions (2026-09-30): the panel printed an O.L
    // and the のりしろ it asks for; the export gathered the sheet's inputs
    // on its own and stopped short of both, so its sheet came out as if
    // there were none.
    testWidgets('an O.L across the cut\'s end prints on the exported sheet',
        (tester) async {
      Future<List<int>> sheetPrinted({required bool withOl}) {
        final session = exportSession();
        addTearDown(session.dispose);
        if (withOl) {
          session.transitions.updateTransitionInstructions({
            1: const InstructionEvent(instructionId: 'ol', length: 2),
          });
        }
        return previewIn(
          tester,
          tab: 'timesheet',
          family: 'BIZ UDPGothic',
          session: session,
        );
      }

      expect(
        await sheetPrinted(withOl: true),
        isNot(await sheetPrinted(withOl: false)),
      );
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
      await tester.runAsync(state.export);
      await tester.pump();

      final image = (await tester.runAsync(
        () => decodeImageFromList(
          File('${temp.path}/_TSCut.png').readAsBytesSync(),
        ),
      ))!;
      addTearDown(image.dispose);
      final data = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      // F-294 (유저 2026-10-05: 「1x하더라도 100%크기인채로 출력해야」): a
      // sheet is its paper's own pixels.
      expect((image.width, image.height), (1754, 2480));
      // The page ink's surface pixel (0, 0) sits on the page's corner, and a
      // pixel of the ink is a pixel of the paper.
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
      await tester.tap(
        find.byKey(const ValueKey<String>('export-tsformat-xdts')),
      );
      await tester.pump();
      await tester.pickExportProjectScope();
      await tester.runAsync(state.export);
      await tester.pump();

      expect(filesWrittenUnder(temp), ['_TSCut B.xdts', '_TSCut.xdts']);
      expect(statusText(tester), 'Exported 2 files.');
      final content = File('${temp.path}/_TSCut.xdts').readAsStringSync();
      expect(content, contains('exchangeDigitalTimeSheet'));
    });
  });

  group('preview & transport', () {
    testWidgets('the image tab exports the frame the transport stands on',
        (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'image');
      expect(state.debugImageFrame, 0);
      expect(tester.exportTransport.range, isNull, reason: 'one frame is written');
      await tester.tap(
        find.byKey(const ValueKey<String>('export-transport-step-forward')),
      );
      await tester.pump();
      expect(state.debugImageFrame, 1);
      expect(tester.exportTransport.currentFrame, 1);
      expect(tester.exportPreviewName, 'Project.png');

      await tester.runAsync(state.export);
      await tester.pump();
      expect(filesWrittenUnder(temp), ['Project.png']);
    });

    testWidgets('project scope: in/out trims by whole-track positions',
        (tester) async {
      final state = await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await pickStillPng(tester);
      await tester.pickExportProjectScope();
      await tester.typeExportRange(inFrame: '2', outFrame: '4');
      await tester.runAsync(state.export);
      await tester.pump();
      expect(filesWrittenUnder(temp), [
        'frame_0001.png',
        'frame_0002.png',
        'frame_0003.png',
      ]);
    });

    testWidgets('a press on the sequence\'s track moves the playhead — and '
        'the plate names the still that frame is', (tester) async {
      await pumpDialog(tester, exportSession());
      await pickStillPng(tester);
      expect(tester.exportPreviewName, 'frame_0001.png');
      final track = find.byKey(
        const ValueKey<String>('export-transport-track'),
      );
      final rect = tester.getRect(track);
      await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
      await tester.pump();
      expect(tester.exportTransport.currentFrame, 1);
      expect(tester.exportPreviewName, 'frame_0002.png');
      expect(tester.exportPreviewNameAbsent, isFalse);
    });

    testWidgets('a frame IN and OUT leave out is no file: the plate says '
        'which frame it is, in the ink of what is off — and the stills are '
        'numbered through the frames that are kept', (tester) async {
      await pumpDialog(tester, exportSession());
      await pickStillPng(tester);
      await tester.typeExportRange(inFrame: '2');

      expect(tester.exportTransport.currentFrame, 0);
      expect(tester.exportPreviewName, 'F1');
      expect(tester.exportPreviewNameAbsent, isTrue);

      await tester.seekExportPreview(1);
      expect(tester.exportPreviewName, 'frame_0001.png');
      expect(tester.exportPreviewNameAbsent, isFalse);
    });

    testWidgets('an OUT typed past the axis lands on the axis end — the '
        'span the export runs', (tester) async {
      final state = await pumpDialog(tester, exportSession());
      await tester.typeExportRange(inFrame: '1', outFrame: '9');

      final range = tester.exportTransport.range!;
      expect((range.inFrame, range.outFrame), (0, 1));
      expect(
        (state.debugSpecs.sequence.inFrame, state.debugSpecs.sequence.outFrame),
        (null, null),
        reason: 'both ends at their ends of the axis: no trim at all',
      );
      expect(tester.exportTransport.frameCount, 2);
    });

    testWidgets('a video is one file: the plate names it whatever frame is '
        'stood on', (tester) async {
      await pumpDialog(tester, exportSession());
      expect(tester.exportPreviewName, 'Project.mp4');
      await tester.seekExportPreview(1);
      expect(tester.exportPreviewName, 'Project.mp4');
    });

    testWidgets('the timesheet stands in the Cels list — its row, a block a '
        'page — and the preview is one picture, named as its file', (
      tester,
    ) async {
      await pumpDialog(tester, exportSession());
      await switchTab(tester, 'timesheet');
      expect(
        tester.exportTransportBar,
        findsNothing,
        reason: 'a cel is one picture: the list\'s band turns the pages',
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-page-strip')),
        findsNothing,
      );
      expect(tester.celsBoardRowIds, ['document-timesheet']);
      expect(tester.celsBoardBlocksOf('document-timesheet'), [('Cut', true)]);
      expect(tester.exportPreviewName, '_TSCut.png');
    });

    /// 🚨THE FILE-BAR PREVIEW AND THE PREVIEW'S PLATE ARE ONE ANSWER.
    ///
    /// They used to work out 「what comes out」 separately, and the copies had
    /// drifted: the preview printed a hardcoded `CUT1.xdts` for every
    /// project, whatever the cut was called (감사 2026-09-09). Nothing
    /// measured it — the whole branch could be deleted and the suite stayed
    /// green. This pins the NAME, so a second implementation cannot come
    /// back and lie again.
    testWidgets('the XDTS name reads the cut, and the preview\'s plate says '
        'the same thing', (tester) async {
      await pumpDialog(
        tester,
        exportSession(),
        exportDirectoryPicker: () async => temp.path,
      );
      await switchTab(tester, 'timesheet');
      await tester.tap(
        find.byKey(const ValueKey<String>('export-tsformat-xdts')),
      );
      await tester.pump();

      // The fixture's cut is named 'Cut', so the file is _TSCut.xdts — the
      // same name the run actually writes.
      expect(tester.exportFirstFileName, '_TSCut.xdts');
      expect(tester.exportPreviewName, '_TSCut.xdts');
    });

    testWidgets('the preview shows the rendered picture once it lands',
        (tester) async {
      await pumpDialog(tester, exportSession());
      await tester.settleExportPreview();
      final picture = tester.exportPreviewImage!;
      expect((picture.width, picture.height), (32, 18));
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
      final h264Chip = tester.widget<Pill>(
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
      await tester.tap(
        find.byKey(const ValueKey<String>('export-format-still-jpg')),
      );
      await tester.pump();
      await tester.runAsync(state.export);
      await tester.pump();
      expect(filesWrittenUnder(temp), ['frame_0001.jpg', 'frame_0002.jpg']);
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
      expect(tester.exportPreviewName, 'frame_0001.png');
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
  });

  group('the sheets export in the notation language (UI-R10 #7)', () {
    // What prints follows the NOTATION language — the timesheet's words from
    // the string tables since 2026-09-26, the conte's before them — and a
    // render handed the program's, or none, comes out the same both times.
    tearDown(() => AppText.settings.value = const AppLanguageSettings());

    for (final tab in ['timesheet', 'conte']) {
      testWidgets('$tab: the preview', (tester) async {
        await loadTheAppFaces();
        Future<List<int>> printedIn(AppLanguage notation) {
          AppText.settings.value = AppLanguageSettings(
            notationLanguage: notation,
          );
          return previewIn(tester, tab: tab, family: 'BIZ UDPGothic');
        }

        expect(
          await printedIn(AppLanguage.ja),
          isNot(await printedIn(AppLanguage.ko)),
        );
      });
    }
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
      await tester.runAsync(state.export);
      await tester.pump();
      return {
        for (final name in filesWrittenUnder(folder))
          name: File('${folder.path}/$name').readAsBytesSync(),
      };
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
