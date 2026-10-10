// A REFERENCE STANDS WHERE ITS REFERENCE FX SAYS (I-68). 🗣️유저 2026-10-04:
// 「처음에 용지 세팅하고나서 오른쪽으로 캔버스 크기 늘리고나서, 용지
// 스위칭하려고 배치하면 캔버스 중앙에 배치되는데 … 구조적,근본적인 해결」;
// 10-10: 「담는값은 변형도구랑 같은거 공유 … 해상도가 달라도 같은크기로
// 겹치지않게 … 배치된 값, 원본값 유지」 · 캔버스 크기 변경 「가」(기준점대로).
//
// The pose a placement starts a file's picture at is the reference's own:
// the canvas growing afterwards moves it with the drawings, a file swapped
// in stands at it over ITS pixels, moving it lays the file again — and a
// movie, decoded as it is shown, stands there too.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// Where [surface]'s ink lies on the canvas, or null when it holds none.
ui.Rect? inkOf(BitmapSurface? surface) {
  if (surface == null) {
    return null;
  }
  final box = bitmapSurfaceContentBounds(surface);
  return box == null
      ? null
      : ui.Rect.fromLTRB(
          box.left.toDouble(),
          box.top.toDouble(),
          box.rightExclusive.toDouble(),
          box.bottomExclusive.toDouble(),
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a fit is where a pose STARTS', () {
    const picture = CanvasSize(width: 200, height: 100);
    const canvas = CanvasSize(width: 400, height: 400);

    ui.Rect laid(MediaFitMode fit) {
      final placement = picturePlacement(
        fitPose(picture: picture, canvas: canvas, fit: fit),
        picture,
      );
      final topLeft = placement.apply(CanvasPoint(x: 0, y: 0));
      final bottomRight = placement.apply(CanvasPoint(x: 200, y: 100));
      return ui.Rect.fromLTRB(
        topLeft.x,
        topLeft.y,
        bottomRight.x,
        bottomRight.y,
      );
    }

    test('contain letterboxes, stretch fills, none is 1:1 — each centred',
        () {
      expect(
        laid(MediaFitMode.contain),
        const ui.Rect.fromLTRB(0, 100, 400, 300),
      );
      expect(
        laid(MediaFitMode.stretch),
        const ui.Rect.fromLTRB(0, 0, 400, 400),
      );
      expect(
        laid(MediaFitMode.none),
        const ui.Rect.fromLTRB(100, 150, 300, 250),
      );
    });

    test('a picture with no pixels stands 1:1 — it has no size to fit', () {
      expect(
        fitPose(
          picture: const CanvasSize(width: 0, height: 10),
          canvas: canvas,
          fit: MediaFitMode.stretch,
        ),
        TransformPose(center: CanvasPoint(x: 200, y: 200)),
      );
    });
  });

  group('a paper', () {
    late Directory tempDir;
    late String red;
    late String blue;
    late String blueTwice;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anicel-i68-paper');
    });

    tearDown(() => deleteTempQuietly(tempDir));

    /// A session with a red 100×60 paper placed 1:1 as a reference on the
    /// default 2340×1654 canvas — its middle at (1170, 827).
    Future<(EditorSessionManager, Layer)> placed(WidgetTester tester) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.playbackRig.prerenderScheduler.beginInputHold();
      await tester.runAsync(() async {
        red = await writeSolidPng(
          tempDir,
          'red.png',
          width: 100,
          height: 60,
          rgba: 0xFF0000FF,
        );
        blue = await writeSolidPng(
          tempDir,
          'blue.png',
          width: 100,
          height: 60,
          rgba: 0x0000FFFF,
        );
        blueTwice = await writeSolidPng(
          tempDir,
          'blue2x.png',
          width: 200,
          height: 120,
          rgba: 0x0000FFFF,
        );
        expect(
          await s.importDoors.importImageFile(
            path: red,
            destination: ImportDestination.activeCutLayer,
            copyIntoProject: false,
            fit: MediaFitMode.none,
          ),
          isTrue,
        );
      });
      final row = s.requireActiveCut.layers.firstWhere(
        (layer) => layer.mediaReference != null,
      );
      return (s, row);
    }

    ui.Rect? shown(EditorSessionManager s, Layer row) {
      final cut = s.requireActiveCut;
      return inkOf(
        s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
          s.brushFrameKeyForCut(cut, row.id, row.frames.single.id),
        ),
      );
    }

    Layer rowOf(EditorSessionManager s, Layer row) => s.layerById(row.id)!;

    testWidgets('🎯the canvas grows to the right, and a paper swapped in '
        'afterwards stands where the first one stood — not in the middle of '
        'the canvas it grew to', (tester) async {
      final (s, row) = await placed(tester);
      expect(shown(s, row), const ui.Rect.fromLTRB(1120, 797, 1220, 857));

      s.cutVerbs.resizeActiveCutCanvas(
        const CanvasSize(width: 2940, height: 1654),
        anchor: CanvasResizeAnchor.centerLeft,
      );
      expect(
        rowOf(s, row).mediaReference!.pose.center,
        CanvasPoint(x: 1170, y: 827),
        reason: 'pinned left: the paper did not move',
      );

      expect(
        await tester.runAsync(
          () => s.importDoors.swapReference(layerId: row.id, path: blue),
        ),
        isTrue,
      );
      expect(
        shown(s, row),
        const ui.Rect.fromLTRB(1120, 797, 1220, 857),
        reason: 'where red stood — the canvas\'s new middle is x 1470',
      );
    });

    testWidgets('grown to the LEFT, the paper moves with the drawings — and '
        'the one swapped in afterwards stands where it moved to',
        (tester) async {
      final (s, row) = await placed(tester);

      s.cutVerbs.resizeActiveCutCanvas(
        const CanvasSize(width: 2940, height: 1654),
        anchor: CanvasResizeAnchor.centerRight,
      );
      expect(shown(s, row), const ui.Rect.fromLTRB(1720, 797, 1820, 857));
      expect(
        rowOf(s, row).mediaReference!.pose.center,
        CanvasPoint(x: 1770, y: 827),
        reason: 'the content offset (600), not the canvas middle\'s (300)',
      );

      await tester.runAsync(
        () => s.importDoors.swapReference(layerId: row.id, path: blue),
      );
      expect(shown(s, row), const ui.Rect.fromLTRB(1720, 797, 1820, 857));
    });

    testWidgets('a paper of another resolution stands at ITS size — the same '
        'pose over its own pixels, not fitted to the old one\'s rect',
        (tester) async {
      final (s, row) = await placed(tester);

      await tester.runAsync(
        () => s.importDoors.swapReference(layerId: row.id, path: blueTwice),
      );

      expect(shown(s, row), const ui.Rect.fromLTRB(1070, 767, 1270, 887));
      expect(
        rowOf(s, row).mediaReference!.pictureSize,
        const CanvasSize(width: 200, height: 120),
        reason: 'the size the row shows is the new file\'s',
      );
    });

    testWidgets('moving the reference fx lays the file again where it now '
        'stands — and ONE undo puts both back', (tester) async {
      final (s, row) = await placed(tester);
      final moved = rowOf(s, row).mediaReference!.pose.copyWith(
        center: CanvasPoint(x: 1210, y: 827),
        scaleX: 2,
        scaleY: 2,
      );

      expect(
        await tester.runAsync(
          () => s.importDoors.reposeReference(layerId: row.id, pose: moved),
        ),
        isTrue,
      );
      expect(rowOf(s, row).mediaReference!.pose, moved);
      expect(shown(s, row), const ui.Rect.fromLTRB(1110, 767, 1310, 887));

      s.undo();
      expect(
        rowOf(s, row).mediaReference!.pose,
        TransformPose(center: CanvasPoint(x: 1170, y: 827)),
      );
      expect(shown(s, row), const ui.Rect.fromLTRB(1120, 797, 1220, 857));
      // The undo's own settling timers, run out on the test's clock — and
      // the warmer they woke stopped after them, or it waits on past the
      // body.
      await tester.pump(const Duration(minutes: 1));
      s.playbackRig.prerenderScheduler.cancel();
      await tester.pump();
    });

    testWidgets('the pose it already stands at changes nothing', (
      tester,
    ) async {
      final (s, row) = await placed(tester);
      final canUndo = s.canUndo;

      expect(
        await tester.runAsync(
          () => s.importDoors.reposeReference(
            layerId: row.id,
            pose: rowOf(s, row).mediaReference!.pose,
          ),
        ),
        isFalse,
      );
      expect(s.canUndo, canUndo);
    });
  });

  group('a movie', () {
    late Directory tempDir;
    late String moviePath;
    late String otherPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anicel-i68-movie');
      moviePath = '${tempDir.path}${Platform.pathSeparator}take3.mov';
      otherPath = '${tempDir.path}${Platform.pathSeparator}take4.mov';
      await File(moviePath).writeAsBytes(const [0, 0, 0, 24]);
      await File(otherPath).writeAsBytes(const [0, 0, 0, 24]);
    });

    tearDown(() async {
      debugVideoDecodeBackend = null;
      deleteTempQuietly(tempDir);
    });

    /// A 64×36 take placed 1:1 as a reference on the default canvas, the
    /// warmer held so what is decoded is the test's asking.
    Future<(EditorSessionManager, Layer, FakeVideoBackend)> placed(
      WidgetTester tester,
    ) async {
      final fake = FakeVideoBackend(frameCount: 24);
      debugVideoDecodeBackend = fake;
      final s = EditorSessionManager(
        initialProject: createDefaultProject(),
        audioConformStore: soundConformStore(),
      );
      addTearDown(s.dispose);
      s.playbackRig.prerenderScheduler.beginInputHold();
      await tester.runAsync(
        () => s.importDoors.importVideoFile(
          path: moviePath,
          settings: const ImportFileSettings(
            mode: ImportFileMode.reference,
            movieParts: MovieParts.picture,
            fit: MediaFitMode.none,
          ),
        ),
      );
      return (s, s.requireActiveCut.layers.firstWhere(isMovieReference), fake);
    }

    Future<ui.Rect?> shownAt(
      WidgetTester tester,
      EditorSessionManager s,
      Layer row,
    ) async {
      await tester.runAsync(
        () => s.movieCels
            .hydrate(s.requireActiveCut, 0)
            .timeout(const Duration(seconds: 30)),
      );
      final layer = s.layerById(row.id)!;
      return inkOf(
        s.renderCaches.brushSurfaceForLayerFrame(
          layer,
          resolveExposedFrameAt(layer, 0)!,
        ),
      );
    }

    testWidgets('🎯the canvas grows, and the movie stays among the drawings '
        '— it is not fitted to the middle of the new canvas at the next '
        'decode', (tester) async {
      final (s, row, _) = await placed(tester);
      expect(
        await shownAt(tester, s, row),
        const ui.Rect.fromLTRB(1138, 809, 1202, 845),
      );

      // On the real clock: the session asks for the frame it shows as the
      // edit lands, and a decode begun on the test's clock never ends.
      await tester.runAsync(() async {
        s.cutVerbs.resizeActiveCutCanvas(
          const CanvasSize(width: 2940, height: 1654),
          anchor: CanvasResizeAnchor.centerLeft,
        );
      });

      expect(
        await shownAt(tester, s, row),
        const ui.Rect.fromLTRB(1138, 809, 1202, 845),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a canvas that keeps its size but moves the picture moves '
        'the movie too — decoded again where it stands now', (tester) async {
      final (s, row, _) = await placed(tester);
      await shownAt(tester, s, row);

      await tester.runAsync(() async {
        s.cutVerbs.placeActiveCutCanvas(
          const CanvasSize(width: 2340, height: 1654),
          contentOffset: (dx: 100, dy: -50),
        );
      });

      expect(
        await shownAt(tester, s, row),
        const ui.Rect.fromLTRB(1238, 759, 1302, 795),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('moving its reference fx decodes it again where it stands',
        (tester) async {
      final (s, row, fake) = await placed(tester);
      await shownAt(tester, s, row);
      final asked = fake.asked.length;

      await tester.runAsync(
        () => s.importDoors.reposeReference(
          layerId: row.id,
          pose: TransformPose(center: CanvasPoint(x: 200, y: 100)),
        ),
      );

      expect(
        await shownAt(tester, s, row),
        const ui.Rect.fromLTRB(168, 82, 232, 118),
      );
      expect(fake.asked.length, greaterThan(asked));
      // Where the installed picture was laid — what the editing canvas
      // moves it from while a move's own picture is decoded.
      final layer = s.layerById(row.id)!;
      expect(
        s.movieCels.laidAt(
          s.brushFrameKeyForCut(
            s.requireActiveCut,
            row.id,
            resolveExposedFrameAt(layer, 0)!.id,
          ),
        ),
        TransformPose(center: CanvasPoint(x: 200, y: 100)),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a movie swapped in is the one decoded — the cel keeps its '
        'key, and a picture of the other movie is not what it shows',
        (tester) async {
      final (s, row, fake) = await placed(tester);
      await shownAt(tester, s, row);

      expect(
        await tester.runAsync(
          () => s.importDoors.swapReference(layerId: row.id, path: otherPath),
        ),
        isTrue,
      );
      final asked = fake.asked.length;
      await shownAt(tester, s, row);

      expect(
        fake.openedAt.map((opened) => opened.path),
        contains(normalizedMediaPath(otherPath)),
      );
      expect(
        fake.asked.length,
        greaterThan(asked),
        reason: 'the frame is decoded from the movie the row shows now',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('rasterizing bakes the frames where the reference stands',
        (tester) async {
      final (s, row, _) = await placed(tester);
      await tester.runAsync(
        () => s.importDoors.reposeReference(
          layerId: row.id,
          pose: TransformPose(center: CanvasPoint(x: 200, y: 100)),
        ),
      );

      await tester.runAsync(
        () => s.importDoors.rasterizeMovieReference(
          cutId: s.requireActiveCut.id,
          layerId: row.id,
        ),
      );

      final baked = s.layerById(row.id)!;
      expect(baked.mediaReference, isNull);
      expect(
        inkOf(
          s.renderCaches.brushSurfaceForLayerFrame(baked, baked.frames.first),
        ),
        const ui.Rect.fromLTRB(168, 82, 232, 118),
      );
      await tester.pumpAndSettle();
    });
  });

  group('a PDF\'s pages', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anicel-i68-pdf');
    });

    tearDown(() {
      PdfRenderService.debugResetForTests();
      deleteTempQuietly(tempDir);
    });

    testWidgets('🎯every page of a reference stands at ITS pose over the '
        'page\'s own size — a bigger page stands bigger, not fitted again — '
        'and each is rendered once at the size it stands at', (tester) async {
      final pdf = FakePdfDocument(
        pageSizes: const [ui.Size(100, 50), ui.Size(200, 100)],
      );
      PdfRenderService.debugOpenerOverride = (_) async => pdf;
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.playbackRig.prerenderScheduler.beginInputHold();

      await tester.runAsync(() async {
        // A 200×100 canvas: the first page fits it at twice its size.
        s.cutVerbs.resizeActiveCutCanvas(
          const CanvasSize(width: 200, height: 100),
        );
        final path = '${tempDir.path}${Platform.pathSeparator}conte.pdf';
        await File(path).writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
        expect(
          await s.importDoors.importPdfFile(
            path: path,
            destination: ImportDestination.activeCutLayer,
            copyIntoProject: false,
          ),
          isTrue,
        );
      });

      final cut = s.requireActiveCut;
      final row = cut.layers.firstWhere(
        (layer) => layer.mediaReference != null,
      );
      expect(
        row.mediaReference!.pose,
        TransformPose.uniform(center: CanvasPoint(x: 100, y: 50), zoom: 2),
      );
      expect(
        row.mediaReference!.pictureSize,
        const CanvasSize(width: 100, height: 50),
      );
      ui.Rect? page(int index) => inkOf(
        s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
          s.brushFrameKeyForCut(cut, row.id, row.frames[index].id),
        ),
      );
      expect(page(0), const ui.Rect.fromLTRB(0, 0, 200, 100));
      expect(
        page(1),
        const ui.Rect.fromLTRB(-100, -50, 300, 150),
        reason: 'the reference\'s pose over a 200×100 page — twice its own '
            'size, not fitted to the canvas again',
      );
      expect(
        [for (final (_, width, height) in pdf.renderRequests) (width, height)],
        [(200, 100), (400, 200)],
        reason: 'the vector source rasters once, at the size it stands at',
      );
      s.playbackRig.prerenderScheduler.cancel();
      await tester.pump();
    });
  });
}
