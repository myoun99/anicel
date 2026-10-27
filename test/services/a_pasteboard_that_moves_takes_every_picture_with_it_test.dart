import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/commands/set_project_pasteboard_command.dart';
import 'package:anicel/src/services/persistence/scratch_file.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/cels_parked_cold.dart';
import '../helpers/files_written_under.dart';

/// 🚨I-109 — THE PASTEBOARD'S WALL MOVES WITH EVERY PICTURE.
///
/// 🗣️I-109-Q2 (유저 2026-10-20): 「잘라낸다 … 다만 언두하면 제대로 돌아온다거나
/// 이런 안전장치만 제대로 철저하게. 페이스트보드 끈다고 안쪽 그림이 위치가
/// 바뀐다거나 그런것들도 다 조심하고」 — so what lies past a wall that shrinks
/// is cut, in every tier a cel can be kept in, nothing inside it moves by a
/// pixel, and one undo puts every pixel back. Q4: a file's picture laid past
/// the wall is left as it is.
///
/// The paper is 16 × 8 in tiles of 4: at 1.5x the wall stands 4 past the
/// sides and 2 past the top and bottom — x in [-4, 20), y in [-2, 10).
void main() {
  const canvas = CanvasSize(width: 16, height: 8);
  const tileSize = 4;

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  /// A tile whose every pixel is [value] in all four channels, so a byte
  /// read off it says which tile it came from.
  BitmapTile tile(int value) => BitmapTile(
    size: tileSize,
    pixels: Uint8List(tileSize * tileSize * 4)..fillRange(0, 64, value),
  );

  /// Inside the paper (0, 0), inside the 1.5x pasteboard (-1, 0) and
  /// (4, 1), straddling its top (1, -1: two rows past it, two inside), and
  /// wholly past it (-2, 0) and (5, 0).
  final inside = TileCoord(x: 0, y: 0);
  final onTheBoard = TileCoord(x: -1, y: 0);
  final onTheRight = TileCoord(x: 4, y: 1);
  final straddling = TileCoord(x: 1, y: -1);
  final pastLeft = TileCoord(x: -2, y: 0);
  final pastRight = TileCoord(x: 5, y: 0);

  BitmapSurface drawn({DirtyRegion? laid}) => BitmapSurface(
    canvasSize: canvas,
    tileSize: tileSize,
    laidBounds: laid,
  ).putTiles([
    (coord: inside, tile: tile(10)),
    (coord: onTheBoard, tile: tile(20)),
    (coord: onTheRight, tile: tile(30)),
    (coord: straddling, tile: tile(40)),
    (coord: pastLeft, tile: tile(50)),
    (coord: pastRight, tile: tile(60)),
  ]);

  /// The straddling tile's rows, top to bottom, as the byte each holds.
  List<int> rowsOf(BitmapTile tile) {
    final pixels = tile.pixels;
    return [
      for (var row = 0; row < tileSize; row += 1)
        pixels[row * tileSize * 4],
    ];
  }

  group('a picture put behind a nearer wall (surfaceBehindReach)', () {
    test('keeps every tile inside as the very tile, at its place', () {
      final before = drawn();
      final behind = surfaceBehindReach(before, PasteboardReach.quarter);
      expect(behind.pasteboardReach, PasteboardReach.quarter);
      for (final coord in [inside, onTheBoard, onTheRight]) {
        expect(identical(behind.tileAt(coord), before.tileAt(coord)), isTrue);
      }
    });

    test('drops the tiles wholly past it', () {
      final behind = surfaceBehindReach(drawn(), PasteboardReach.quarter);
      expect(behind.tileAt(pastLeft), isNull);
      expect(behind.tileAt(pastRight), isNull);
    });

    test('clears what of a straddling tile lies past it, and only that', () {
      final behind = surfaceBehindReach(drawn(), PasteboardReach.quarter);
      // Rows -4 and -3 are past the top wall (-2); rows -2 and -1 inside.
      expect(rowsOf(behind.tileAt(straddling)!), [0, 0, 40, 40]);
    });

    test('a straddling tile whose ink all lay past it is not kept empty', () {
      // Ink on the two rows past the top wall only.
      final pixels = Uint8List(tileSize * tileSize * 4)
        ..fillRange(0, 2 * tileSize * 4, 40);
      final surface = BitmapSurface(
        canvasSize: canvas,
        tileSize: tileSize,
      ).putTiles([
        (coord: straddling, tile: BitmapTile(size: tileSize, pixels: pixels)),
      ]);
      final behind = surfaceBehindReach(surface, PasteboardReach.quarter);
      expect(behind.tiles, isEmpty);
    });

    test('off, the paper alone is left', () {
      final behind = surfaceBehindReach(drawn(), PasteboardReach.none);
      expect(behind.tiles.keys.toSet(), {inside});
    });

    test('cuts a text\'s letters the way it cuts the drawing', () {
      final surface = BitmapSurface(
        canvasSize: canvas,
        tileSize: tileSize,
        texts: [
          CelText(
            id: 1,
            content: CelTextContent(
              spans: const [CelTextSpan(text: 'a', style: TextLetterStyle())],
              anchor: CanvasPoint(x: 0, y: 0),
            ),
            plate: {straddling: tile(40), pastLeft: tile(50), inside: tile(10)},
          ),
        ],
      );
      final behind = surfaceBehindReach(surface, PasteboardReach.quarter);
      final plate = behind.texts.single.plate;
      expect(plate.keys.toSet(), {straddling, inside});
      expect(rowsOf(plate[straddling]!), [0, 0, 40, 40]);
      expect(behind.texts.single.content, surface.texts.single.content);

      // What the wall crossed of the letters, cleared elsewhere, is taken as
      // it came, as the drawing's is.
      final crossed = wallCrossingsOf(surface, behind);
      expect(crossed.texts.single.plate.keys, [straddling]);
      final taken = surfaceBehindReach(
        surface,
        PasteboardReach.quarter,
        crossed: crossed,
      ).texts.single.plate;
      expect(
        identical(taken[straddling], crossed.texts.single.plate[straddling]),
        isTrue,
      );
      expect(
        identical(taken[inside], surface.texts.single.plate[inside]),
        isTrue,
      );
    });

    test('leaves a file\'s picture laid past the wall as it is (Q4)', () {
      final laid = DirtyRegion(
        left: -8,
        top: -4,
        rightExclusive: 24,
        bottomExclusive: 12,
      );
      final before = drawn(laid: laid);
      final behind = surfaceBehindReach(before, PasteboardReach.quarter);
      for (final coord in [pastLeft, pastRight, straddling]) {
        expect(identical(behind.tileAt(coord), before.tileAt(coord)), isTrue);
      }
      expect(behind.laidBounds, laid);
    });

    test('a picture already behind the wall is handed back as it is', () {
      final behind = surfaceBehindReach(drawn(), PasteboardReach.quarter);
      expect(
        identical(surfaceBehindReach(behind, PasteboardReach.quarter), behind),
        isTrue,
      );
    });

    test('what the wall crossed, cleared elsewhere, is taken as it came — '
        'the rest decided here, the very tiles', () {
      final surface = drawn();
      final here = surfaceBehindReach(surface, PasteboardReach.quarter);
      final crossed = wallCrossingsOf(surface, here);
      expect(crossed.tiles.keys, [straddling]);
      final taken = surfaceBehindReach(
        surface,
        PasteboardReach.quarter,
        crossed: crossed,
      );
      expect(taken.tiles.keys.toSet(), here.tiles.keys.toSet());
      expect(
        identical(taken.tileAt(straddling), crossed.tileAt(straddling)),
        isTrue,
      );
      for (final coord in [inside, onTheBoard, onTheRight]) {
        expect(identical(taken.tileAt(coord), surface.tileAt(coord)), isTrue);
      }
    });

    // A paper 18 wide does not end on a tile: at 1.5x the wall stands 5
    // past it — x in [-5, 23) — so a tile can straddle it across, and a
    // file laid on the same tile keeps columns of its own.
    const narrow = CanvasSize(width: 18, height: 8);

    /// [column]s of the tile at [coord] once [laid] and the 1.5x wall have
    /// kept what they keep, row by row, as the byte each holds.
    List<List<int>> columnsBehind(TileCoord coord, DirtyRegion laid) {
      final surface = BitmapSurface(
        canvasSize: narrow,
        tileSize: tileSize,
        laidBounds: laid,
      ).putTiles([(coord: coord, tile: tile(70))]);
      final pixels = surfaceBehindReach(
        surface,
        PasteboardReach.quarter,
      ).tileAt(coord)!.pixels;
      return [
        for (var row = 0; row < tileSize; row += 1)
          [
            for (var column = 0; column < tileSize; column += 1)
              pixels[(row * tileSize + column) * 4],
          ],
      ];
    }

    test('clears a straddling tile across, keeping each run a file holds', () {
      // Tile (-2, 0) holds x -8..-5: the wall keeps -5 alone, a file laid
      // on its first two rows keeps -8 — a run to the left of the wall's.
      expect(
        columnsBehind(
          TileCoord(x: -2, y: 0),
          DirtyRegion(left: -8, top: 0, rightExclusive: -7, bottomExclusive: 2),
        ),
        [
          [70, 0, 0, 70],
          [70, 0, 0, 70],
          [0, 0, 0, 70],
          [0, 0, 0, 70],
        ],
      );
    });

    test('a run inside the wall\'s takes nothing of what the wall keeps', () {
      // Tile (5, 0) holds x 20..23: the wall keeps 20..22, a file laid on
      // 21 alone keeps nothing more — and must not cut the wall's short.
      expect(
        columnsBehind(
          TileCoord(x: 5, y: 0),
          DirtyRegion(left: 21, top: 0, rightExclusive: 22, bottomExclusive: 2),
        ),
        [
          for (var row = 0; row < tileSize; row += 1) [70, 70, 70, 0],
        ],
      );
    });
  });

  group('the store moves its wall in every tier', () {
    final cut = key('cut');
    final clean = key('clean');

    /// [clean] has ink inside the 1.5x wall only.
    BitmapSurface inkInside() => BitmapSurface(
      canvasSize: canvas,
      tileSize: tileSize,
    ).putTiles([(coord: inside, tile: tile(10))]);

    void expectCut(BitmapSurface? surface) {
      expect(surface, isNotNull);
      expect(surface!.pasteboardReach, PasteboardReach.quarter);
      expect(surface.tileAt(pastLeft), isNull);
      expect(surface.tileAt(pastRight), isNull);
      expect(rowsOf(surface.tileAt(straddling)!), [0, 0, 40, 40]);
      expect(surface.tileAt(onTheBoard)!.pixels.first, 20);
    }

    test('hot: cut, and handed back as it was for the undo', () {
      final store = BrushFrameStore();
      final before = drawn();
      store.storeBakedSurface(cut, before);
      store.storeBakedSurface(clean, inkInside());
      final taken = store.adoptPasteboardReach(PasteboardReach.quarter);
      expect(taken.keys, [cut]);
      expect(identical(taken[cut]?.picture, before), isTrue);
      expectCut(store.bakedSurfaceOrNull(cut));
      expect(
        store.bakedSurfaceOrNull(clean)!.pasteboardReach,
        PasteboardReach.quarter,
      );
    });

    test('parked cold: rewritten behind the wall without going hot', () {
      final store = BrushFrameStore();
      parkCold(store, {cut: drawn(), clean: inkInside()});
      final taken = store.adoptPasteboardReach(PasteboardReach.quarter);
      expect(taken.keys, [cut]);
      expect(store.isCelCold(cut), isTrue);
      expect(store.isCelCold(clean), isTrue);
      expect(store.dirtyCelKeysSinceSave, {cut});
      expectCut(store.bakedSurfaceOrNull(cut));
    });

    test('kept in a file: rewritten into the room; an untouched cel stays', () {
      final store = BrushFrameStore();
      keepInAFile(store, {cut: drawn(), clean: inkInside()});
      final taken = store.adoptPasteboardReach(PasteboardReach.quarter);
      expect(taken.keys, [cut]);
      expect(store.isCelFileBacked(cut), isFalse);
      expect(store.isCelFileBacked(clean), isTrue);
      expectCut(store.bakedSurfaceOrNull(cut));
      expect(
        store.bakedSurfaceOrNull(clean)!.pasteboardReach,
        PasteboardReach.quarter,
      );
    });

    // Card `a-cooled-empty-cel-reads-drawn` (2026-10-24): a kept cel cut to
    // nothing stays kept, and it read 「그려짐」 by being kept at all — so the
    // block stayed white over nothing, and the crossing below was never
    // heard.
    for (final (tier, keep) in [
      ('parked cold', parkCold),
      ('kept in a file', keepInAFile),
    ]) {
      test('🚨$tier, its lines only past the wall: it crosses to empty, and '
          'the crossing names it', () {
        final store = BrushFrameStore();
        keep(store, {
          cut: BitmapSurface(
            canvasSize: canvas,
            tileSize: tileSize,
          ).putTiles([(coord: pastLeft, tile: tile(50))]),
          clean: inkInside(),
        });
        expect(store.celHasRenderableContent(cut), isTrue, reason: '⛔premise');
        final before = store.celContentRevision.value;

        store.adoptPasteboardReach(PasteboardReach.quarter);

        expect(store.celHasRenderableContent(cut), isFalse);
        expect(store.celHasRenderableContent(clean), isTrue);
        expect(store.hotBakedSurfaceOrNull(cut), isNull, reason: 'still kept');
        expect(store.celContentRevision.value, greaterThan(before));
        expect(store.celsLastCrossed, {cut});
      });
    }

    test('a wall that grows cuts nothing and touches no kept bytes', () {
      final store = BrushFrameStore();
      keepInAFile(
        store,
        {cut: drawn()},
        pasteboardReach: PasteboardReach.quarter,
      );
      expect(store.adoptPasteboardReach(PasteboardReach.whole), isEmpty);
      expect(store.isCelFileBacked(cut), isTrue);
      expect(store.dirtyCelKeysSinceSave, isEmpty);
    });

    test('a project opened at a size hands out its cels behind it', () {
      final store = BrushFrameStore();
      keepInAFile(
        store,
        {cut: drawn()},
        pasteboardReach: PasteboardReach.quarter,
      );
      expect(store.pasteboardReach, PasteboardReach.quarter);
      expectCut(store.bakedSurfaceOrNull(cut));
    });

    test('a picture laid in past the wall is cut on the way in', () {
      final store = BrushFrameStore();
      parkCold(store, const {}, pasteboardReach: PasteboardReach.quarter);
      store.storeBakedSurface(cut, drawn());
      expectCut(store.bakedSurfaceOrNull(cut));
    });

    test('a save that ran across the cut leaves the cut to the next save', (
    ) async {
      final store = BrushFrameStore()..hotCelByteBudget = 0;
      store.storeBakedSurface(cut, drawn());
      store.storeBakedSurface(clean, inkInside());
      await store.drainCooling();
      expect(store.isCelCold(cut), isTrue, reason: 'premise: parked, dirty');
      // The save reads its snapshot, the wall moves while it writes, and
      // the save lands with the bytes from before the cut.
      final snapshot = store.bakedSnapshotForSave();
      expect(snapshot.dirtyTicks.keys, contains(cut));
      store.adoptPasteboardReach(PasteboardReach.quarter);
      store.adoptSavedFile({
        cut: const AnicelCelFileRef(
          filePath: 'unused.anicel',
          dataOffset: 0,
          length: 1,
          canvasSize: canvas,
          tileSize: tileSize,
          photoPaths: [],
          showsSomething: true,
        ),
      }, dirtyTicksAtSnapshot: snapshot.dirtyTicks);
      expect(
        store.dirtyCelKeysSinceSave,
        contains(cut),
        reason: 'the save wrote the picture before the cut: the cut is '
            'unsaved work',
      );
      expectCut(store.bakedSurfaceOrNull(cut));
    });

    // 🗣️F-432 (유저 2026-10-21): 「페이스트 보드 배율 전환이 너무 느리고」 — on
    // a project saved and opened again every kept cel was inflated, cut and
    // compressed again on the UI thread. It is worked out ahead now, on the
    // machine's workers, while the wait window is up.
    group('worked out ahead (F-432)', () {
      /// Every file in the run's room, by its path inside it — once what was
      /// let go is gone ([ScratchFile.letGo]).
      Future<Set<String>> roomFiles() async {
        await ScratchFile.lettingGo;
        return filesWrittenUnder(
          Directory(SessionScratch.stagedFolder()),
        ).toSet();
      }

      /// What the rounds worked out ahead have parked in the room.
      Future<Set<String>> parkedAhead() async => {
        for (final path in await roomFiles())
          if (path.contains('-ahead')) path,
      };

      void expectSamePicture(BitmapSurface? actual, BitmapSurface expected) {
        expect(actual!.tiles.keys.toSet(), expected.tiles.keys.toSet());
        for (final MapEntry(key: coord, :value) in expected.tiles.entries) {
          expect(actual.tileAt(coord)!.pixels, value.pixels, reason: '$coord');
        }
      }

      /// Nothing left to read where [refs] point: a move that read a kept
      /// byte now throws.
      void unreadable(
        BrushFrameStore store,
        Map<BrushFrameKey, AnicelCelFileRef> refs,
      ) {
        store.releaseFilesReadFrom();
        for (final ref in refs.values) {
          File(ref.filePath).deleteSync();
        }
      }

      test('the move takes what was worked out, and reads no kept byte', (
      ) async {
        final store = BrushFrameStore();
        final refs = keepInAFile(store, {cut: drawn(), clean: inkInside()});
        await store.cutCelsAhead(PasteboardReach.quarter);
        unreadable(store, refs);
        final taken = store.adoptPasteboardReach(PasteboardReach.quarter);
        expect(taken.keys, [cut]);
        expectSamePicture(taken[cut]?.picture, drawn());
        expect(store.isCelCold(cut), isTrue);
        expect(store.isCelFileBacked(clean), isTrue);
        expect(store.dirtyCelKeysSinceSave, {cut});
        expectCut(store.bakedSurfaceOrNull(cut));
      });

      for (final (tier, keep) in <(String, _KeepAll)>[
        ('parked cold', parkCold),
        ('kept in a file', keepInAFile),
        // 🗣️F-432: a step done again cuts the cels its undo laid back, every
        // one hot.
        ('hot', _keepHot),
      ]) {
        test('$tier: what is worked out is what the move works out', () async {
          final here = BrushFrameStore();
          final ahead = BrushFrameStore();
          for (final store in [here, ahead]) {
            keep(store, {cut: drawn(), clean: inkInside()});
          }
          await ahead.cutCelsAhead(PasteboardReach.none);
          final takenHere = here.adoptPasteboardReach(PasteboardReach.none);
          final taken = ahead.adoptPasteboardReach(PasteboardReach.none);
          expect(taken.keys, [cut]);
          expect(takenHere.keys, [cut]);
          expectSamePicture(taken[cut]?.picture, takenHere[cut]!.picture);
          for (final key in [cut, clean]) {
            expectSamePicture(
              ahead.bakedSurfaceOrNull(key),
              here.bakedSurfaceOrNull(key)!,
            );
          }
          expect(ahead.dirtyCelKeysSinceSave, here.dirtyCelKeysSinceSave);
        });
      }

      test('on a worker of its own, the road production takes', () async {
        debugWorkersRunHere = false;
        addTearDown(() => debugWorkersRunHere = true);
        final store = BrushFrameStore();
        final refs = keepInAFile(store, {cut: drawn(), clean: inkInside()});
        final reports = <double>[];
        await store.cutCelsAhead(
          PasteboardReach.quarter,
          report: reports.add,
        );
        expect(reports, [0.5, 1.0]);
        unreadable(store, refs);
        expect(store.adoptPasteboardReach(PasteboardReach.quarter).keys, [cut]);
        expectCut(store.bakedSurfaceOrNull(cut));
      });

      test('hot: the move takes the very picture worked out, behind its '
          'wall, and the undo keeps the one it was', () async {
        final store = BrushFrameStore();
        final before = drawn();
        _keepHot(store, {cut: before, clean: inkInside()});
        await store.cutCelsAhead(PasteboardReach.quarter);
        final worked = store.cutAheadOf(cut);
        expectCut(worked);
        for (final coord in [inside, onTheBoard, onTheRight]) {
          expect(
            identical(worked!.tileAt(coord), before.tileAt(coord)),
            isTrue,
            reason: '$coord kept whole: the very tile, shared with the undo',
          );
        }
        expect(store.cutAheadOf(clean), isNull, reason: 'nothing of it cut');
        final taken = store.adoptPasteboardReach(PasteboardReach.quarter);
        expect(identical(taken[cut]?.picture, before), isTrue);
        expect(identical(store.hotBakedSurfaceOrNull(cut), worked), isTrue);
        expect(store.cutAheadOf(cut), isNull, reason: 'let go once taken');
      });

      test('hot, on a worker of its own: its blocks read where they lie, and '
          'held until it is done', () async {
        debugWorkersRunHere = false;
        addTearDown(() => debugWorkersRunHere = true);
        final store = BrushFrameStore();
        _keepHot(store, {cut: drawn(), clean: inkInside()});
        final before = store.hotBakedSurfaceOrNull(cut)!;
        final reports = <double>[];
        await store.cutCelsAhead(
          PasteboardReach.quarter,
          report: reports.add,
        );
        expect(reports, [0.5, 1.0]);
        final worked = store.cutAheadOf(cut);
        expectCut(worked);
        expect(
          identical(worked!.tileAt(inside), before.tileAt(inside)),
          isTrue,
        );
        store.adoptPasteboardReach(PasteboardReach.quarter);
        expect(identical(store.hotBakedSurfaceOrNull(cut), worked), isTrue);
      });

      test('a kept cel that will not read is left to the move, and the rest '
          'is still worked out', () async {
        final store = BrushFrameStore();
        final other = key('other');
        final refs = keepInAFile(store, {cut: drawn(), other: drawn()});
        final unread = File(refs[cut]!.filePath);
        final bytes = unread.readAsBytesSync();
        unread.deleteSync();
        await store.cutCelsAhead(PasteboardReach.quarter);
        unread.writeAsBytesSync(bytes);
        unreadable(store, {other: refs[other]!});
        expect(
          store.adoptPasteboardReach(PasteboardReach.quarter).keys.toSet(),
          {cut, other},
        );
        expectCut(store.bakedSurfaceOrNull(cut));
        expectCut(store.bakedSurfaceOrNull(other));
      });

      test('hot: a cel drawn on since is cut where the move is taken', (
      ) async {
        final store = BrushFrameStore();
        _keepHot(store, {cut: drawn()});
        await store.cutCelsAhead(PasteboardReach.quarter);
        final worked = store.cutAheadOf(cut);
        final drawnSince = drawn();
        store.storeBakedSurface(cut, drawnSince);
        final taken = store.adoptPasteboardReach(PasteboardReach.quarter);
        expect(identical(taken[cut]?.picture, drawnSince), isTrue);
        expect(identical(store.hotBakedSurfaceOrNull(cut), worked), isFalse);
        expectCut(store.bakedSurfaceOrNull(cut));
      });

      test('worked out for another wall: not taken, and not left behind', (
      ) async {
        final store = BrushFrameStore();
        keepInAFile(store, {cut: drawn()});
        final before = await parkedAhead();
        await store.cutCelsAhead(PasteboardReach.none);
        expect((await parkedAhead()).difference(before), hasLength(1));
        expect(store.adoptPasteboardReach(PasteboardReach.quarter).keys, [cut]);
        expect(
          ScratchFile.stillLettingGo,
          1,
          reason: 'what was worked out for the other wall, let go off the '
              'UI thread',
        );
        expectCut(store.bakedSurfaceOrNull(cut));
        expect((await parkedAhead()).difference(before), isEmpty);
      });

      test('hot, worked out for another wall: not taken', () async {
        final store = BrushFrameStore();
        _keepHot(store, {cut: drawn()});
        await store.cutCelsAhead(PasteboardReach.none);
        expect(store.cutAheadOf(cut), isNotNull);
        store.adoptPasteboardReach(PasteboardReach.quarter);
        expectCut(store.bakedSurfaceOrNull(cut));
      });

      test('worked out again, the last round goes', () async {
        final store = BrushFrameStore();
        keepInAFile(store, {cut: drawn()});
        final before = await parkedAhead();
        await store.cutCelsAhead(PasteboardReach.none);
        final first = (await parkedAhead()).difference(before);
        await store.cutCelsAhead(PasteboardReach.quarter);
        final second = (await parkedAhead()).difference(before);
        expect(second, hasLength(1));
        expect(second.intersection(first), isEmpty);
      });

      test('a store laid in anew lets what was worked out go', () async {
        final store = BrushFrameStore();
        keepInAFile(store, {cut: drawn()});
        final before = await parkedAhead();
        await store.cutCelsAhead(PasteboardReach.none);
        parkCold(store, const {});
        expect((await parkedAhead()).difference(before), isEmpty);
      });

      test('a wall that does not shrink works nothing out', () async {
        final store = BrushFrameStore();
        keepInAFile(store, {cut: drawn()});
        final reports = <double>[];
        await store.cutCelsAhead(
          PasteboardReach.whole,
          report: reports.add,
        );
        expect(reports, isEmpty, reason: 'only a wall that shrinks cuts');
      });

      test('a move that goes nowhere lets what was worked out go', () async {
        final store = BrushFrameStore();
        keepInAFile(store, {cut: drawn()});
        final before = await parkedAhead();
        await store.cutCelsAhead(PasteboardReach.quarter);
        expect(store.adoptPasteboardReach(PasteboardReach.whole), isEmpty);
        expect((await parkedAhead()).difference(before), isEmpty);
      });

      test('answers landing after their round was let go leave nothing', (
      ) async {
        final store = BrushFrameStore();
        keepInAFile(store, {cut: drawn()});
        final before = await parkedAhead();
        final working = store.cutCelsAhead(PasteboardReach.none);
        parkCold(store, const {});
        await working;
        expect((await parkedAhead()).difference(before), isEmpty);
      });

      test('parked cold, the bytes a cut replaces leave the room', () async {
        final before = await roomFiles();
        final store = BrushFrameStore();
        parkCold(store, {cut: drawn(), clean: inkInside()});
        await store.cutCelsAhead(PasteboardReach.quarter);
        await ScratchFile.lettingGo;
        store.adoptPasteboardReach(PasteboardReach.quarter);
        expect(
          ScratchFile.stillLettingGo,
          1,
          reason: "the cut's last park, let go off the UI thread",
        );
        expect(
          (await roomFiles()).difference(before),
          hasLength(2),
          reason: "the clean cel's, and the cut parked ahead — the cut's "
              'last bytes went when it was kept anew',
        );
      });

      test('a cel the move cut stands behind its wall: moved back and forth, '
          'nothing is worked out for it again', () async {
        final store = BrushFrameStore();
        keepInAFile(store, {cut: drawn()});
        expect(store.adoptPasteboardReach(PasteboardReach.quarter).keys, [cut]);
        store.adoptPasteboardReach(PasteboardReach.whole);
        final reports = <double>[];
        await store.cutCelsAhead(
          PasteboardReach.quarter,
          report: reports.add,
        );
        expect(reports, isEmpty, reason: 'no cel to work out');
      });

      test('a move back and forth reads the kept bytes once', () {
        final store = BrushFrameStore();
        final refs = keepInAFile(store, {clean: inkInside()});
        expect(store.adoptPasteboardReach(PasteboardReach.quarter), isEmpty);
        store.adoptPasteboardReach(PasteboardReach.whole);
        unreadable(store, refs);
        expect(store.adoptPasteboardReach(PasteboardReach.quarter), isEmpty);
        expect(store.isCelFileBacked(clean), isTrue);
      });

      for (final ahead in [false, true]) {
        test('a room that will not take the cut leaves the cel as it was'
            '${ahead ? ' — worked out ahead too' : ''}', () async {
          final store = BrushFrameStore();
          keepInAFile(store, {cut: drawn()});
          // A FILE where the room's folder has to go — a revoked scope or a
          // full disk (`a_cooled_cel_parks_on_disk_test`).
          final room = Directory(SessionScratch.stagedFolder());
          if (room.existsSync()) {
            room.deleteSync(recursive: true);
          }
          final blocker = File(SessionScratch.stagedFolder())
            ..createSync(recursive: true)
            ..writeAsBytesSync(const [0]);
          addTearDown(() {
            if (blocker.existsSync()) {
              blocker.deleteSync();
            }
          });
          if (ahead) {
            await store.cutCelsAhead(PasteboardReach.quarter);
          }
          expect(store.adoptPasteboardReach(PasteboardReach.quarter), isEmpty);
          expect(
            store.isCelFileBacked(cut),
            isTrue,
            reason: '⛔its bytes stay where they were — not out of the file '
                'and into a room that never took them',
          );

          // ⚠️Not read before this: a read thaws it, and a hot cel is cut by
          // its own pass whatever was learnt of its bytes.
          blocker.deleteSync();
          store.adoptPasteboardReach(PasteboardReach.whole);
          expect(
            store.adoptPasteboardReach(PasteboardReach.quarter).keys,
            [cut],
            reason: '⛔a cut the room refused is not a picture that stands '
                'behind the wall: the next move cuts it',
          );
          expectCut(store.bakedSurfaceOrNull(cut));
        });
      }
    });
  });

  group('SetProjectPasteboardCommand', () {
    final cut = key('cut');

    ({ProjectRepository repository, BrushFrameStore store}) fixture(
      void Function(BrushFrameStore store) keep,
    ) {
      final repository = ProjectRepository()
        ..replaceProject(
          Project(
            id: const ProjectId('p'),
            name: 'p',
            createdAt: DateTime.utc(2026, 10, 21),
            tracks: const [],
          ),
        );
      final store = BrushFrameStore();
      keep(store);
      return (repository: repository, store: store);
    }

    void expectWhole(BitmapSurface? surface, BitmapSurface before) {
      for (final coord in before.tiles.keys) {
        expect(
          surface!.tileAt(coord)!.pixels,
          before.tileAt(coord)!.pixels,
          reason: 'tile $coord back, byte for byte, where it was',
        );
      }
      expect(surface!.tiles.keys.toSet(), before.tiles.keys.toSet());
    }

    for (final (tier, keep) in <(String, _Keep)>[
      ('hot', (store, surface) => store.storeBakedSurface(cut, surface)),
      ('parked cold', (store, surface) => parkCold(store, {cut: surface})),
      (
        'kept in a file',
        (store, surface) => keepInAFile(store, {cut: surface}),
      ),
    ]) {
      test('$tier: a smaller size cuts, and undo and redo walk it back', () {
        final before = drawn();
        final f = fixture((store) => keep(store, before));
        final command = SetProjectPasteboardCommand(
          repository: f.repository,
          brushFrameStore: f.store,
          size: PasteboardSize.oneAndAHalf,
        )..execute();
        expect(
          f.repository.requireProject().pasteboardSize,
          PasteboardSize.oneAndAHalf,
        );
        expect(f.store.pasteboardReach, PasteboardReach.quarter);
        final cutSurface = f.store.bakedSurfaceOrNull(cut)!;
        expect(cutSurface.tileAt(pastLeft), isNull);
        expect(command.estimatedRetainedBytes(undone: false), greaterThan(0));

        command.undo();
        expect(
          f.repository.requireProject().pasteboardSize,
          PasteboardSize.three,
        );
        expect(f.store.pasteboardReach, PasteboardReach.whole);
        expectWhole(f.store.bakedSurfaceOrNull(cut), before);

        command.execute();
        expect(f.store.bakedSurfaceOrNull(cut)!.tileAt(pastLeft), isNull);
        command.undo();
        expectWhole(f.store.bakedSurfaceOrNull(cut), before);
      });

      test('$tier: undone, the cel is at the revision that named what it is '
          'given back — every picture made of it answers again (F-432 ④)', () {
        final f = fixture((store) => keep(store, drawn()));
        final named = f.store.getOrCreateFrame(cut).sourceRevision;
        final command = SetProjectPasteboardCommand(
          repository: f.repository,
          brushFrameStore: f.store,
          size: PasteboardSize.oneAndAHalf,
        )..execute();
        expect(f.store.getOrCreateFrame(cut).sourceRevision, isNot(named));
        command.undo();
        expect(f.store.getOrCreateFrame(cut).sourceRevision, named);
        command.execute();
        command.undo();
        expect(f.store.getOrCreateFrame(cut).sourceRevision, named);
      });
    }

    test('off leaves the paper alone; undo brings the pasteboard back', () {
      final before = drawn();
      final f = fixture((store) => store.storeBakedSurface(cut, before));
      final command = SetProjectPasteboardCommand(
        repository: f.repository,
        brushFrameStore: f.store,
        inUse: false,
      )..execute();
      expect(f.repository.requireProject().pasteboardInUse, isFalse);
      // The size is kept for when it is on again.
      expect(
        f.repository.requireProject().pasteboardSize,
        PasteboardSize.three,
      );
      expect(f.store.bakedSurfaceOrNull(cut)!.tiles.keys.toSet(), {inside});
      command.undo();
      expect(f.repository.requireProject().pasteboardInUse, isTrue);
      expectWhole(f.store.bakedSurfaceOrNull(cut), before);
    });

    test('works out ahead what each way of it cuts — none where its wall '
        'grows', () {
      final f = fixture((store) => store.storeBakedSurface(cut, drawn()));
      final shrink = SetProjectPasteboardCommand(
        repository: f.repository,
        brushFrameStore: f.store,
        size: PasteboardSize.oneAndAHalf,
      );
      expect(shrink.workAhead(undo: false)?.wall, WallMove.pasteboard);
      expect(shrink.workAhead(undo: true), isNull, reason: 'not taken yet');
      shrink.execute();
      expect(shrink.workAhead(undo: true), isNull, reason: 'its undo grows');
      final grow = SetProjectPasteboardCommand(
        repository: f.repository,
        brushFrameStore: f.store,
        size: PasteboardSize.three,
      );
      expect(grow.workAhead(undo: false), isNull);
      grow.execute();
      expect(grow.workAhead(undo: true)?.wall, WallMove.pasteboard);
      grow.undo();
      shrink.undo();
      expect(shrink.workAhead(undo: false)?.wall, WallMove.pasteboard);
    });

    test('done again either way, it cuts what was worked out ahead of it, '
        'and lays every pixel back', () async {
      final before = drawn();
      final f = fixture((store) => store.storeBakedSurface(cut, before));
      final shrink = SetProjectPasteboardCommand(
        repository: f.repository,
        brushFrameStore: f.store,
        size: PasteboardSize.oneAndAHalf,
      )..execute()..undo();
      await shrink.workAhead(undo: false)!.run((_) {});
      final redone = f.store.cutAheadOf(cut);
      expect(redone, isNotNull, reason: 'its undo laid the cel back hot');
      shrink.execute();
      expect(identical(f.store.hotBakedSurfaceOrNull(cut), redone), isTrue);

      final grow = SetProjectPasteboardCommand(
        repository: f.repository,
        brushFrameStore: f.store,
        size: PasteboardSize.three,
      )..execute();
      final drawnPast = drawn();
      f.store.storeBakedSurface(cut, drawnPast);
      await grow.workAhead(undo: true)!.run((_) {});
      final undone = f.store.cutAheadOf(cut);
      expect(undone, isNotNull);
      grow.undo();
      expect(identical(f.store.hotBakedSurfaceOrNull(cut), undone), isTrue);

      shrink.undo();
      expectWhole(f.store.bakedSurfaceOrNull(cut), before);
    });

    // 🗣️Card a-pasteboard-undo-runs-on-the-ui-thread: 🔬S5_BA (2026-10-23):
    // the first undo of the pasteboard turned off removed the parked bytes
    // of the 99 cels it laid back, a file at a time on the UI thread —
    // 30–61 ms of its 33–67.
    test('🚨its undo hands what it lays back\'s parked bytes off the UI '
        'thread, and leaves none of them in the room', () async {
      final before = drawn();
      final f = fixture((store) => keepInAFile(store, {cut: before}));
      final command = SetProjectPasteboardCommand(
        repository: f.repository,
        brushFrameStore: f.store,
        inUse: false,
      );
      await command.workAhead(undo: false)!.run((_) {});
      command.execute();
      expect(f.store.isCelCold(cut), isTrue, reason: 'premise: cut, parked');
      final parked = f.store.bakedSnapshotForSave().cold[cut]!.filePath;
      await ScratchFile.lettingGo;

      command.undo();
      expect(
        ScratchFile.stillLettingGo,
        1,
        reason: 'handed off by the undo, not removed inside it',
      );
      expectWhole(f.store.bakedSurfaceOrNull(cut), before);
      await ScratchFile.lettingGo;
      expect(File(parked).existsSync(), isFalse);
    });

    test('a parked payload still lays every pixel back', () async {
      final before = drawn();
      final f = fixture((store) => store.storeBakedSurface(cut, before));
      final command = SetProjectPasteboardCommand(
        repository: f.repository,
        brushFrameStore: f.store,
        size: PasteboardSize.oneAndAHalf,
      )..execute();
      expect(
        f.store.bakedSurfaceOrNull(cut)!.tiles.length,
        lessThan(before.tiles.length),
        reason: 'premise: the move cut the cel',
      );
      expect(await command.parkPayload(), isTrue);
      command.undo();
      expectWhole(f.store.bakedSurfaceOrNull(cut), before);
    });

    test('a parked payload is laid back under the revision that named it',
        () async {
      final f = fixture((store) => store.storeBakedSurface(cut, drawn()));
      final named = f.store.getOrCreateFrame(cut).sourceRevision;
      final command = SetProjectPasteboardCommand(
        repository: f.repository,
        brushFrameStore: f.store,
        size: PasteboardSize.oneAndAHalf,
      )..execute();
      expect(
        f.store.getOrCreateFrame(cut).sourceRevision,
        isNot(named),
        reason: 'premise: the move cut the cel',
      );
      expect(await command.parkPayload(), isTrue);
      expect(command.estimatedRetainedBytes(undone: false), 0);
      command.undo();
      expect(f.store.getOrCreateFrame(cut).sourceRevision, named);
    });

    test('a parked payload read back is let go off the UI thread', () async {
      final f = fixture((store) => store.storeBakedSurface(cut, drawn()));
      final command = SetProjectPasteboardCommand(
        repository: f.repository,
        brushFrameStore: f.store,
        inUse: false,
      )..execute();
      final room = Directory(SessionScratch.volatileFolder());
      final before = filesWrittenUnder(room).toSet();
      expect(await command.parkPayload(), isTrue);
      final parked = filesWrittenUnder(room).toSet().difference(before);
      expect(parked, hasLength(1), reason: 'premise: the cut tiles parked');
      await ScratchFile.lettingGo;

      command.undo();
      expect(
        ScratchFile.stillLettingGo,
        1,
        reason: 'the payload, read back, let go off the UI thread',
      );
      await ScratchFile.lettingGo;
      expect(filesWrittenUnder(room).toSet().intersection(parked), isEmpty);
    });
  });

  group('a session follows the wall', () {
    BrushFrameEditingCoordinator coordinator(BrushFrameStore store) =>
        BrushFrameEditingCoordinator(
          initialFrameKey: key('blank'),
          frameStore: store,
          sessionStore: BrushFrameEditSessionStore(
            canvasSize: canvas,
            tileSize: tileSize,
          ),
          historyPolicy: const BrushHistoryPolicy(),
        );

    test('a blank made behind the old wall is made again behind the new', () {
      final store = BrushFrameStore();
      final c = coordinator(store);
      expect(
        c.currentSurfaceOf(key('blank')).pasteboard,
        canvas.pasteboardAt(PasteboardReach.whole),
      );
      store.adoptPasteboardReach(PasteboardReach.quarter);
      expect(
        c.currentSurfaceOf(key('blank')).pasteboard,
        canvas.pasteboardAt(PasteboardReach.quarter),
      );
    });

    test('a drawn cel shows what the cut left', () {
      final store = BrushFrameStore();
      final c = coordinator(store);
      store.storeBakedSurface(key('drawn'), drawn());
      expect(c.currentSurfaceOf(key('drawn')).tileAt(pastLeft), isNotNull);
      store.adoptPasteboardReach(PasteboardReach.quarter);
      final now = c.currentSurfaceOf(key('drawn'));
      expect(now.pasteboardReach, PasteboardReach.quarter);
      expect(now.tileAt(pastLeft), isNull);
    });
  });

  // 🗣️Card a-thawed-cel-is-walled-again-on-the-ui-thread: kept bytes carry
  // no wall, so a kept cel a worker laid came back standing behind none
  // and was walled on the UI thread — every tile the wall crosses copied
  // again there, on every thaw. 🔬S5_BA off: 61 ms over 122 cels. A worker
  // lays it behind the wall now, and the store takes it as it came.
  group('a kept cel laid on a worker comes back behind the wall', () {
    setUp(() => debugWorkersRunHere = false);
    tearDown(() => debugWorkersRunHere = true);

    final cel = key('kept');

    /// Ink everywhere the wall decides on — a file's picture laid across
    /// the left of it, and a text's letters it crosses.
    BitmapSurface drawnWithLetters() =>
        drawn(
          laid: DirtyRegion(
            left: -6,
            top: 0,
            rightExclusive: 2,
            bottomExclusive: 4,
          ),
        ).copyWith(
          texts: [
            CelText(
              id: 1,
              content: CelTextContent(
                spans: const [
                  CelTextSpan(text: 'a', style: TextLetterStyle()),
                ],
                anchor: CanvasPoint(x: 0, y: 0),
              ),
              plate: {
                straddling: tile(70),
                pastRight: tile(80),
                inside: tile(90),
              },
            ),
          ],
        );

    void expectSamePicture(BitmapSurface? actual, BitmapSurface expected) {
      expect(actual, isNotNull);
      expect(actual!.pasteboardReach, expected.pasteboardReach);
      expect(actual.laidBounds, expected.laidBounds);
      void samePixels(
        Map<TileCoord, BitmapTile> tiles,
        Map<TileCoord, BitmapTile> expected,
      ) {
        expect(tiles.keys.toSet(), expected.keys.toSet());
        for (final MapEntry(key: coord, :value) in expected.entries) {
          expect(tiles[coord]!.pixels, value.pixels, reason: '$coord');
        }
      }

      samePixels(actual.tiles, expected.tiles);
      expect(actual.texts.length, expected.texts.length);
      for (final (index, text) in expected.texts.indexed) {
        expect(actual.texts[index].content, text.content);
        samePixels(actual.texts[index].plate, text.plate);
      }
    }

    for (final (tier, keep) in <(String, _KeepAll)>[
      (
        'parked cold',
        (store, cels) =>
            parkCold(store, cels, pasteboardReach: PasteboardReach.quarter),
      ),
      (
        'kept in a file',
        (store, cels) =>
            keepInAFile(store, cels, pasteboardReach: PasteboardReach.quarter),
      ),
    ]) {
      group(tier, () {
        BrushFrameStore kept() {
          final store = BrushFrameStore();
          keep(store, {cel: drawnWithLetters()});
          return store;
        }

        test('🚨thawed ahead: behind the wall a read here puts it behind, '
            'and walled here not at all', () async {
          final here = kept();
          final ahead = kept();
          final read = here.bakedSurfaceOrNull(cel);
          expect(here.celsWalledHere, 1, reason: 'premise: walled here');

          await ahead.thawAhead(cel, canvasSize: canvas);

          expect(ahead.celsWalledHere, 0, reason: 'laid behind it there');
          expectSamePicture(ahead.hotBakedSurfaceOrNull(cel), read!);
        });

        test('🚨cut ahead: the picture the undo keeps stands behind the wall '
            'it was kept at, and is laid back there walled here not at '
            'all', () async {
          final store = kept();
          await store.cutCelsAhead(PasteboardReach.none);
          final was = store
              .adoptPasteboardReach(PasteboardReach.none)[cel]
              ?.picture;

          expectSamePicture(
            was,
            surfaceBehindReach(drawnWithLetters(), PasteboardReach.quarter),
          );
          final walled = store.celsWalledHere;
          store.adoptPasteboardReach(PasteboardReach.quarter);
          store.storeBakedSurface(cel, was!);
          expect(store.celsWalledHere, walled, reason: 'as the undo lays it');
        });
      });
    }
  });
}

/// How a test keeps [BitmapSurface] as a cel of [BrushFrameStore] — one
/// tier of the three a cel can be kept in.
typedef _Keep = void Function(BrushFrameStore store, BitmapSurface surface);

/// How a test keeps every cel of [cels] in [BrushFrameStore] at once — in
/// the room, or in a file.
typedef _KeepAll =
    Object Function(
      BrushFrameStore store,
      Map<BrushFrameKey, BitmapSurface> cels,
    );

/// [cels] hot in [store] — drawn there, or laid back by an undo.
Object _keepHot(
  BrushFrameStore store,
  Map<BrushFrameKey, BitmapSurface> cels,
) {
  for (final MapEntry(:key, value: surface) in cels.entries) {
    store.storeBakedSurface(key, surface);
  }
  return cels;
}
