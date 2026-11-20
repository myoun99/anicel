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
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/scratch_file.dart';

import '../helpers/cels_parked_cold.dart';
import '../helpers/shells_with_no_bytes.dart';

/// 🚨Card `cel-originals-are-held-twice-in-ram-and-on-the-gpu`, Q6 (유저
/// 2026-11-21 04:28, 「disk 임시 방에 미리 내려 둔다 — 형식 불문」:
/// 「아무튼 사본이나 ram에있는걸 최대한 없애고싶어서」): a cel parked in
/// the run's room and made hot is parked STILL — its park is its bytes till
/// an edit ends it, as a stretch of the saved file is. So a cooling of it
/// writes nothing, a use of it may hold no byte here (its shell,
/// a_hot_cel_that_is_kept_lets_its_bytes_go_at_a_rest_test.dart), and a
/// save writes the park through.
///
/// ↩️Till then a park was let go as its cel was made hot
/// (`BrushFrameStore._keepThawed`): every parked cel a screen stood on was
/// the RAM's alone again, and pressed and written anew to leave it.
///
/// 🚨And so every door a hot cel's pixels change by ends its park
/// (`BrushFrameStore._letTheKeptGo`): a park that outlived its cel's
/// pixels would be read back as the cel, and written by the next save.
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

  late ShellsWithNoBytes engine;
  late BrushFrameStore store;

  setUp(() {
    engine = ShellsWithNoBytes();
    store = BrushFrameStore(shells: engine);
    parkCold(store, {key('f'): ink(4), key('g'): ink(5)});
  });

  AnicelCelFileRef? parkOf(String frame) =>
      store.bakedSnapshotForSave().cold[key(frame)];

  /// [frame]'s cel made hot by a use, its park where it was.
  ({BitmapSurface hot, AnicelCelFileRef park}) usedParked(String frame) {
    final park = parkOf(frame)!;
    final hot = store.bakedSurfaceOrNull(key(frame))!;
    expect(parkOf(frame), same(park), reason: '⛔premise: parked still');
    return (hot: hot, park: park);
  }

  Future<bool> gone(AnicelCelFileRef park) async {
    await ScratchFile.lettingGo;
    return !File(park.filePath).existsSync();
  }

  group('made hot, a parked cel is parked still', () {
    test('🚨a use of it lets go of nothing: the same park, its file in '
        'the room, and nothing more parked', () {
      final park = parkOf('f')!;
      final parkedBytes = store.coldBakedBytes;

      final hot = store.bakedSurfaceOrNull(key('f'))!;

      expect(hot.tiles[origin]!.pixels, pixelsOf(4));
      expect(store.hotBakedSurfaceOrNull(key('f')), same(hot));
      expect(store.isCelCold(key('f')), isTrue);
      expect(parkOf('f'), same(park));
      expect(File(park.filePath).existsSync(), isTrue);
      expect(store.coldBakedBytes, parkedBytes);
    });

    test('🚨a thaw made ahead keeps it too', () async {
      final park = parkOf('f')!;

      await store.thawAhead(key('f'), canvasSize: canvasSize);

      expect(store.hotBakedSurfaceOrNull(key('f')), isNotNull);
      expect(parkOf('f'), same(park));
    });

    test('🚨a cooling of it is for nothing: no byte pressed, no file '
        'written — the park it had', () async {
      final (hot: _, :park) = usedParked('f');
      usedParked('g');
      final parkedBytes = store.coldBakedBytes;

      store.hotCelByteBudget = 0;
      store.coolToBudget();
      await store.drainCooling();

      expect(store.hotBakedSurfaceOrNull(key('f')), isNull);
      expect(parkOf('f'), same(park));
      expect(store.coldBakedBytes, parkedBytes);
      expect(
        store.bakedSurfaceOrNull(key('f'))!.tiles[origin]!.pixels,
        pixelsOf(4),
      );
    });

    test('🚨a use of it takes the shell a look left, as a cel the file '
        'keeps does — hot, no bytes here, nothing thawed', () async {
      final looked = (await store.lookAhead(
        key('f'),
        canvasSize: canvasSize,
      ))!;
      store.keepShellOf(
        key('f'),
        looked,
        canvasSize: canvasSize,
        revision: store.sourceRevisionOf(key('f')),
      );
      final shell = engine.made.single;
      final park = parkOf('f')!;

      final used = store.bakedSurfaceOrNull(key('f'));

      expect(used, same(shell));
      expect(store.hotBakedBytes, 0);
      expect(parkOf('f'), same(park));
      expect(store.shells, isEmpty, reason: 'the cel\'s now, not the looks\'');
    });
  });

  group('🚨the save is handed a hot cel with a park as its park alone', () {
    test('not as a hot cel to press again', () {
      final (hot: _, :park) = usedParked('f');

      final snapshot = store.bakedSnapshotForSave();

      expect(snapshot.hot.containsKey(key('f')), isFalse);
      expect(snapshot.cold[key('f')], same(park));
    });

    test('hot too where its park\'s file is gone from the room: the '
        'picture is here still', () {
      final (:hot, :park) = usedParked('f');
      File(park.filePath).deleteSync();

      final snapshot = store.bakedSnapshotForSave();

      expect(snapshot.hot[key('f')], same(hot));
    });

    test('and a hot cel with none as hot', () {
      store.storeBakedSurface(key('h'), ink(7));

      final snapshot = store.bakedSnapshotForSave();

      expect(snapshot.hot.containsKey(key('h')), isTrue);
      expect(snapshot.cold.containsKey(key('h')), isFalse);
    });
  });

  group('🚨every door a hot cel\'s pixels change by ends its park', () {
    /// What changes the pixels of [f], hot with its park, in [store].
    final doors = <String, void Function()>{
      'a picture stored over it': () =>
          store.storeBakedSurface(key('f'), ink(9)),
      'the cel emptied': () => store.storeBakedSurface(
        key('f'),
        BitmapSurface(canvasSize: canvasSize, tileSize: defaultCelTileSize),
      ),
      'its cut\'s canvas resized': () => store.resizeBakedSurfaces(
        const CanvasSize(
          width: defaultCelTileSize * 2,
          height: defaultCelTileSize,
        ),
        cutId: cut,
      ),
      'its cut\'s canvas resized by an anchor': () => store.adoptCutCanvasSize(
        cutId: cut,
        canvasSize: const CanvasSize(
          width: defaultCelTileSize * 2,
          height: defaultCelTileSize,
        ),
        dx: defaultCelTileSize.toDouble(),
      ),
      'its cut\'s cels laid back by an undo': () =>
          store.restoreBakedForCut(cut, {key('f'): ink(9)}),
    };

    for (final MapEntry(key: how, value: door) in doors.entries) {
      test('$how: the park is the cel\'s no more, and its file goes',
          () async {
        final (hot: _, :park) = usedParked('f');

        door();

        expect(parkOf('f'), isNot(same(park)));
        expect(await gone(park), isTrue);
        // What is kept of it now, if anything, is what it shows now.
        final shown = store.hotBakedSurfaceOrNull(key('f'));
        if (shown != null) {
          expect(store.isCelCold(key('f')), isFalse);
        }
      });
    }

    test('a cel renamed takes its park along — hot under its new name, '
        'parked under it, and nothing left under the old', () {
      final (:hot, :park) = usedParked('f');

      store.rekeyFrames([(key('f'), key('h'))]);

      expect(store.hotBakedSurfaceOrNull(key('h')), same(hot));
      expect(parkOf('h'), same(park));
      expect(parkOf('f'), isNull);
      expect(store.hotBakedSurfaceOrNull(key('f')), isNull);
      expect(File(park.filePath).existsSync(), isTrue);
    });

    test('and the tiles a use took of its shell go with it: an edit under '
        'the new name hands them their bytes', () {
      usedParked('f');
      store.letGoOfBytesTheEngineHolds();
      final tile = store.hotBakedSurfaceOrNull(key('f'))!.tiles[origin]!;
      expect(tile.hasItsBytesHere, isFalse, reason: '⛔premise: a shell');
      store.rekeyFrames([(key('f'), key('h'))]);
      engine.slots = false;

      store.storeBakedSurface(key('h'), ink(9));

      expect(tile.hasItsBytesHere, isTrue);
      expect(tile.pixels, pixelsOf(4));
    });
  });

  test('🧱a hot cel\'s pixels change by no door that lets the file\'s ref '
      'go alone: only the copy\'s keep and the forgetting do', () {
    final source = File(
      'lib/src/services/brush_frame_store.dart',
    ).readAsStringSync();
    final calls = RegExp(
      r'(?<!AnicelCelFileRef\? )_letTheFileRefGo\(',
    ).allMatches(source).toList();
    final bodies = [
      for (final member in const [
        'AnicelCelFileRef? _letTheKeptGo(',
        'void forgetCelsLostWithTheirFile(',
        'void _keepCopy(',
      ])
        _bodyOf(source, member),
    ];

    expect(calls, hasLength(bodies.length));
    for (final (index, call) in calls.indexed) {
      expect(
        call.start,
        inExclusiveRange(bodies[index].from, bodies[index].to),
        reason: 'the call ${source.substring(call.start, call.start + 40)}',
      );
    }
  });
}

/// Where the body of the store's member declared as [signature] lies in
/// [source]: from its declaration to the brace that closes it.
({int from, int to}) _bodyOf(String source, String signature) {
  final from = source.indexOf(signature);
  expect(from, isNot(-1), reason: '⛔premise: $signature is declared');
  return (from: from, to: source.indexOf('\n  }', from));
}
