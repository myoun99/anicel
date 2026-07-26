import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/controllers/default_cut_helpers.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/cut.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/export_spec.dart';
import 'package:quick_animaker_v2/src/models/frame.dart';
import 'package:quick_animaker_v2/src/models/frame_id.dart';
import 'package:quick_animaker_v2/src/models/layer.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/project.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/native/qa_engine_abi.dart';
import 'package:quick_animaker_v2/src/native/qa_image_encoder.dart';
import 'package:quick_animaker_v2/src/services/persistence/app_export_settings.dart';
import 'package:quick_animaker_v2/src/services/persistence/app_export_settings_store.dart';
import 'package:quick_animaker_v2/src/ui/editor_session_manager.dart';
import 'package:quick_animaker_v2/src/ui/export/export_dialog.dart';
import 'package:quick_animaker_v2/src/ui/export/export_format_availability.dart';
import 'package:quick_animaker_v2/src/ui/export/export_settings_modules.dart';
import 'package:quick_animaker_v2/src/ui/export/video_export_service.dart';

import '../../helpers/native_engine_path.dart';
import 'fake_ffmpeg_process.dart';

void main() {
  late Directory temp;

  setUp(() {
    AppExport.settings.value = AppExportSettings();
    temp = Directory.systemTemp.createTempSync('qa-export-dialog');
  });

  tearDown(() {
    AppExport.settings.value = AppExportSettings();
    try {
      temp.deleteSync(recursive: true);
    } on Object {
      // Windows may hold a handle a beat; leaking a temp dir beats failing.
    }
  });

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

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
  }) async {
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Unmount at teardown: the dialog's dispose cancels the preview
    // debounce timer — otherwise every test ends with a pending Timer.
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
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
      expect(session.exportAnchorIsFallback, isTrue);

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
        find.ancestor(of: h265, matching: find.byType(Tooltip)),
        findsOneWidget,
        reason: 'a grayed chip explains itself',
      );
      // The tap is a no-op on a grayed chip — H.264 stays selected.
      await tester.tap(h265);
      await tester.pump();
      final h264Chip = tester.widget<ExportChip>(
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
  });
}
