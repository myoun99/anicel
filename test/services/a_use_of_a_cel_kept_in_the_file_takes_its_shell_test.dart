import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/scratch_file.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';

import '../helpers/a_room_that_refuses.dart';
import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/cels_parked_cold.dart';
import '../helpers/files_written_under.dart';
import '../helpers/shells_with_no_bytes.dart';

/// 🚨Card `cel-originals-are-held-twice-in-ram-and-on-the-gpu` ② (유저
/// 2026-11-19, Q1 「브러시가 맡고, 저장과 맞닿는 곳은 저장이 같이 정한다」 ·
/// Q3 「놓는다」): a cel the saved file holds, used — stood on, drawn on —
/// is the shell a look left of it (`BrushFrameStore.keepShellOf`): what the
/// engine holds, and no bytes here. ↩️It was thawed from the file as it was
/// made hot, its shell let go, and its tiles put on the engine again at the
/// first stroke (🔬the store's own note holds the numbers).
///
/// And what keeps them is held on in the run's room as the file's stop
/// being the cel's (🗣️유저 2026-11-21 on Q4, 「최대한 사본안만드는게
/// 중요」, and on Q6, 「사본이나 ram에있는걸 최대한 없애고싶어서」) — for
/// the tiles themselves, whoever holds them: none is handed a byte.
/// ↩️Till that day the bytes came here, into the tiles (②(3), 저장's
/// draft: 「셀을 처음 더럽히기 직전에 그 셀의 바이트를 다시 든다」); they
/// come so still where the room holds none.
///
/// Here a keeper whose shells hold no bytes: a tile of one reads what the
/// engine holds of it, or — its slot gone — its cel's kept bytes again.
void main() {
  const canvasSize = CanvasSize(
    width: defaultCelTileSize,
    height: defaultCelTileSize,
  );
  const cut = CutId('c');
  final origin = TileCoord(x: 0, y: 0);

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: cut,
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

  const tileBytes = defaultCelTileSize * defaultCelTileSize * 4;

  /// How many files lie in the run's room — under it, a store's cels
  /// lying in a folder of its own.
  int celsInTheRoom() =>
      filesWrittenUnder(Directory(SessionScratch.stagedFolder())).length;

  late ShellsWithNoBytes engine;
  late BrushFrameStore store;
  late Map<BrushFrameKey, AnicelCelFileRef> refs;

  setUp(() {
    engine = ShellsWithNoBytes();
    store = BrushFrameStore(shells: engine);
    refs = keepInAFile(store, {key('f'): ink(4), key('g'): ink(5)});
  });

  /// [frame]'s cel looked at, and let go as a look lets go of it: its
  /// shell, kept.
  Future<BitmapSurface> aShellOf(String frame) async {
    final looked = (await store.lookAhead(
      key(frame),
      canvasSize: canvasSize,
    ))!;
    store.keepShellOf(
      key(frame),
      looked,
      canvasSize: canvasSize,
      revision: store.sourceRevisionOf(key(frame)),
    );
    return engine.made.last;
  }

  /// [frame]'s cel used as its shell — the shell's one tile, which holds
  /// no bytes here.
  Future<BitmapTile> aTileTaken(String frame) async {
    final shell = await aShellOf(frame);
    expect(
      store.bakedSurfaceOrNull(key(frame)),
      same(shell),
      reason: '⛔premise: the use took the shell',
    );
    final tile = shell.tiles[origin]!;
    expect(tile.hasItsBytesHere, isFalse, reason: '⛔premise: no bytes here');
    return tile;
  }

  group('a use takes the shell', () {
    test('🚨a cel kept in the file is used as the shell a look left of it '
        '— hot, nothing thawed and nothing read', () async {
      final shell = await aShellOf('f');

      final used = store.bakedSurfaceOrNull(key('f'));

      expect(used, same(shell));
      expect(store.hotBakedSurfaceOrNull(key('f')), same(shell));
      expect(store.shells, isEmpty, reason: 'the cel\'s now, not the looks\'');
      expect(store.hotBakedBytes, 0, reason: 'no bytes of it are here');
      expect(engine.reads, 0);
      expect(store.isCelFileBacked(key('f')), isTrue, reason: 'still clean');
    });

    test('a thaw ahead takes it too, and waits for no worker', () async {
      final shell = await aShellOf('f');

      final thawed = store.thawAhead(key('f'), canvasSize: canvasSize);

      expect(store.hotBakedSurfaceOrNull(key('f')), same(shell));
      await thawed;
    });

    test('and the read a canvas stands on', () async {
      final shell = await aShellOf('f');

      final stoodOn = store.currentSurfaceWithoutReplay(
        key('f'),
        canvasSize: canvasSize,
      );

      expect(stoodOn, same(shell));
    });

    test('a look at the cel then is handed that shell, and keeps no other',
        () async {
      final shell = await aShellOf('f');
      store.bakedSurfaceOrNull(key('f'));

      final looked = await store.lookAhead(key('f'), canvasSize: canvasSize);
      store.keepShellOf(
        key('f'),
        looked!,
        canvasSize: canvasSize,
        revision: store.sourceRevisionOf(key('f')),
      );

      expect(looked, same(shell));
      expect(engine.made, hasLength(1));
    });

    test('a look alone takes nothing: the shell stays the looks\'', () async {
      final shell = await aShellOf('f');

      final looked = store.bakedSurfaceOrNull(
        key('f'),
        read: CelRead.look,
      );

      expect(looked, isNot(same(shell)));
      expect(store.hotBakedSurfaceOrNull(key('f')), isNull);
      expect(store.shells, [same(shell)]);
    });

    test('a shell some of whose slots the engine let go is not taken: the '
        'cel is thawed', () async {
      await aShellOf('f');
      engine.whole = false;

      final used = store.bakedSurfaceOrNull(key('f'))!;

      expect(used.tiles[origin]!.hasItsBytesHere, isTrue);
      expect(used.tiles[origin]!.pixels, pixelsOf(4));
    });

    test('a parked cel\'s too — its park is its still '
        '(a_cel_made_hot_keeps_its_park_test.dart)', () async {
      parkCold(store, {key('a'): ink(1)});
      final shell = await aShellOf('a');

      final used = store.bakedSurfaceOrNull(key('a'))!;

      expect(used, same(shell));
      expect(used.tiles[origin]!.hasItsBytesHere, isFalse);
      expect(store.isCelParked(key('a')), isTrue);
    });

    test('🚨a tile of the cel\'s shell whose slot went reads the file — '
        'never the hot shell that asks', () async {
      final tile = await aTileTaken('f');
      engine.slots = false;

      expect(tile.pixels, pixelsOf(4));
      expect(tile.hasItsBytesHere, isFalse, reason: 'a read keeps nothing');
      expect(engine.readsOfTheKept, 1);
    });

    test('a shell a use took, cooled, is the looks\' again', () async {
      final shell = await aShellOf('f');
      store.bakedSurfaceOrNull(key('f'));
      // Another, newer and with bytes here: the budget is over by it, and
      // the newest never cools.
      store.storeBakedSurface(key('h'), ink(7));

      store.hotCelByteBudget = 0;
      store.storeBakedSurface(key('h'), ink(8));
      await store.drainCooling();

      expect(store.hotBakedSurfaceOrNull(key('f')), isNull, reason: 'cooled');
      expect(store.shells, [same(shell)]);
      expect(
        await store.lookAhead(key('f'), canvasSize: canvasSize),
        same(shell),
      );
    });
  });

  group('🚨a hot shell the engine holds no more whole is hot no more', () {
    /// The engine lets go of every slot it held: a tile of a shell
    /// reads its cel's kept bytes again from here on.
    void theEngineLetsGo() => engine
      ..whole = false
      ..slots = false;

    test('a thaw ahead thaws it as it does any cel the file keeps — '
        'its bytes here, no tile of the shell read', () async {
      final shell = await aShellOf('f');
      store.bakedSurfaceOrNull(key('f'));
      theEngineLetsGo();

      await store.thawAhead(key('f'), canvasSize: canvasSize);

      final hot = store.hotBakedSurfaceOrNull(key('f'))!;
      expect(hot, isNot(same(shell)));
      expect(hot.tiles[origin]!.hasItsBytesHere, isTrue);
      expect(hot.tiles[origin]!.pixels, pixelsOf(4));
      expect(engine.reads, 0, reason: 'no tile of the shell was read');
      expect(store.shells, isEmpty, reason: 'a shell not whole is let go');
      expect(store.isCelFileBacked(key('f')), isTrue);
    });

    test('a look ahead reads it thawed, and the cel is hot no more', () async {
      final shell = await aShellOf('f');
      store.bakedSurfaceOrNull(key('f'));
      theEngineLetsGo();

      final looked = await store.lookAhead(
        key('f'),
        canvasSize: canvasSize,
      );

      expect(looked, isNot(same(shell)));
      expect(looked!.tiles[origin]!.pixels, pixelsOf(4));
      expect(engine.reads, 0, reason: 'no tile of the shell was read');
      expect(store.hotBakedSurfaceOrNull(key('f')), isNull);
      expect(store.isCelFileBacked(key('f')), isTrue);
    });

    test('one the engine holds whole stays hot through both', () async {
      final shell = await aShellOf('f');
      store.bakedSurfaceOrNull(key('f'));

      await store.thawAhead(key('f'), canvasSize: canvasSize);
      await store.lookAhead(key('f'), canvasSize: canvasSize);

      expect(store.hotBakedSurfaceOrNull(key('f')), same(shell));
    });

    test('a cel hot with its bytes here is no shell: it stays, whatever '
        'the engine let go of', () async {
      final thawed = store.bakedSurfaceOrNull(key('f'))!;
      expect(
        thawed.tiles[origin]!.hasItsBytesHere,
        isTrue,
        reason: '⛔premise: thawed, no shell to take',
      );
      theEngineLetsGo();

      await store.thawAhead(key('f'), canvasSize: canvasSize);
      await store.lookAhead(key('f'), canvasSize: canvasSize);

      expect(store.hotBakedSurfaceOrNull(key('f')), same(thawed));
    });

    test('a cel drawn on since is the file\'s no more, and stays', () async {
      final tile = await aTileTaken('f');
      // As a stroke on another tile leaves it: the tile the engine made
      // is still of the cel.
      store.storeBakedSurface(
        key('f'),
        BitmapSurface(
          canvasSize: canvasSize,
          tileSize: defaultCelTileSize,
          tiles: {origin: tile},
        ),
      );
      final drawn = store.hotBakedSurfaceOrNull(key('f'));
      expect(
        drawn!.tiles[origin],
        same(tile),
        reason: '⛔premise: a tile the engine made is of the cel still',
      );
      theEngineLetsGo();

      await store.thawAhead(key('f'), canvasSize: canvasSize);

      expect(store.hotBakedSurfaceOrNull(key('f')), same(drawn));
    });
  });

  group('🚨a hand going down has what keeps the cel held ahead, off this '
      'thread', () {
    /// How many pictures [edit] put behind the store's wall on this
    /// thread: the one it stores, and any it thawed here to do so —
    /// counted behind a wall that is not the whole pasteboard
    /// ([BrushFrameStore.celsWalledHere]), which [behindAWall] sets.
    int walledHereBy(void Function() edit) {
      final was = store.celsWalledHere;
      edit();
      return store.celsWalledHere - was;
    }

    void behindAWall() => refs = keepInAFile(
      store,
      {key('f'): ink(4)},
      pasteboardReach: PasteboardReach.quarter,
    );

    test('in the run\'s room, pressed as it is: the cel hot as it was, '
        'the file\'s still, and no byte here', () async {
      final tile = await aTileTaken('f');
      final weighed = store.hotBakedBytes;

      await store.holdOnAhead(key('f'));

      expect(tile.hasItsBytesHere, isFalse);
      expect(
        store.hotBakedSurfaceOrNull(key('f'))!.tiles[origin],
        same(tile),
      );
      expect(store.isCelFileBacked(key('f')), isTrue);
      expect(engine.reads, 0);
      expect(store.hotBakedBytes, weighed);
      expect(store.coldBakedBytes, refs[key('f')]!.length);
    });

    test('🚨the edit that follows reads no file on this thread, and '
        'thaws nothing', () async {
      behindAWall();
      final tile = await aTileTaken('f');
      await store.holdOnAhead(key('f'));
      File(refs[key('f')]!.filePath).deleteSync();

      final walled = walledHereBy(
        () => store.storeBakedSurface(key('f'), ink(9)),
      );

      expect(store.isCelFileBacked(key('f')), isFalse, reason: '⛔premise');
      expect(walled, 1, reason: 'the picture it stores, and no thaw');
      expect(tile.hasItsBytesHere, isFalse);
      expect(store.coldBakedBytes, refs[key('f')]!.length);
      engine.slots = false;
      expect(tile.pixels, pixelsOf(4), reason: 'what was held ahead');
    });

    test('an edit no press came before reads its stretch here, and '
        'thaws nothing', () async {
      behindAWall();
      final tile = await aTileTaken('f');

      expect(
        walledHereBy(() => store.storeBakedSurface(key('f'), ink(9))),
        1,
        reason: 'the picture it stores: no cel thawed for its tile',
      );
      expect(tile.hasItsBytesHere, isFalse);
      expect(store.keptBytesHeldOn, 1);
      engine.slots = false;
      expect(tile.pixels, pixelsOf(4), reason: 'held in the room');
    });

    test('asked again while it runs, it is the same holding', () async {
      await aTileTaken('f');

      final first = store.holdOnAhead(key('f'));
      final again = store.holdOnAhead(key('f'));

      expect(again, same(first));
      await first;
    });

    test('nothing is asked where no tile waits, nor where it is held '
        'ahead already', () async {
      await aShellOf('g');
      await store.holdOnAhead(key('g'));
      expect(store.coldBakedBytes, 0, reason: 'a cel never taken');

      await aTileTaken('f');
      await store.holdOnAhead(key('f'));
      final held = store.coldBakedBytes;
      File(refs[key('f')]!.filePath).deleteSync();
      await store.holdOnAhead(key('f'));
      expect(store.coldBakedBytes, held, reason: 'held once');
      expect(
        store.holdOnAhead(key('f')),
        isNot(same(store.holdOnAhead(key('f')))),
        reason: 'no holding runs, to be joined by the next asking',
      );
    });

    test('🚨an edit landing while it is written holds the stretch itself, '
        'and what was written ahead goes', () async {
      final tile = await aTileTaken('f');
      final room = celsInTheRoom();

      final ahead = store.holdOnAhead(key('f'));
      // Each turn of the microtasks till the room has what it wrote: the
      // edit lands before it hears the write has ended.
      for (var turns = 0; celsInTheRoom() == room; turns += 1) {
        expect(turns, lessThan(200), reason: '⛔premise: it writes');
        await null;
      }
      store.storeBakedSurface(key('f'), ink(9));
      await ahead;
      await ScratchFile.lettingGo;

      expect(store.keptBytesHeldOn, 1);
      expect(store.coldBakedBytes, refs[key('f')]!.length);
      expect(celsInTheRoom(), room + 1, reason: 'one file of it');
      engine.slots = false;
      expect(tile.pixels, pixelsOf(4));
    });

    test('where the file will not read, the tiles wait on — and are '
        'read where the engine holds them as the edit lands', () async {
      final tile = await aTileTaken('f');
      File(refs[key('f')]!.filePath).deleteSync();

      await store.holdOnAhead(key('f'));
      expect(tile.hasItsBytesHere, isFalse);
      expect(store.coldBakedBytes, 0);
      store.storeBakedSurface(key('f'), ink(9));

      expect(tile.pixels, pixelsOf(4));
      expect(engine.readsOfASlot, 1);
      expect(store.keptBytesHeldOn, 0);
    });

    test('what was held ahead goes where the edit holds nothing on: no '
        'tile waits by then', () async {
      final tile = await aTileTaken('f');
      final room = celsInTheRoom();
      await store.holdOnAhead(key('f'));
      expect(celsInTheRoom(), room + 1, reason: '⛔premise: held ahead');
      tile.readPixels((_, pixels) => tile.keepBytesHere(pixels));

      store.storeBakedSurface(key('f'), ink(9));
      await ScratchFile.lettingGo;

      expect(store.keptBytesHeldOn, 0);
      expect(store.coldBakedBytes, 0);
      expect(celsInTheRoom(), room);
    });

    test('🚨a tile nothing holds the bytes of — its file gone and no '
        'slot of it as the edit lands — is refused: ⛔not read as what '
        'its cel is kept as after', () async {
      final tile = await aTileTaken('f');
      File(refs[key('f')]!.filePath).deleteSync();
      engine.slots = false;
      store.storeBakedSurface(key('f'), ink(9));
      expect(tile.hasItsBytesHere, isFalse, reason: '⛔premise: none to hand');
      expect(store.keptBytesHeldOn, 0, reason: '⛔premise: none held');
      // Kept anew, as a save keeps it.
      final snapshot = store.bakedSnapshotForSave();
      final saved = keepInAFile(
        BrushFrameStore(shells: ShellsWithNoBytes()),
        {key('f'): ink(9)},
      )[key('f')]!;
      store.adoptSavedFile({
        key('f'): saved,
      }, dirtyTicksAtSnapshot: snapshot.dirtyTicks);
      expect(store.isCelFileBacked(key('f')), isTrue, reason: '⛔premise');

      expect(() => tile.pixels, throwsStateError);
    });

    test('what was held ahead goes as the engine\'s tiles rest, no edit '
        'having come — and stays for a cel a canvas stands on', () async {
      await aTileTaken('f');
      await store.holdOnAhead(key('f'));
      store.setCelsStoodOn(() => [key('f')]);

      store.letGoOfBytesTheEngineHolds();
      expect(
        store.coldBakedBytes,
        refs[key('f')]!.length,
        reason: 'stood on: a pen may be down',
      );

      store.setCelsStoodOn(null);
      store.letGoOfBytesTheEngineHolds();
      expect(store.coldBakedBytes, 0);
    });

    // As a tile with no slot on the engine keeps them, where the rest of
    // its cel became a shell (`EngineTileLedger.shellOf`).
    void bytesHere(BitmapTile tile) =>
        tile.readPixels((_, pixels) => tile.keepBytesHere(pixels));

    test('a shell with bytes here, cooled, is no shell of the looks\': '
        'a shell holds none', () async {
      bytesHere(await aTileTaken('f'));
      store.storeBakedSurface(key('h'), ink(7));

      store.hotCelByteBudget = 0;
      store.storeBakedSurface(key('h'), ink(8));
      await store.drainCooling();

      expect(store.hotBakedSurfaceOrNull(key('f')), isNull, reason: 'cooled');
      expect(store.shells, isEmpty);
    });

    test('and its tile is struck off as the cel is taken again: only '
        'what waits is written down', () async {
      final tile = await aTileTaken('f');
      bytesHere(tile);
      store.storeBakedSurface(key('h'), ink(7));
      store.hotCelByteBudget = 0;
      store.storeBakedSurface(key('h'), ink(8));
      await store.drainCooling();
      store.hotCelByteBudget = 1 << 30;

      final again = await aTileTaken('f');

      expect(again, isNot(same(tile)), reason: '⛔premise: a new shell');
      expect(tile.hasItsBytesHere, isTrue, reason: '⛔premise: and held');
      expect(store.tilesWrittenDown, 1);
    });
  });

  group('🚨what keeps the tiles is held on in the room as the file ref '
      'goes', () {
    test('🚨for each tile once, however often its cel cooled and was '
        'used again', () async {
      final tile = await aTileTaken('f');
      store.storeBakedSurface(key('h'), ink(7));
      store.hotCelByteBudget = 0;
      store.storeBakedSurface(key('h'), ink(8));
      await store.drainCooling();
      expect(
        store.hotBakedSurfaceOrNull(key('f')),
        isNull,
        reason: '⛔premise: cooled',
      );
      store.hotCelByteBudget = 1 << 30;
      store.bakedSurfaceOrNull(key('f'));
      expect(
        store.hotBakedSurfaceOrNull(key('f'))!.tiles[origin],
        same(tile),
        reason: '⛔premise: the same shell, used again',
      );
      expect(store.tilesWrittenDown, 1);
      final room = store.coldBakedBytes;

      store.storeBakedSurface(key('f'), ink(9));

      expect(tile.hasItsBytesHere, isFalse);
      expect(store.keptBytesHeldOn, 1);
      expect(store.coldBakedBytes, room + refs[key('f')]!.length);
      engine.slots = false;
      expect(tile.pixels, pixelsOf(4));
    });

    test('as the cel is drawn on — its stretch written to the room as it '
        'is: nothing thawed, no slot read, no byte here', () async {
      final tile = await aTileTaken('f');
      final weighed = store.hotBakedBytes;

      store.storeBakedSurface(key('f'), ink(9));

      expect(store.isCelFileBacked(key('f')), isFalse, reason: '⛔premise');
      expect(tile.hasItsBytesHere, isFalse);
      expect(engine.reads, 0);
      expect(
        store.hotBakedBytes,
        weighed + tileBytes,
        reason: 'the picture drawn, and no tile of the cel it was',
      );
      expect(store.coldBakedBytes, refs[key('f')]!.length);
      engine.slots = false;
      expect(tile.pixels, pixelsOf(4), reason: 'read in the room');
      expect(tile.hasItsBytesHere, isFalse, reason: 'and kept nowhere here');
    });

    test('and a step back over it lays the shell back, read where it is '
        'held', () async {
      final tile = await aTileTaken('f');
      final shell = store.hotBakedSurfaceOrNull(key('f'))!;
      store.storeBakedSurface(key('f'), ink(9));

      store.storeBakedSurface(key('f'), shell);
      engine.slots = false;

      expect(store.bakedSurfaceOrNull(key('f')), same(shell));
      expect(tile.pixels, pixelsOf(4));
      expect(tile.hasItsBytesHere, isFalse);
    });

    final ways = <String, _Way>{
      'the cel is emptied': (store, f) => store.storeBakedSurface(
        f,
        BitmapSurface(canvasSize: canvasSize, tileSize: defaultCelTileSize),
      ),
      'its cut is moved': (store, f) => store.adoptCutCanvasSize(
        cutId: cut,
        canvasSize: canvasSize,
        dx: 3,
      ),
      'its cut is laid on another size': (store, f) =>
          store.resizeBakedSurfaces(
            const CanvasSize(
              width: 2 * defaultCelTileSize,
              height: defaultCelTileSize,
            ),
            cutId: cut,
          ),
      'its cut is restored': (store, f) =>
          store.restoreBakedForCut(cut, {f: ink(9)}),
      'its file is lost': (store, f) =>
          store.forgetCelsLostWithTheirFile([f]),
    };
    for (final MapEntry(key: way, value: does) in ways.entries) {
      test('as $way', () async {
        final tile = await aTileTaken('f');

        does(store, key('f'));

        expect(store.isCelFileBacked(key('f')), isFalse, reason: '⛔premise');
        expect(tile.hasItsBytesHere, isFalse);
        expect(store.keptBytesHeldOn, 1);
        engine.slots = false;
        expect(tile.pixels, pixelsOf(4));
      });
    }

    test('as another is copied onto it: the file ref it keeps from there '
        'on is the one the other has', () async {
      final tile = await aTileTaken('f');

      store.copyCel(key('g'), key('f'));

      expect(
        store.bakedSurfaceOrNull(key('f'))!.tiles[origin]!.pixels,
        pixelsOf(5),
        reason: '⛔premise: the copy',
      );
      expect(tile.hasItsBytesHere, isFalse);
      engine.slots = false;
      expect(tile.pixels, pixelsOf(4));
    });

    test('a cel renamed keeps its file ref and its tiles written down: '
        'they read it by its new name, and are held for as the cel under '
        'that name is drawn on', () async {
      final tile = await aTileTaken('f');

      store.rekeyFrames([(key('f'), key('x'))]);
      expect(tile.hasItsBytesHere, isFalse, reason: 'kept where it was');
      expect(store.isCelFileBacked(key('x')), isTrue, reason: '⛔premise');
      engine.slots = false;
      expect(tile.pixels, pixelsOf(4), reason: 'by its new name');
      engine.slots = true;
      store.storeBakedSurface(key('x'), ink(9));

      expect(tile.hasItsBytesHere, isFalse);
      expect(store.keptBytesHeldOn, 1);
      engine.slots = false;
      expect(tile.pixels, pixelsOf(4));
    });

    test('🚨where the room will hold none, the bytes come into the tiles '
        'themselves — read from the file once, not from the engine', () async {
      final tile = await aTileTaken('f');
      refuseTheRoom();

      store.storeBakedSurface(key('f'), ink(9));

      expect(store.keptBytesHeldOn, 0);
      expect(tile.hasItsBytesHere, isTrue);
      expect(tile.pixels, pixelsOf(4));
      expect(engine.reads, 0, reason: 'the file\'s, not a slot\'s');
    });

    test('where the file will not read, each is read where the engine holds '
        'it', () async {
      final tile = await aTileTaken('f');
      File(refs[key('f')]!.filePath).deleteSync();

      store.storeBakedSurface(key('f'), ink(9));

      expect(tile.hasItsBytesHere, isTrue);
      expect(tile.pixels, pixelsOf(4));
      expect(engine.readsOfASlot, 1);
    });

    test('and one neither holds stays as it is, the edit going on', () async {
      final tile = await aTileTaken('f');
      File(refs[key('f')]!.filePath).deleteSync();
      engine.slots = false;

      store.storeBakedSurface(key('f'), ink(9));

      expect(tile.hasItsBytesHere, isFalse);
      expect(
        store.bakedSurfaceOrNull(key('f'))!.tiles[origin]!.pixels,
        pixelsOf(9),
      );
    });

    test('a tile nobody holds is asked for nothing', () async {
      await aShellOf('f');
      store.bakedSurfaceOrNull(key('f'));

      store.dispose();

      expect(engine.reads, 0);
    });

    test('🧱every removal of a file ref is the one door\'s, or the move\'s '
        'beside it', () {
      final source = File(
        'lib/src/services/brush_frame_store.dart',
      ).readAsStringSync();
      final removals = RegExp(
        r'_fileCels\s*\.\s*remove\(',
      ).allMatches(source);
      final doors = [
        source.indexOf('AnicelCelFileRef? _letTheFileRefGo('),
        source.indexOf('bool _keptMoves('),
        source.indexOf('BitmapSurface? _asKept('),
      ];

      expect(doors, isNot(contains(-1)), reason: '⛔premise: the doors stand');
      expect(removals, hasLength(2));
      for (final removal in removals) {
        expect(
          removal.start,
          inExclusiveRange(doors.first, doors.last),
          reason: 'a ref removed anywhere else leaves its tiles unread',
        );
      }
    });
  });
}

/// What makes a cel's file ref go, done to [store]'s cel [f].
typedef _Way = void Function(BrushFrameStore store, BrushFrameKey f);
