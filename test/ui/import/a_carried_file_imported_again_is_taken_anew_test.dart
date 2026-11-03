import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart'
    show createDefaultCut;
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/import_destination.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/reference_swap.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart'
    show bitmapSurfaceRegionPixels;
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/project_lookup.dart' show requireCut;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/import/import_preview.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/model_vocabulary.dart' show partsOf;
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/fake_video_backend.dart';
import '../../helpers/import_warnings.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/three_frame_gif.dart';
import '../../helpers/wait_window.dart';

/// 🗣️F-550-Q3 (유저 2026-11-04: 「새로 받는다」): a file the pool carries,
/// imported again, is taken as it is now — 「그 경로의 항목을 고른 파일의
/// 지금 데이터로 새로 품는다(되돌리기 한 번). 타임라인에 놓인 것도 새 데이터를
/// 쓴다. 미리보기는 고른 파일을 보인다」.
///
/// FU's 265.mp3 had become 301-312's sound (F-550-Q2), and the user imported
/// the file again to mend it: the window showed the pool's bytes, and the
/// press kept them.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-anew');
  });
  tearDown(() => deleteTempQuietly(tempDir));

  // The window's pixel-size column shows on a timer, which a frame without a
  // step never reaches.
  Future<bool> settle(WidgetTester tester, bool Function() until) =>
      settleAsync(tester, until, step: const Duration(milliseconds: 50));

  const red = 0xFF0000FF;
  const blue = 0x0000FFFF;
  const redPixel = [0xFF, 0, 0, 0xFF];
  const bluePixel = [0, 0, 0xFF, 0xFF];

  /// The RGBA in the middle of the canvas on the cel of [row], of the cut
  /// [cutId].
  List<int> middleOf(EditorSessionManager session, CutId cutId, LayerId row) {
    final cut = requireCut(session.repository.requireProject(), cutId);
    final layer = cut.layers.firstWhere((layer) => layer.id == row);
    final cel = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cut, row, layer.frames.single.id),
    )!;
    return bitmapSurfaceRegionPixels(
      cel,
      DirtyRegion.fromXYWH(
        x: cut.canvasSize.width ~/ 2,
        y: cut.canvasSize.height ~/ 2,
        width: 1,
        height: 1,
      ),
    );
  }

  /// `bg.png` — red, 8×8 — placed CARRIED as a reference row of the open
  /// cut; then the file on disk becomes [nowRgba] at [nowSide]×[nowSide].
  Future<({String path, LayerId row})> placeCarried(
    WidgetTester tester,
    EditorSessionManager session, {
    int nowRgba = blue,
    int nowSide = 16,
  }) async {
    final path = normalizedMediaPath(
      (await tester.runAsync(() => writeSolidPng(tempDir, 'bg.png', rgba: red)))!,
    );
    expect(
      await tester.runAsync(
        () => session.importDoors.importImageFile(
          path: path,
          destination: ImportDestination.activeCutLayer,
          copyIntoProject: true,
        ),
      ),
      isTrue,
      reason: 'premise: the row is placed',
    );
    final row = session.requireActiveCut.layers
        .firstWhere((layer) => layer.mediaReference?.assetPath == path)
        .id;
    await tester.runAsync(
      () => writeSolidPng(
        tempDir,
        'bg.png',
        rgba: nowRgba,
        width: nowSide,
        height: nowSide,
      ),
    );
    return (path: path, row: row);
  }

  group('the pool', () {
    testWidgets('a carried file is carried anew from what it holds now — '
        'under a carry of its own, one undo from the one before', (
      tester,
    ) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final (:path, row: _) = await placeCarried(tester, session);
      final before = carryIn(session, path);
      final held = session.projectFile.mediaByteSourceFor(path).readSync();
      expect(held, isNot(File(path).readAsBytesSync()), reason: 'premise');

      final anew = await tester.runAsync(
        () => session.mediaPool.carryAnew([path]),
      );

      expect(anew, {path});
      expect(carryIn(session, path), isNot(before));
      expect(
        session.projectFile.mediaByteSourceFor(path).readSync(),
        File(path).readAsBytesSync(),
      );
      expect(stagedCopyIn(session, path), isNotNull, reason: 'held, not read');
      expect(
        session.repository.requireProject().mediaAssetByPath(path)!.identity,
        isNot(isNull),
      );
      session.historyManager.undo();
      expect(carryIn(session, path), before);
      expect(session.projectFile.mediaByteSourceFor(path).readSync(), held);
    });

    testWidgets('a file the pool points at, and a carried one whose file is '
        'gone, are left as they are — no step is spent', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final paths = (await tester.runAsync(() async {
        final linked = await writeSolidPng(tempDir, 'linked.png');
        final gone = await writeSolidPng(tempDir, 'gone.png');
        return [normalizedMediaPath(linked), normalizedMediaPath(gone)];
      }))!;
      await tester.runAsync(() async {
        await session.mediaPool.importMediaFiles(
          [paths[0]],
          copyIntoProject: false,
        );
        await session.mediaPool.importMediaFiles(
          [paths[1]],
          copyIntoProject: true,
        );
        await File(paths[1]).delete();
      });
      final pool = session.repository.requireProject().mediaAssets;
      final steps = session.historyManager.undoCount;

      final anew = await tester.runAsync(
        () => session.mediaPool.carryAnew(paths),
      );

      expect(anew, isEmpty);
      expect(session.repository.requireProject().mediaAssets, pool);
      expect(session.historyManager.undoCount, steps);
    });
  });

  group('the rows that show it', () {
    testWidgets('a still row is drawn from the file carried anew — in a cut '
        'that is not open too', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final first = session.requireActiveCut;
      final (:path, :row) = await placeCarried(tester, session);
      final second = createDefaultCut(
        cutId: const CutId('anew-second-cut'),
        name: '2',
        layerId: const LayerId('anew-second-cut-layer'),
        canvasSize: first.canvasSize,
      );
      session.repository.insertCut(trackId: session.activeTrack.id, cut: second);
      session.selectCut(second.id);
      expect(middleOf(session, first.id, row), redPixel, reason: 'premise');

      final undrawn = await tester.runAsync(() async {
        final anew = await session.mediaPool.carryAnew([path]);
        return session.importDoors.drawAgainFrom(anew);
      });

      expect(undrawn, isEmpty);
      expect(middleOf(session, first.id, row), bluePixel);
      expect(
        requireCut(session.repository.requireProject(), first.id).layers
            .firstWhere((layer) => layer.id == row)
            .mediaReference!
            .pictureSize,
        const CanvasSize(width: 16, height: 16),
        reason: 'the size of the picture it holds now',
      );
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('a movie row says the size of the movie carried anew', (
      tester,
    ) async {
      debugVideoDecodeBackend = FakeVideoBackend(width: 1280, height: 720);
      addTearDown(() => debugVideoDecodeBackend = null);
      final path = normalizedMediaPath('${tempDir.path}/take.mp4');
      await tester.runAsync(() => File(path).writeAsBytes([1, 2, 3, 4]));
      const takeRow = LayerId('take-row');
      final shown = MediaReference(
        assetPath: path,
        frameOffset: 3,
        pose: TransformPose(
          center: CanvasPoint(x: 700, y: 500),
          scaleX: 1.5,
          scaleY: 1.5,
        ),
        pictureSize: const CanvasSize(width: 640, height: 360),
      );
      final session = EditorSessionManager(
        initialProject: createDefaultProject().copyWith(
          mediaAssets: [
            MediaAsset(
              path: path,
              name: mediaAssetDefaultName(path),
              kind: MediaAssetKind.video,
              carriedAs: mintMediaCarry(path),
            ),
          ],
        ),
      );
      addTearDown(session.dispose);
      session.repository.insertLayer(
        cutId: session.requireActiveCut.id,
        layer: Layer(
          id: takeRow,
          name: 'take',
          frames: [
            Frame(id: const FrameId('take-cel'), duration: 1, strokes: const []),
          ],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('take-cel'), length: 6),
          },
          mediaReference: shown,
        ),
      );

      final undrawn = await tester.runAsync(() async {
        final anew = await session.mediaPool.carryAnew([path]);
        return session.importDoors.drawAgainFrom(anew);
      });

      expect(undrawn, isEmpty);
      expect(
        session.layerById(takeRow)!.mediaReference,
        shown.copyWith(pictureSize: const CanvasSize(width: 1280, height: 720)),
        reason: 'the same path, another movie — its own frame',
      );
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('a PDF row is drawn from the pages carried anew', (
      tester,
    ) async {
      // The document the bytes are: four of them before, eight after.
      PdfRenderService.debugOpenerOverride = (source) async => FakePdfDocument(
        pageSizes: [
          if (source.lengthSync() == 4)
            const ui.Size(100, 50)
          else
            const ui.Size(50, 100),
        ],
      );
      addTearDown(PdfRenderService.debugResetForTests);
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final path = normalizedMediaPath('${tempDir.path}/conte.pdf');
      await tester.runAsync(() async {
        await File(path).writeAsBytes([1, 2, 3, 4]);
        expect(
          await session.importDoors.importPdfFile(
            path: path,
            destination: ImportDestination.activeCutLayer,
            copyIntoProject: true,
          ),
          isTrue,
          reason: 'premise: the row is placed',
        );
        await File(path).writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);
      });
      Layer row() => session.requireActiveCut.layers.firstWhere(
        (layer) => layer.mediaReference?.assetPath == path,
      );
      expect(
        row().mediaReference!.pictureSize,
        const CanvasSize(width: 100, height: 50),
        reason: 'premise',
      );

      final undrawn = await tester.runAsync(() async {
        final anew = await session.mediaPool.carryAnew([path]);
        return session.importDoors.drawAgainFrom(anew);
      });

      expect(undrawn, isEmpty);
      expect(
        row().mediaReference!.pictureSize,
        const CanvasSize(width: 50, height: 100),
      );
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('a row the file carried anew does not draw keeps what it '
        'showed, and says why', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final (:path, :row) = await placeCarried(tester, session);
      await tester.runAsync(() => File(path).writeAsBytes([1, 2, 3, 4]));
      final cutId = session.requireActiveCut.id;

      final undrawn = await tester.runAsync(() async {
        final anew = await session.mediaPool.carryAnew([path]);
        return session.importDoors.drawAgainFrom(anew);
      });

      expect(undrawn, {path: isA<ReferenceUnreadable>()});
      expect(middleOf(session, cutId, row), redPixel);
    });
  });

  group('the import window', () {
    /// The window on [session], handed [picked] by its door — or, with
    /// [fromThePool], [path] as a pool row places it.
    Future<void> openWindow(
      WidgetTester tester,
      EditorSessionManager session,
      String path, {
      bool fromThePool = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: fromThePool
                ? ImportDialog(
                    session: session,
                    initialPaths: [path],
                    placeOnly: true,
                  )
                : ImportDialog(
                    session: session,
                    picked: [
                      FolderGrant.granted(path: path, kind: GrantKind.file),
                    ],
                  ),
          ),
        ),
      );
      await tester.pump();
    }

    String resolutionOf(WidgetTester tester, String path) => tester
        .widget<Text>(find.byKey(ValueKey<String>('import-resolution-$path')))
        .data!;

    Future<void> pressImport(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      await pumpPastTheWaitWindow(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('🗣️a carried file picked again: the window shows the FILE, '
        'and the press takes it — the pool and the row placed from it are '
        'its picture now, ONE undo from the old', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final (:path, :row) = await placeCarried(tester, session);
      final cutId = session.requireActiveCut.id;
      final before = carryIn(session, path);

      await openWindow(tester, session, path);
      await settle(tester, () => resolutionOf(tester, path) != '');
      expect(
        resolutionOf(tester, path),
        '16×16',
        reason: 'the file as it is, not the 8×8 the pool holds',
      );
      await pressImport(tester);

      expect(carryIn(session, path), isNot(before));
      expect(
        session.projectFile.mediaByteSourceFor(path).readSync(),
        File(path).readAsBytesSync(),
      );
      expect(middleOf(session, cutId, row), bluePixel);
      expect(importWarningsButton, findsNothing);

      session.undo();
      await tester.pump(Duration.zero);
      expect(carryIn(session, path), before);
      expect(middleOf(session, cutId, row), redPixel);
      session.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('a pool row placed is the pool\'s: shown and placed as the '
        'pool holds it, and nothing is carried anew (유저 09-11 「풀에서 '
        '가져올때는 가 로」)', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final (:path, :row) = await placeCarried(tester, session);
      final cutId = session.requireActiveCut.id;
      final before = carryIn(session, path);

      await openWindow(tester, session, path, fromThePool: true);
      await settle(tester, () => resolutionOf(tester, path) != '');
      expect(resolutionOf(tester, path), '8×8');
      await pressImport(tester);

      expect(carryIn(session, path), before);
      expect(middleOf(session, cutId, row), redPixel);
      session.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('a carried SOUND picked again: the preview plays the file, '
        'and after the press the timeline\'s conform is of the new bytes', (
      tester,
    ) async {
      late EditorSessionManager session;
      // A second for every thousand bytes the conform is OF.
      final conforms = soundConformStore(
        secondsOf: (request) => request.effectiveSource.lengthSync() / 1000,
        resolveByteSource: (path) =>
            session.projectFile.mediaByteSourceFor(path),
        resolveCarry: (path) => session.projectFile.mediaCarryFor(path),
      );
      session = EditorSessionManager(
        initialProject: createDefaultProject(),
        audioConformStore: conforms,
      );
      addTearDown(session.dispose);
      final path = normalizedMediaPath('${tempDir.path}/door.wav');
      await tester.runAsync(() async {
        await File(path).writeAsBytes(List<int>.filled(1000, 1));
        await session.mediaPool.importMediaFiles([path], copyIntoProject: true);
        await File(path).writeAsBytes(List<int>.filled(3000, 1));
      });
      int framesOf(double seconds) => AudioPeaks(
        bucketsPerSecond: 100,
        peaks: Float32List((100 * seconds).round()),
      ).durationFrames(session.projectSettings.projectFrameRate);
      TransportBar bar() =>
          tester.widget<TransportBar>(find.byType(TransportBar));

      await openWindow(tester, session, path);
      await settleAsync(tester, () => bar().frameCount != 1);
      expect(bar().frameCount, framesOf(3), reason: 'the file, not the pool');
      final heard = tester
          .widget<ImportPreview>(find.byType(ImportPreview))
          .sound
          ?.conformStore;
      expect(
        heard
            ?.peaksFor(path)
            ?.durationFrames(session.projectSettings.projectFrameRate),
        framesOf(3),
        reason: 'what plays is the file too, not the pool\'s copy',
      );

      await pressImport(tester);
      final peaks = await tester.runAsync(
        () => session.audioConformStore.ensurePeaksFor(path),
      );
      expect(peaks!.durationFrames(session.projectSettings.projectFrameRate),
          framesOf(3));
      session.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('a row the file carried anew lacks a picture for is said in '
        'the warnings, as a file let go on it would be', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      // A row of the GIF's 3rd picture — then the file is a still.
      final path = normalizedMediaPath(
        (await tester.runAsync(() => writeThreeFrameGif(tempDir, 'clip.gif')))!,
      );
      await tester.runAsync(
        () => session.importDoors.importImageFile(
          path: path,
          destination: ImportDestination.activeCutLayer,
          copyIntoProject: true,
          inFrame: 2,
          outFrame: 2,
        ),
      );
      await tester.runAsync(() => writeSolidPng(tempDir, 'clip.gif'));

      await openWindow(tester, session, path);
      await pressImport(tester);

      expect(importWarningsButton, findsOneWidget);
      final notice = await openImportWarnings(tester);
      final name = session.repository.requireProject().shownNameOfMedia(path);
      final (:about, :says) = partsOf(
        AppText.strings.imLacksPicture(name, 3),
        about: name,
      );
      // The sentence heads the files it was said of, counted.
      for (final words in [about!, '$says (1)']) {
        expect(
          find.descendant(of: notice, matching: find.text(words)),
          findsOneWidget,
          reason: words,
        );
      }
      session.playbackRig.prerenderScheduler.cancel();
    });
  });

  testWidgets('an open viewer shows the file carried anew — and the one '
      'before again, undone', (tester) async {
    // The document the bytes are: four pages before, two after.
    PdfRenderService.debugOpenerOverride = (source) async => FakePdfDocument(
      pageSizes: List<ui.Size>.filled(
        source.lengthSync() == 4 ? 4 : 2,
        const ui.Size(595, 842),
      ),
    );
    addTearDown(PdfRenderService.debugResetForTests);
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final slot = MediaViewerSlot();
    addTearDown(slot.dispose);
    final path = normalizedMediaPath('${tempDir.path}/conte.pdf');
    await tester.runAsync(() async {
      await File(path).writeAsBytes([1, 2, 3, 4]);
      await session.mediaPool.importMediaFiles([path], copyIntoProject: true);
      await File(path).writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: slot.position,
            builder: (context, position, _) => MediaViewerTabHost(
              viewerId: 'media-viewer',
              session: session,
              request: slot.request,
              position: slot.position,
            ),
          ),
        ),
      ),
    );
    slot.request.value = MediaViewerRequest(
      path: path,
      kind: MediaAssetKind.pdf,
    );
    await settle(tester, () => tester.any(find.text('1 / 4')));

    await tester.runAsync(() => session.mediaPool.carryAnew([path]));
    expect(await settle(tester, () => tester.any(find.text('1 / 2'))),
        isTrue);

    session.undo();
    expect(await settle(tester, () => tester.any(find.text('1 / 4'))),
        isTrue);
  });
}
