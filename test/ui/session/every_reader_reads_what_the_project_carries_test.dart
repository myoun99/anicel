import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/import/import_preview.dart';

import '../../helpers/carried_media_fixture.dart';
import '../../helpers/psd_fixture.dart';
import '../../helpers/temp_dir.dart';

/// Card `carried-bytes-every-reader` — the SAME question the viewer asks
/// (`the_viewer_reads_what_the_project_carries_test`), at every other reader
/// of a medium's bytes: placing a file from the pool, the import window's
/// preview, a movie row on the canvas, and a movie reference baked into
/// cels. 유저 2026-09-11: 「파일 뭐든 관계없이 법 하나로」; 08-30: 「품은 순간
/// 데이터를 가지고있고 불변이었으면좋겠어서」.
///
/// 🪦Every one of them read the file the medium was imported from: a
/// carried file whose original was deleted could not be placed, previewed
/// or played on the canvas, and one whose original was EDITED placed the
/// edit.
///
/// ⚠️The readers READ what they are handed ([carried_media_fixture]), and
/// the original is made unreadable in every case — so a reader that went to
/// it fails, and one that went to the project's copy succeeds.
void main() {
  late Directory directory;
  late ReadingVideoBackend movies;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-every-reader');
    PdfRenderService.debugOpenerOverride = openPdfThatReads;
    debugVideoDecodeBackend = movies = ReadingVideoBackend();
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    debugVideoDecodeBackend = null;
    deleteTempQuietly(directory);
  });

  /// A layered Photoshop document — the one kind the pool calls a picture
  /// and the window EXPANDS rather than decodes.
  Future<String> writeCarriedLayers(Directory dir) => written(
    dir,
    'layout.psd',
    buildPsd(
      width: 8,
      height: 8,
      layers: [
        PsdTestLayer(
          name: 'ink',
          left: 0,
          top: 0,
          right: 8,
          bottom: 8,
          planes: psdSolidPlanes(8, 8, [10, 20, 30]),
        ),
      ],
      compositePlanes: [Uint8List(64), Uint8List(64), Uint8List(64)],
    ),
  );

  Future<bool> placeMovie(EditorSessionManager s, String path) =>
      s.importDoors.importVideoFile(
        path: path,
        settings: const ImportFileSettings(
          mode: ImportFileMode.keepInside,
          sound: false,
        ),
      );

  final placements =
      <
        ({
          String kind,
          Future<String> Function(Directory) write,
          Future<bool> Function(EditorSessionManager, String) place,
        })
      >[
        (
          kind: 'picture',
          write: writeCarriedPicture,
          place: (s, path) => s.importDoors.importImageFile(
            path: path,
            destination: ImportDestination.activeCutLayer,
            copyIntoProject: true,
          ),
        ),
        (
          kind: 'photoshop layers',
          write: writeCarriedLayers,
          place: (s, path) async =>
              await s.importDoors.importPsdExpanded(
                path: path,
                destination: ImportDestination.activeCutLayer,
                copyIntoProject: true,
              ) !=
              null,
        ),
        (
          kind: 'pdf',
          write: writeCarriedPdf,
          place: (s, path) => s.importDoors.importPdfFile(
            path: path,
            destination: ImportDestination.activeCutLayer,
            copyIntoProject: true,
          ),
        ),
        (kind: 'movie', write: writeCarriedMovie, place: placeMovie),
      ];

  /// [write]'s file, carried and saved, its original [fate] — the state a
  /// project opened on another machine, or after a clean-up, is in.
  Future<({EditorSessionManager session, String path})> carriedAndGone(
    WidgetTester tester,
    Future<String> Function(Directory) write,
    OriginalFate fate,
  ) async {
    final carried = await carrying(tester, directory, write);
    // Held, as while someone works: nothing here is decoded unless a test
    // asks for it.
    carried.session.playbackRig.prerenderScheduler.beginInputHold();
    await saveProject(tester, carried.session, directory);
    fate.befall(carried.path);
    return carried;
  }

  group('placing a carried file from the pool', () {
    for (final (:kind, :write, :place) in placements) {
      for (final fate in OriginalFate.values) {
        testWidgets('$kind, its original ${fate.name}: the placement reads '
            'what the project carries, and gives it back', (tester) async {
          final (:session, :path) = await carriedAndGone(tester, write, fate);

          final placed = await tester.runAsync(() => place(session, path));

          expect(placed, isTrue);
          expect(
            movies.openedAt.where((opened) => opened.path == path),
            isEmpty,
            reason: 'no decoder was pointed at the original',
          );
          expect(
            session.mediaStagingStore.find(path),
            isNull,
            reason: 'the project already holds it — its original is not '
                'copied again',
          );
          // A placed movie's row asks for its picture as it lands, and HOLDS
          // its bytes for as long as it can play — so the placement's own
          // hold is counted once the rows have let go.
          await tester.runAsync(() => session.movieCels.dispose());
          expect(session.projectFile.heldArchiveEntries, isEmpty);
          await tester.pumpAndSettle();
        });
      }
    }
  });

  group('the import window\'s preview of a carried file', () {
    for (final (:kind, :write) in [
      (kind: 'picture', write: writeCarriedPicture),
      (kind: 'pdf', write: writeCarriedPdf),
      (kind: 'movie', write: writeCarriedMovie),
    ]) {
      testWidgets('$kind, its original deleted: the preview shows what the '
          'project carries, and gives it back when it goes', (tester) async {
        final (:session, :path) = await carriedAndGone(
          tester,
          write,
          OriginalFate.deleted,
        );
        final picture = find.byKey(
          const ValueKey<String>('import-preview-checker'),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 300,
                child: ImportPreview(
                  path: path,
                  inFrame: 0,
                  outFrame: null,
                  rangeEditable: false,
                  onRangeChanged: (start, end) {},
                  soundPeaks: (_) async => null,
                  holdBytes: session.projectFile.holdMediaBytes,
                  frameRate: ProjectFrameRate.fps24,
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 60 && picture.evaluate().isEmpty; i += 1) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(picture, findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        expect(session.projectFile.heldArchiveEntries, isEmpty);
      });
    }
  });

  group('a carried movie on the canvas', () {
    Future<(EditorSessionManager, Layer)> placedAndGone(
      WidgetTester tester,
      OriginalFate fate,
    ) async {
      final (:session, :path) = await carriedAndGone(
        tester,
        writeCarriedMovie,
        fate,
      );
      await tester.runAsync(() => placeMovie(session, path));
      return (
        session,
        session.requireActiveCut.layers.firstWhere(isMovieReference),
      );
    }

    BitmapSurface? pictureAt(EditorSessionManager s, Layer layer, int at) =>
        s.brushSurfaceForLayerFrame(layer, resolveExposedFrameAt(layer, at)!);

    for (final fate in OriginalFate.values) {
      testWidgets('its original ${fate.name}: the row plays what the project '
          'carries', (tester) async {
        final (session, layer) = await placedAndGone(tester, fate);

        await tester.runAsync(
          () => session.movieCels.hydrate(session.requireActiveCut, 0),
        );

        expect(pictureAt(session, layer, 0), isNotNull);
        expect(
          movies.openedAt.where(
            (opened) => opened.path == layer.mediaReference!.assetPath,
          ),
          isEmpty,
          reason: 'no decoder was pointed at the original',
        );
        await tester.pumpAndSettle();
      });

      testWidgets('its original ${fate.name}: baking the row into cels reads '
          'what the project carries', (tester) async {
        final (session, layer) = await placedAndGone(tester, fate);

        final baked = await tester.runAsync(
          () => session.importDoors.rasterizeMovieReference(
            cutId: session.requireActiveCut.id,
            layerId: layer.id,
          ),
        );

        expect(baked, isTrue);
        expect(
          session.requireActiveCut.layers.where(isMovieReference),
          isEmpty,
          reason: 'the reference became cels',
        );
        await tester.runAsync(() => session.movieCels.dispose());
        expect(
          session.projectFile.heldArchiveEntries,
          isEmpty,
          reason: 'the bake gave back what it read',
        );
        await tester.pumpAndSettle();
      });
    }

    testWidgets('closing the session gives back what its movie rows read', (
      tester,
    ) async {
      final (session, _) = await placedAndGone(tester, OriginalFate.deleted);
      await tester.runAsync(
        () => session.movieCels.hydrate(session.requireActiveCut, 0),
      );
      expect(
        session.projectFile.heldArchiveEntries,
        hasLength(1),
        reason: 'the premise: the row holds its entry while it can play',
      );

      await tester.runAsync(() => session.movieCels.dispose());

      expect(session.projectFile.heldArchiveEntries, isEmpty);
    });
  });
}
