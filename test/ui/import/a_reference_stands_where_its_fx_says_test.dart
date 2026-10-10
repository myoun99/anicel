// A REFERENCE STANDS WHERE ITS REFERENCE FX SAYS (I-68). 🗣️유저 2026-10-04:
// 「처음에 용지 세팅하고나서 오른쪽으로 캔버스 크기 늘리고나서, 용지
// 스위칭하려고 배치하면 캔버스 중앙에 배치되는데 … 구조적,근본적인 해결」;
// 10-10: 「담는값은 변형도구랑 같은거 공유 … 해상도가 달라도 같은크기로
// 겹치지않게 … 배치된 값, 원본값 유지」 · 캔버스 크기 변경 「가」(기준점대로).
//
// The pose a placement starts a file's picture at is the reference's own:
// the canvas growing afterwards moves it with the drawings, a file swapped
// in stands at it over ITS pixels, moving it lays the file again — and a
// movie, decoded as it is shown, stands there too. 10-10 「가」: a GIF's
// frames and a PDF's pages are laid again the same way, each cel from the
// picture of the file it says it is.
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
import 'package:anicel/src/models/reference_swap.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/timeline/reference_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart';

import '../../helpers/cel_text_fixture.dart' show pixelOf;
import '../../helpers/fake_pdf_document.dart';
import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/three_frame_gif.dart';

/// Cel [index] of [row] as the store holds it baked.
BitmapSurface? celOf(EditorSessionManager s, Layer row, int index) =>
    s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      s.brushFrameKeyForCut(s.requireActiveCut, row.id, row.frames[index].id),
    );

/// The colour [surface] holds at canvas pixel ([x], [y]), as straight RGBA.
List<int>? colourAt(BitmapSurface? surface, int x, int y) {
  if (surface == null) {
    return null;
  }
  final size = surface.tileSize;
  return pixelOf(
    surface,
    TileCoord.fromPixel(pixelX: x, pixelY: y, tileSize: size),
    x % size,
    y % size,
  );
}

/// A redraw the file did not give: it lacks [picture], counted from 0.
Matcher lacks(int picture) => isA<ReferenceLacksPicture>().having(
  (answer) => answer.picture,
  'picture',
  picture,
);

/// [colour] as the straight RGBA a surface reads back.
List<int> rgbaOf(ui.Color colour) {
  final argb = colour.toARGB32();
  return [(argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, argb >>> 24];
}

/// The warmer the session woke, stopped — or it waits on past the test.
Future<void> stopTheWarmer(WidgetTester tester, EditorSessionManager s) async {
  s.playbackRig.prerenderScheduler.cancel();
  await tester.pump();
}

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
        isA<ReferenceLaid>(),
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
        isA<ReferenceLaid>(),
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
      // the warmer they woke stopped after them.
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
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
        isA<ReferenceLeftAlone>(),
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
        isA<ReferenceLaid>(),
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

    /// [pdf]'s pages from [inFrame] to [outFrame] placed as a reference on
    /// a 200×100 canvas, contained: a 100×50 first page stands at twice its
    /// size.
    Future<(EditorSessionManager, Layer)> placed(
      WidgetTester tester,
      FakePdfDocument pdf, {
      int inFrame = 0,
      int? outFrame,
    }) async {
      PdfRenderService.debugOpenerOverride = (_) async => pdf;
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.playbackRig.prerenderScheduler.beginInputHold();
      await tester.runAsync(() async {
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
            inFrame: inFrame,
            outFrame: outFrame,
          ),
          isTrue,
        );
      });
      final row = s.requireActiveCut.layers.firstWhere(
        (layer) => layer.mediaReference != null,
      );
      return (s, row);
    }

    /// [row]'s reference fx moved to 1:1 in the canvas's middle.
    Future<ReferenceRedraw?> moved(
      WidgetTester tester,
      EditorSessionManager s,
      Layer row,
    ) => tester.runAsync(
      () => s.importDoors.reposeReference(
        layerId: row.id,
        pose: TransformPose(center: CanvasPoint(x: 100, y: 50)),
      ),
    );

    testWidgets('🎯every page of a reference stands at ITS pose over the '
        'page\'s own size — a bigger page stands bigger, not fitted again — '
        'and each is rendered once at the size it stands at', (tester) async {
      final pdf = FakePdfDocument(
        pageSizes: const [ui.Size(100, 50), ui.Size(200, 100)],
      );
      final (s, row) = await placed(tester, pdf);

      expect(
        row.mediaReference!.pose,
        TransformPose.uniform(center: CanvasPoint(x: 100, y: 50), zoom: 2),
      );
      expect(
        row.mediaReference!.pictureSize,
        const CanvasSize(width: 100, height: 50),
      );
      expect(inkOf(celOf(s, row, 0)), const ui.Rect.fromLTRB(0, 0, 200, 100));
      expect(
        inkOf(celOf(s, row, 1)),
        const ui.Rect.fromLTRB(-100, -50, 300, 150),
        reason: 'the reference\'s pose over a 200×100 page — twice its own '
            'size, not fitted to the canvas again',
      );
      expect(
        [for (final (_, width, height) in pdf.renderRequests) (width, height)],
        [(200, 100), (400, 200)],
        reason: 'the vector source rasters once, at the size it stands at',
      );
      await stopTheWarmer(tester, s);
    });

    testWidgets('🎯moving the fx renders EACH page again from its own page '
        'of the file — counted from the span\'s IN, not from the row\'s '
        'first cel — each at its own size, and lets each render go once '
        'laid', (tester) async {
      final pdf = FakePdfDocument(
        pageSizes: const [ui.Size(100, 50), ui.Size(100, 50), ui.Size(60, 30)],
      );
      final (s, row) = await placed(tester, pdf, inFrame: 1);
      expect([for (final frame in row.frames) frame.filePicture], [1, 2]);
      pdf.renderRequests.clear();

      expect(await moved(tester, s, row), isA<ReferenceLaid>());

      expect(
        pdf.renderRequests,
        [(1, 100, 50), (2, 60, 30)],
        reason: 'each page once, at the size it stands at now',
      );
      for (final (index, ink) in [
        (0, const ui.Rect.fromLTRB(50, 25, 150, 75)),
        (1, const ui.Rect.fromLTRB(70, 35, 130, 65)),
      ]) {
        final cel = celOf(s, row, index);
        expect(inkOf(cel), ink);
        expect(
          colourAt(cel, 100, 50),
          rgbaOf(FakePdfDocument.pageColor(index + 1)),
          reason: 'cel $index is page ${index + 1}',
        );
      }
      expect(
        s.layerById(row.id)!.mediaReference!.pictureSize,
        const CanvasSize(width: 100, height: 50),
        reason: 'the size the row says is its first cel\'s page, as placed',
      );
      expect(
        pdf.renders.where((image) => !image.debugDisposed),
        isEmpty,
        reason: 'a page rendered for the laying is let go of once laid — the '
            'placing\'s and the move\'s alike',
      );
      await stopTheWarmer(tester, s);
    });

    testWidgets('one page kept from the middle is a still that says WHICH '
        'page it is — and the fx lays that page again', (tester) async {
      final pdf = FakePdfDocument(
        pageSizes: const [ui.Size(100, 50), ui.Size(100, 50), ui.Size(100, 50)],
      );
      final (s, row) = await placed(tester, pdf, inFrame: 2, outFrame: 2);
      expect(row.frames.single.filePicture, 2);
      pdf.renderRequests.clear();

      await moved(tester, s, row);

      expect(pdf.renderRequests, [(2, 100, 50)]);
      expect(
        colourAt(celOf(s, row, 0), 100, 50),
        rgbaOf(FakePdfDocument.pageColor(2)),
      );
      await stopTheWarmer(tester, s);
    });

    testWidgets('a page the renderer gives up on is a file that does not '
        'read — the move lands nothing', (tester) async {
      // The placing let go of the document; the same one, asked again,
      // cancels every page it is asked for — pdfrx's way.
      final (s, row) = await placed(
        tester,
        FakePdfDocument(
          pageSizes: const [ui.Size(100, 50), ui.Size(100, 50)],
          cancelsWhenDisposed: true,
        ),
      );
      final canUndo = s.canUndo;

      expect(await moved(tester, s, row), isA<ReferenceUnreadable>());

      expect(s.canUndo, canUndo);
      expect(inkOf(celOf(s, row, 0)), const ui.Rect.fromLTRB(0, 0, 200, 100));
      await stopTheWarmer(tester, s);
    });

    testWidgets('a document that has since lost the page a cel shows is not '
        'laid again — the move lands nothing, and every cel keeps what it '
        'showed', (tester) async {
      final (s, row) = await placed(
        tester,
        FakePdfDocument(
          pageSizes: const [
            ui.Size(100, 50),
            ui.Size(100, 50),
            ui.Size(100, 50),
          ],
        ),
        inFrame: 1,
      );
      final canUndo = s.canUndo;
      // The same file, two pages now: the conte exported again, shorter.
      PdfRenderService.debugOpenerOverride = (_) async => FakePdfDocument(
        pageSizes: const [ui.Size(100, 50), ui.Size(100, 50)],
      );

      expect(await moved(tester, s, row), lacks(2));

      expect(s.canUndo, canUndo);
      for (final index in [0, 1]) {
        final cel = celOf(s, row, index);
        expect(inkOf(cel), const ui.Rect.fromLTRB(0, 0, 200, 100));
        expect(
          colourAt(cel, 100, 50),
          rgbaOf(FakePdfDocument.pageColor(index + 1)),
          reason: 'cel $index',
        );
      }
      await stopTheWarmer(tester, s);
    });
  });

  // I-68 「가」 (유저 2026-10-10): a GIF's frames are laid again by the
  // still's law — each cel from the picture of the file it says it is.
  group('a GIF\'s frames', () {
    late Directory tempDir;
    const white = [255, 255, 255, 255];
    const black = [0, 0, 0, 255];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anicel-i68-gif');
    });

    tearDown(() => deleteTempQuietly(tempDir));

    /// The black · white · black GIF from its second frame to [outFrame],
    /// contained as a reference on a 100×100 canvas: to its end, two cels
    /// — white, then black — each filling it.
    Future<(EditorSessionManager, Layer)> placed(
      WidgetTester tester, {
      int? outFrame,
    }) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.playbackRig.prerenderScheduler.beginInputHold();
      await tester.runAsync(() async {
        s.cutVerbs.resizeActiveCutCanvas(
          const CanvasSize(width: 100, height: 100),
        );
        expect(
          await s.importDoors.importImageFile(
            path: await writeThreeFrameGif(tempDir, 'walk.gif'),
            destination: ImportDestination.activeCutLayer,
            copyIntoProject: false,
            inFrame: 1,
            outFrame: outFrame,
          ),
          isTrue,
        );
      });
      final row = s.requireActiveCut.layers.firstWhere(
        (layer) => layer.mediaReference != null,
      );
      return (s, row);
    }

    testWidgets('🎯each cel says which picture of the FILE it is — from the '
        'span\'s IN — so the row has the reference fx', (tester) async {
      final (s, row) = await placed(tester);

      expect([for (final frame in row.frames) frame.filePicture], [1, 2]);
      for (final (index, colour) in [(0, white), (1, black)]) {
        final cel = celOf(s, row, index);
        expect(inkOf(cel), const ui.Rect.fromLTRB(0, 0, 100, 100));
        expect(colourAt(cel, 50, 50), colour, reason: 'cel $index');
      }
      expect(
        timelineLanesForLayer(
          layer: row,
          session: s,
          expandedGroupKeys: const {},
        ).first.laneId,
        referenceGroupLaneId,
      );
      await stopTheWarmer(tester, s);
    });

    testWidgets('🎯moving the reference fx lays EACH cel again from its own '
        'picture of the file — the white one white, the black one black — '
        'not every cel from the first', (tester) async {
      final (s, row) = await placed(tester);

      expect(
        await tester.runAsync(
          () => s.importDoors.reposeReference(
            layerId: row.id,
            pose: TransformPose.uniform(
              center: CanvasPoint(x: 50, y: 50),
              zoom: 50,
            ),
          ),
        ),
        isA<ReferenceLaid>(),
      );

      for (final (index, colour) in [(0, white), (1, black)]) {
        final cel = celOf(s, row, index);
        expect(inkOf(cel), const ui.Rect.fromLTRB(25, 25, 75, 75));
        expect(colourAt(cel, 50, 50), colour, reason: 'cel $index');
      }
      await stopTheWarmer(tester, s);
    });

    testWidgets('one frame kept is a still that says WHICH frame it is — '
        'the white one, laid again white', (tester) async {
      final (s, row) = await placed(tester, outFrame: 1);
      expect(row.frames.single.filePicture, 1);

      await tester.runAsync(
        () => s.importDoors.reposeReference(
          layerId: row.id,
          pose: TransformPose.uniform(
            center: CanvasPoint(x: 50, y: 50),
            zoom: 50,
          ),
        ),
      );

      final cel = celOf(s, row, 0);
      expect(inkOf(cel), const ui.Rect.fromLTRB(25, 25, 75, 75));
      expect(colourAt(cel, 50, 50), white);
      await stopTheWarmer(tester, s);
    });

    // ⓐ (유저 2026-10-10 「추천대로가자」): a swap keeps the picture's number
    // as a move does — the file is all that changes.
    testWidgets('🎯a still that is one frame takes the SAME frame of a file '
        'swapped in — another GIF\'s 2nd, not its 1st — and a file with no '
        'such frame is not taken: the answer names the one it lacks',
        (tester) async {
      final (s, row) = await placed(tester, outFrame: 1);
      final files = (await tester.runAsync(
        () async => (
          // red · blue · red
          gif: await writeThreeFrameGif(
            tempDir,
            'other.gif',
            colours: const [0xFF0000, 0x0000FF],
          ),
          png: await writeSolidPng(
            tempDir,
            'bg.png',
            width: 1,
            height: 1,
            rgba: 0x00FF00FF,
          ),
        ),
      ))!;

      expect(
        await tester.runAsync(
          () => s.importDoors.swapReference(layerId: row.id, path: files.png),
        ),
        lacks(1),
      );
      expect(s.layerById(row.id), row, reason: 'nothing changed');

      expect(
        await tester.runAsync(
          () => s.importDoors.swapReference(layerId: row.id, path: files.gif),
        ),
        isA<ReferenceLaid>(),
      );
      expect(
        colourAt(celOf(s, row, 0), 50, 50),
        [0, 0, 255, 255],
        reason: 'its 2nd frame, blue — not its 1st, red',
      );
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });

    testWidgets('a file that has since lost the picture a cel shows is not '
        'laid again — the move lands nothing, and every cel keeps what it '
        'showed', (tester) async {
      final (s, row) = await placed(tester);
      final canUndo = s.canUndo;
      // The same name, now one picture: the GIF re-exported shorter.
      await tester.runAsync(
        () => writeSolidPng(
          tempDir,
          'walk.gif',
          width: 1,
          height: 1,
          rgba: 0x00FF00FF,
        ),
      );

      expect(
        await tester.runAsync(
          () => s.importDoors.reposeReference(
            layerId: row.id,
            pose: TransformPose.uniform(
              center: CanvasPoint(x: 50, y: 50),
              zoom: 50,
            ),
          ),
        ),
        lacks(1),
      );
      expect(s.canUndo, canUndo);
      for (final (index, colour) in [(0, white), (1, black)]) {
        final cel = celOf(s, row, index);
        expect(inkOf(cel), const ui.Rect.fromLTRB(0, 0, 100, 100));
        expect(colourAt(cel, 50, 50), colour, reason: 'cel $index');
      }
      await stopTheWarmer(tester, s);
    });

    testWidgets('rasterizing lets go of which picture each cel was, with the '
        'file — its undo gives both back, its redo takes them again',
        (tester) async {
      final (s, row) = await placed(tester);
      List<int?> pictures() => [
        for (final frame in s.layerById(row.id)!.frames) frame.filePicture,
      ];

      s.editingCanvas.rasterizeLayerReferences([row.id]);
      expect(s.layerById(row.id)!.mediaReference, isNull);
      expect(pictures(), [null, null]);

      s.undo();
      expect(s.layerById(row.id)!.mediaReference, isNotNull);
      expect(pictures(), [1, 2]);
      expect(referenceRedrawFor(s.layerById(row.id)!), ReferenceSwap.pictures);

      s.redo();
      expect(pictures(), [null, null]);
      await tester.pump(const Duration(minutes: 1));
      await stopTheWarmer(tester, s);
    });
  });
}
