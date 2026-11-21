import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';

import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/cels_parked_cold.dart';
import '../helpers/shells_with_no_bytes.dart';

/// 🚨Card `cel-originals-are-held-twice-in-ram-and-on-the-gpu` (유저
/// 2026-11-19 on Q3 「놓는다」 · 2026-11-21 on Q4 「최대한 사본안만드는게
/// 중요」 and on Q6 「사본이나 ram에있는걸 최대한 없애고싶어서」): a cel
/// that is kept — in the saved file, or parked in the run's room —, made
/// hot by a use that found no shell — a frame a screen stood on before any
/// look made it — holds its bytes here only till the engine's tiles rest.
/// Then its tiles are laid on the engine and it is its shell
/// (`BrushFrameStore.letGoOfBytesTheEngineHolds`): hot as it was, the
/// engine's tiles and no bytes here, as a use that took a shell a look left
/// is from the start
/// (a_use_of_a_cel_kept_in_the_file_takes_its_shell_test.dart). ↩️It kept
/// them for as long as it was hot — and, till 2026-11-21, through every
/// rest where a canvas stood on it or the engine held no tile of it.
///
/// A rest is asked for as such bytes come here: a thaw, a park or a save
/// stores no tile on the engine, which is what else brings one.
///
/// When the engine's tiles rest is the ledger's
/// (the_ledger_folds_its_tiles_once_the_hand_rests_test.dart), and what a
/// project says it stands on its session's
/// (a_session_lets_go_of_bytes_as_the_engine_s_tiles_rest_test.dart). That
/// a parked cel made hot is parked still is
/// a_cel_made_hot_keeps_its_park_test.dart's, and what an edit of such a
/// shell holds on to for the tiles it left
/// an_edited_cel_reads_what_it_was_kept_as_test.dart's.
///
/// Here a keeper whose shells hold no bytes: a tile of one reads what the
/// engine holds of it, or — its slot gone — its cel's kept bytes again.
void main() {
  const canvasSize = CanvasSize(
    width: defaultCelTileSize,
    height: defaultCelTileSize,
  );
  final origin = TileCoord(x: 0, y: 0);

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  /// A cel of one tile, drawn on: not of one colour, so its bytes weigh.
  BitmapSurface ink(int seed) {
    final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = (seed * 20 + i ~/ 4) % 251;
      pixels[i + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: defaultCelTileSize,
      tiles: {origin: BitmapTile(size: defaultCelTileSize, pixels: pixels)},
    );
  }

  Uint8List pixelsOf(int seed) => ink(seed).tiles[origin]!.pixels;

  late ShellsWithNoBytes engine;
  late BrushFrameStore store;

  /// [frame]'s cel used with no shell to take: thawed, its bytes here.
  BitmapSurface used(String frame) {
    final thawed = store.bakedSurfaceOrNull(key(frame))!;
    expect(
      thawed.tiles[origin]!.hasItsBytesHere,
      isTrue,
      reason: '⛔premise: thawed, its bytes here',
    );
    return thawed;
  }

  /// Each law, of a cel kept either way.
  final kept = <String, void Function()>{
    'the saved file keeps': () => keepInAFile(store, {
      key('f'): ink(4),
      key('g'): ink(5),
    }),
    'the run\'s room keeps, parked': () => parkCold(store, {
      key('f'): ink(4),
      key('g'): ink(5),
    }),
  };

  for (final MapEntry(key: how, value: keep) in kept.entries) {
    group('a cel $how —', () {
      setUp(() {
        engine = ShellsWithNoBytes();
        store = BrushFrameStore(shells: engine);
        keep();
      });

      test('🚨at a rest, hot, it is its shell — no bytes of it here, '
          'nothing read, and kept where it was', () {
        final thawed = used('f');
        expect(store.hotBakedBytes, greaterThan(0), reason: '⛔premise');
        final keptAs = store.bakedSnapshotForSave();

        store.letGoOfBytesTheEngineHolds();

        final hot = store.hotBakedSurfaceOrNull(key('f'))!;
        expect(hot, same(engine.made.single));
        expect(hot, isNot(same(thawed)));
        expect(hot.tiles[origin]!.hasItsBytesHere, isFalse);
        expect(store.hotBakedBytes, 0);
        expect(engine.reads, 0);
        final now = store.bakedSnapshotForSave();
        expect(now.cold[key('f')], same(keptAs.cold[key('f')]));
        expect(now.fileRefs[key('f')], same(keptAs.fileRefs[key('f')]));
        expect(
          now.cold[key('f')] ?? now.fileRefs[key('f')],
          isNotNull,
          reason: 'kept still',
        );
        expect(store.shells, isEmpty, reason: 'the cel\'s, not the looks\'');
        expect(hot.tiles[origin]!.pixels, pixelsOf(4));
        expect(engine.laid.single.surface, same(thawed));
        expect(engine.laid.single.cel, key('f').cel);
      });

      test('🚨what its screens are drawn from is the shell too: nothing '
          'here holds the bytes it let go', () {
        final thawed = used('f');
        expect(
          store.validPreviewSurfaceOrNull(key('f')),
          same(thawed),
          reason: '⛔premise: a use seeds what the cel is shown from',
        );

        store.letGoOfBytesTheEngineHolds();

        expect(
          store.validPreviewSurfaceOrNull(key('f')),
          same(store.hotBakedSurfaceOrNull(key('f'))),
        );
      });

      test('a rest after makes no shell more, and a use then takes the '
          'same', () {
        used('f');
        store.letGoOfBytesTheEngineHolds();
        final shell = store.hotBakedSurfaceOrNull(key('f'));

        store.letGoOfBytesTheEngineHolds();

        expect(engine.made, hasLength(1));
        expect(engine.laid, hasLength(1), reason: 'no bytes of it to lay');
        expect(store.bakedSurfaceOrNull(key('f')), same(shell));
      });

      test('🚨an edit holds on to what kept its tiles: whoever holds one '
          'reads its pixels still, once what kept them is the cel\'s no '
          'more — and no byte of it comes here', () async {
        used('f');
        store.letGoOfBytesTheEngineHolds();
        final tile = store.hotBakedSurfaceOrNull(key('f'))!.tiles[origin]!;
        expect(store.tilesWrittenDown, 1);
        // The engine holds it no more: its bytes are the kept ones alone.
        engine.slots = false;

        store.storeBakedSurface(key('f'), ink(9));

        expect(tile.hasItsBytesHere, isFalse);
        expect(store.keptBytesHeldOn, 1);
        expect(tile.pixels, pixelsOf(4));
        expect(store.isCelFileBacked(key('f')), isFalse);
        expect(store.isCelParked(key('f')), isFalse);
      });

      test('🚨a cel a canvas stands on is its shell at the rest as any '
          'other', () {
        used('f');
        used('g');
        store.setCelsStoodOn(() => [key('f')]);

        store.letGoOfBytesTheEngineHolds();

        expect(store.hotBakedBytes, 0);
        for (final frame in ['f', 'g']) {
          expect(
            store
                .hotBakedSurfaceOrNull(key(frame))!
                .tiles[origin]!
                .hasItsBytesHere,
            isFalse,
            reason: frame,
          );
        }
      });

      test('a rest is no use of it: the cel keeps its place in the line, '
          'ahead of one used after it', () async {
        used('f');
        store.storeBakedSurface(key('h'), ink(9));
        final last = store.hotBakedSurfaceOrNull(key('h'));
        store.letGoOfBytesTheEngineHolds();
        expect(
          store.hotBakedBytes,
          greaterThan(0),
          reason: '⛔premise: the bytes of the cel drawn, the only ones',
        );

        // Over its budget by the cel drawn: the line lets go from its
        // head, and never of the last used.
        store.hotCelByteBudget = 0;
        store.coolToBudget();
        await store.drainCooling();

        expect(store.hotBakedSurfaceOrNull(key('h')), same(last));
        expect(store.hotBakedSurfaceOrNull(key('f')), isNull);
      });

      test('🚨a cel the engine held no tile of is laid there at the rest, '
          'and is its shell', () {
        final thawed = used('f');
        engine.holds = false;

        store.letGoOfBytesTheEngineHolds();

        expect(engine.laid.single.surface, same(thawed));
        expect(
          store.hotBakedSurfaceOrNull(key('f')),
          same(engine.made.single),
        );
        expect(store.hotBakedBytes, 0);
      });

      test('one the engine has no room for stays as it is, and is laid '
          'again at the rest after', () {
        final thawed = used('f');
        engine
          ..holds = false
          ..takes = false;

        store.letGoOfBytesTheEngineHolds();

        expect(store.hotBakedSurfaceOrNull(key('f')), same(thawed));
        expect(store.tilesWrittenDown, 0);

        engine.takes = true;
        store.letGoOfBytesTheEngineHolds();

        expect(engine.laid, hasLength(2));
        expect(store.hotBakedBytes, 0);
      });

      test('a cel drawn — kept no more — keeps its bytes: they are the '
          'only ones, and nothing of it is laid', () {
        store.storeBakedSurface(key('f'), ink(9));
        final drawn = store.hotBakedSurfaceOrNull(key('f'));

        store.letGoOfBytesTheEngineHolds();

        expect(store.hotBakedSurfaceOrNull(key('f')), same(drawn));
        expect(engine.made, isEmpty);
        expect(engine.laid, isEmpty);
      });

      test('🚨a use that thaws it asks for a rest — it stores no tile on '
          'the engine, which is what else brings one', () {
        final asked = engine.restsAsked;

        used('f');

        expect(engine.restsAsked, asked + 1);
      });
    });
  }

  group('a save\'s file that comes to keep a cel —', () {
    setUp(() {
      engine = ShellsWithNoBytes()..holds = false;
      store = BrushFrameStore(shells: engine);
    });

    /// [frame]'s cel kept anew as a save keeps it: a stretch of a file
    /// holding [seed]'s picture, adopted.
    void savedAs(String frame, int seed) {
      final snapshot = store.bakedSnapshotForSave();
      final saved = keepInAFile(BrushFrameStore(shells: ShellsWithNoBytes()), {
        key(frame): ink(seed),
      })[key(frame)]!;
      store.adoptSavedFile({
        key(frame): saved,
      }, dirtyTicksAtSnapshot: snapshot.dirtyTicks);
      expect(store.isCelFileBacked(key(frame)), isTrue, reason: '⛔premise');
    }

    test('🚨hot, its bytes here: a rest is asked for, and takes them — '
        'they are the file\'s too from there', () {
      store.storeBakedSurface(key('h'), ink(9));
      final drawn = store.hotBakedSurfaceOrNull(key('h'));
      final asked = engine.restsAsked;

      savedAs('h', 9);

      expect(engine.restsAsked, asked + 1);
      expect(
        store.hotBakedSurfaceOrNull(key('h')),
        same(drawn),
        reason: 'till the rest',
      );

      store.letGoOfBytesTheEngineHolds();

      expect(engine.laid.single.surface, same(drawn));
      expect(store.hotBakedBytes, 0);
      expect(
        store.hotBakedSurfaceOrNull(key('h'))!.tiles[origin]!.pixels,
        pixelsOf(9),
      );
    });

    test('hot nowhere: no rest is asked for', () {
      parkCold(store, {key('f'): ink(4)});
      final asked = engine.restsAsked;

      savedAs('f', 4);

      expect(engine.restsAsked, asked);
    });
  });
}
