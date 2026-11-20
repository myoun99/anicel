import 'dart:io';
import 'dart:math';
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
import 'package:anicel/src/services/cel_looks.dart';
import 'package:anicel/src/services/persistence/thaw_in_worker.dart'
    show celThawTurns;

import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/cels_parked_cold.dart';
import '../helpers/shells_with_no_bytes.dart';

/// 🚨ONE THAW OF A CEL'S KEPT BYTES, WHOEVER ASKS FIRST (card
/// `the-first-stroke-after-a-file-opens-comes-late`, 2026-11-20): a use of
/// a kept cel takes what a look has in hand of it — hot as that very
/// surface, nothing read and nothing thawed again — and waits for a look
/// thawing it, as a look has waited for a use since 2026-11-15; a look is
/// handed what another holds. ↩️A use thawed its own whatever a look held:
/// a frame stood on as its file opens is looked at by the band's walk and
/// used by the canvas at once, and the cel's own tiles came to the engine
/// at the first stroke (🔬`BrushFrameStore._usedAsLooked` holds the
/// numbers).
///
/// That nothing is read again is read off the surface — the very one the
/// look was handed — and off a file taken away under it.
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
  late Map<BrushFrameKey, AnicelCelFileRef> refs;

  setUp(() {
    engine = ShellsWithNoBytes();
    store = BrushFrameStore(shells: engine);
    refs = keepInAFile(store, {key('f'): ink(4), key('g'): ink(5)});
  });

  Future<BitmapSurface> aLookAt(String frame) async =>
      (await store.lookAhead(key(frame), canvasSize: canvasSize))!;

  /// The looks let go of [looked], [frame]'s cel, as they do
  /// ([CelLooks.nextFrame]).
  void theLooksLetGo(String frame, BitmapSurface looked) => store.keepShellOf(
    key(frame),
    looked,
    canvasSize: canvasSize,
    revision: store.sourceRevisionOf(key(frame)),
  );

  /// The file [frame]'s cel is kept in, taken away: a read of it fails.
  void theFileGoes(String frame) =>
      File(refs[key(frame)]!.filePath).deleteSync();

  group('a use takes what a look holds', () {
    test('🚨a cel a look holds is used as what the look was handed — hot, '
        'its bytes here, the file read no more', () async {
      final looked = await aLookAt('f');
      expect(
        store.hotBakedSurfaceOrNull(key('f')),
        isNull,
        reason: '⛔premise: a look leaves the store as it found it',
      );
      theFileGoes('f');

      final used = store.bakedSurfaceOrNull(key('f'));

      expect(used, same(looked));
      expect(store.hotBakedSurfaceOrNull(key('f')), same(looked));
      expect(used!.tiles[origin]!.hasItsBytesHere, isTrue);
      expect(store.hotBakedBytes, greaterThan(0), reason: 'the cel weighs');
      expect(store.isCelFileBacked(key('f')), isTrue, reason: 'still clean');
    });

    test('a thaw ahead takes it too, before it returns: it waits for no '
        'worker', () async {
      final looked = await aLookAt('f');
      theFileGoes('f');

      final thawed = store.thawAhead(key('f'), canvasSize: canvasSize);

      expect(store.hotBakedSurfaceOrNull(key('f')), same(looked));
      await thawed;
    });

    test('and the read a canvas stands on', () async {
      final looked = await aLookAt('f');

      final stoodOn = store.currentSurfaceWithoutReplay(
        key('f'),
        canvasSize: canvasSize,
      );

      expect(stoodOn, same(looked));
    });

    test('what a read with no door before it read is in hand as well',
        () async {
      // ⚠️The file stays: a read on this thread keeps its handle open, and
      // an open file is not taken away on Windows.
      final looked = store.bakedSurfaceOrNull(key('f'), read: CelRead.look);

      expect(store.bakedSurfaceOrNull(key('f')), same(looked));
    });

    test('a parked cel\'s too, parked still as it is made hot', () async {
      parkCold(store, {key('a'): ink(1)});
      final looked = await aLookAt('a');

      final used = store.bakedSurfaceOrNull(key('a'));

      expect(used, same(looked));
      expect(store.isCelParked(key('a')), isTrue);
    });

    test('the shell the looks let go of comes first: the engine holds it '
        'whole, and no byte here weighs', () async {
      final first = await aLookAt('f');
      theLooksLetGo('f', first);
      final shell = engine.made.single;
      // Read with no door before it, which is handed no shell.
      final second = store.bakedSurfaceOrNull(key('f'), read: CelRead.look);
      expect(second, isNot(same(shell)), reason: '⛔premise: one more in hand');

      expect(store.bakedSurfaceOrNull(key('f')), same(shell));
    });
  });

  group('🚨a use and a look at once thaw the cel once', () {
    /// The most thaws under way at once until [asked] have all answered,
    /// read at every turn: a worker's job is done on this thread in a
    /// test (`debugWorkersRunHere`), turn by turn, so a second thaw begun
    /// a turn after the first is under way beside it. ⚠️Not read once the
    /// doors have given up their turns: by then the one thaw is over.
    Future<int> mostThawingAtOnce(List<Future<Object?>> asked) async {
      var most = 0;
      var answered = false;
      final all = Future.wait(asked).whenComplete(() => answered = true);
      for (var turn = 0; turn < 256 && !answered; turn++) {
        most = max(most, celThawTurns.running);
        await null;
      }
      await all;
      return most;
    }

    test('a use that comes as a look thaws it waits for the look, and '
        'takes what it read', () async {
      final look = store.lookAhead(key('f'), canvasSize: canvasSize);
      final use = store.thawAhead(key('f'), canvasSize: canvasSize);
      expect(await mostThawingAtOnce([look, use]), 1, reason: 'one thaw');

      final looked = await look;

      expect(store.hotBakedSurfaceOrNull(key('f')), same(looked));
    });

    test('a look that comes as a use thaws it waits for the use, and is '
        'handed the cel hot', () async {
      final use = store.thawAhead(key('f'), canvasSize: canvasSize);
      final look = store.lookAhead(key('f'), canvasSize: canvasSize);
      expect(await mostThawingAtOnce([look, use]), 1, reason: 'one thaw');

      expect(await look, same(store.hotBakedSurfaceOrNull(key('f'))));
    });

    test('a look that comes as a use waits for a look\'s thaw is handed '
        'the same cel', () async {
      final look = store.lookAhead(key('f'), canvasSize: canvasSize);
      final use = store.thawAhead(key('f'), canvasSize: canvasSize);
      final after = store.lookAhead(key('f'), canvasSize: canvasSize);

      await use;

      expect(await look, same(store.hotBakedSurfaceOrNull(key('f'))));
      expect(await after, same(store.hotBakedSurfaceOrNull(key('f'))));
    });

    test('two looks at once are one thaw, and a look after them is handed '
        'what they hold', () async {
      final both = await Future.wait([aLookAt('f'), aLookAt('f')]);
      theFileGoes('f');

      expect(both.last, same(both.first));
      expect(await aLookAt('f'), same(both.first));
      expect(
        store.bakedSurfaceOrNull(key('f'), read: CelRead.look),
        same(both.first),
      );
      expect(store.hotBakedSurfaceOrNull(key('f')), isNull);
    });
  });

  group('in a look\'s hand only while it is', () {
    test('🚨once the looks let go, a use takes no surface of theirs: the '
        'cel is thawed where the engine keeps no shell whole', () async {
      final looked = await aLookAt('f');
      theLooksLetGo('f', looked);
      engine.whole = false;

      final used = store.bakedSurfaceOrNull(key('f'))!;

      expect(used, isNot(same(looked)));
      expect(used.tiles[origin]!.pixels, pixelsOf(4));
    });

    test('a look let go by one of two that hold it is in hand no more',
        () async {
      final looked = await aLookAt('f');
      expect(await aLookAt('f'), same(looked), reason: '⛔premise: shared');
      theLooksLetGo('f', looked);
      engine.whole = false;

      expect(store.bakedSurfaceOrNull(key('f')), isNot(same(looked)));
    });

    test('a hold that lets go of a surface in hand no more leaves in hand '
        'what a look holds since', () async {
      final first = await aLookAt('f');
      theLooksLetGo('f', first);
      engine.whole = false;
      final second = await aLookAt('f');
      expect(second, isNot(same(first)), reason: '⛔premise: read anew');

      theLooksLetGo('f', first);

      expect(store.bakedSurfaceOrNull(key('f')), same(second));
    });

    test('🚨bytes kept anew are not what the look read: a use reads them',
        () async {
      final looked = await aLookAt('f');
      keepInAFile(store, {key('f'): ink(9)});

      final used = store.bakedSurfaceOrNull(key('f'))!;

      expect(used, isNot(same(looked)));
      expect(used.tiles[origin]!.pixels, pixelsOf(9));
    });

    test('a look of another cel is not this one\'s', () async {
      final looked = await aLookAt('g');

      final used = store.bakedSurfaceOrNull(key('f'))!;

      expect(used, isNot(same(looked)));
      expect(used.tiles[origin]!.pixels, pixelsOf(4));
    });

    test('a cel hot already is handed as it is, whatever a look held',
        () async {
      final hot = store.bakedSurfaceOrNull(key('f'));

      expect(await aLookAt('f'), same(hot));
      expect(store.bakedSurfaceOrNull(key('f')), same(hot));
    });
  });

  group('the looks of a film', () {
    late CelLooks looks;

    setUp(() => looks = CelLooks(store));

    test('🚨a frame stood on while the walk reads it is one surface: what '
        'the walk draws from is the cel a hand draws on', () async {
      final ahead = looks.ahead([key('f')], canvasSize: canvasSize);
      final stoodOn = store.thawAhead(key('f'), canvasSize: canvasSize);
      final read = await ahead;
      await stoodOn;

      final drawn = looks.surfaceOf(
        key('f'),
        canvasSize: canvasSize,
        ahead: read,
      );

      expect(drawn, same(store.hotBakedSurfaceOrNull(key('f'))));
      expect(looks.reads, 1);
    });

    test('and a cel the walk holds from the frame before, stood on then',
        () async {
      final first = looks.surfaceOf(key('f'), canvasSize: canvasSize);
      looks.nextFrame();
      await store.thawAhead(key('f'), canvasSize: canvasSize);

      final next = looks.surfaceOf(key('f'), canvasSize: canvasSize);

      expect(next, same(first));
      expect(store.hotBakedSurfaceOrNull(key('f')), same(first));
      expect(
        looks.bytesBesideTheStore(const []),
        0,
        reason: 'the store weighs it, hot',
      );
    });
  });
}
