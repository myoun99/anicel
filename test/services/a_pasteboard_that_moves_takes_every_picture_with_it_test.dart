import 'dart:typed_data';

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
import 'package:anicel/src/services/commands/set_project_pasteboard_command.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/cels_parked_cold.dart';

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
      expect(identical(taken[cut], before), isTrue);
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

    test('a parked payload still lays every pixel back', () async {
      final before = drawn();
      final f = fixture((store) => store.storeBakedSurface(cut, before));
      final command = SetProjectPasteboardCommand(
        repository: f.repository,
        brushFrameStore: f.store,
        size: PasteboardSize.two,
      )..execute();
      expect(await command.parkPayload(), isTrue);
      command.undo();
      expectWhole(f.store.bakedSurfaceOrNull(cut), before);
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
}

/// How a test keeps [BitmapSurface] as a cel of [BrushFrameStore] — one
/// tier of the three a cel can be kept in.
typedef _Keep = void Function(BrushFrameStore store, BitmapSurface surface);
