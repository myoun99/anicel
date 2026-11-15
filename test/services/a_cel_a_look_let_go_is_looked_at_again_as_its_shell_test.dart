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
import 'package:anicel/src/services/cel_shells.dart';

import '../helpers/cels_parked_cold.dart';

/// 🚨Card `let-go-cels-keep-their-gpu-tiles` (유저 2026-11-16 03:10: 「지금
/// 착지하고, GPU 타일을 남기는 일을 바로 다음으로」): a cel a look let go of
/// is looked at again as what the engine still holds of it — its shell
/// ([BrushFrameStore.keepShellOf]) — where it was thawed from the file again
/// and every tile put back on the engine. What a shell is, and when the
/// engine lets its slots go, is the ledger's ([CelShells]); here a keeper
/// that makes one of every surface it is handed.
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

  BitmapSurface ink(int seed) {
    final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = seed * 40;
      pixels[i + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: defaultCelTileSize,
      tiles: {origin: BitmapTile(size: defaultCelTileSize, pixels: pixels)},
    );
  }

  late _Shells shells;
  late BrushFrameStore store;

  setUp(() {
    shells = _Shells();
    store = BrushFrameStore(shells: shells);
    parkCold(store, {key('a'): ink(1), key('b'): ink(2)});
  });

  Future<BitmapSurface?> lookAhead(String frame) =>
      store.lookAhead(key(frame), canvasSize: canvasSize);

  /// [frame]'s cel looked at, and let go as a look lets go of it.
  Future<BitmapSurface> lookedAndLetGo(String frame) async {
    final looked = (await lookAhead(frame))!;
    store.keepShellOf(
      key(frame),
      looked,
      canvasSize: canvasSize,
      revision: store.sourceRevisionOf(key(frame)),
    );
    return looked;
  }

  group('the store', () {
    test('🚨a cel a look let go is handed its shell at the next look — not '
        'thawed again', () async {
      final looked = await lookedAndLetGo('a');
      expect(shells.made, hasLength(1), reason: '⛔premise: a shell kept');

      final again = await lookAhead('a');

      expect(again, same(shells.made.single));
      expect(again, isNot(same(looked)));
      expect(store.isCelCold(key('a')), isTrue, reason: 'still not hot');
    });

    test('🚨a shell some of whose slots the engine let go is thawed again, '
        'and let go', () async {
      await lookedAndLetGo('a');
      shells.whole = false;

      final thawed = await lookAhead('a');
      shells.whole = true;
      final again = await lookAhead('a');

      expect(thawed, isNot(same(shells.made.single)));
      expect(thawed!.tiles[origin]!.pixels, ink(1).tiles[origin]!.pixels);
      expect(again, isNot(same(shells.made.single)), reason: 'let go');
    });

    test('🚨hot wins — a cel made hot lets its shell go, and is read hot',
        () async {
      await lookedAndLetGo('a');

      await store.thawAhead(key('a'), canvasSize: canvasSize);
      final hot = store.hotBakedSurfaceOrNull(key('a'));
      expect(hot, isNotNull, reason: '⛔premise: made hot');

      expect(store.shells, isEmpty);
      expect(await lookAhead('a'), same(hot));
    });

    test('a look at a hot cel keeps no shell — the store holds its tiles '
        'already', () async {
      await store.thawAhead(key('a'), canvasSize: canvasSize);
      final hot = store.hotBakedSurfaceOrNull(key('a'));
      expect(hot, isNotNull, reason: '⛔premise: made hot');

      store.keepShellOf(
        key('a'),
        hot!,
        canvasSize: canvasSize,
        revision: store.sourceRevisionOf(key('a')),
      );

      expect(shells.made, isEmpty);
    });

    test('a closed project keeps no shell', () async {
      await lookedAndLetGo('a');
      expect(store.shells, [same(shells.made.single)], reason: '⛔premise');

      store.dispose();

      expect(store.shells, isEmpty);
    });

    test('kept bytes that moved on are thawed — the shell is of the bytes '
        'it was read from', () async {
      await lookedAndLetGo('a');

      parkCold(store, {key('a'): ink(3), key('b'): ink(2)});
      final again = await lookAhead('a');

      expect(again, isNot(same(shells.made.single)));
      expect(again!.tiles[origin]!.pixels, ink(3).tiles[origin]!.pixels);
    });

    test('nothing is kept of a look at a revision the cel has left, or at '
        'another size', () async {
      final looked = (await lookAhead('a'))!;
      final revision = store.sourceRevisionOf(key('a'));

      store.keepShellOf(
        key('a'),
        looked,
        canvasSize: canvasSize,
        revision: revision + 1,
      );
      store.keepShellOf(
        key('a'),
        looked,
        canvasSize: const CanvasSize(width: 1, height: 1),
        revision: revision,
      );

      expect(shells.made, isEmpty);
    });

    test('a store with no keeper keeps nothing, and every look thaws',
        () async {
      final bare = BrushFrameStore();
      parkCold(bare, {key('a'): ink(1)});
      final looked = await bare.lookAhead(key('a'), canvasSize: canvasSize);
      bare.keepShellOf(
        key('a'),
        looked!,
        canvasSize: canvasSize,
        revision: bare.sourceRevisionOf(key('a')),
      );

      final again = await bare.lookAhead(key('a'), canvasSize: canvasSize);

      expect(again, isNot(same(looked)));
    });
  });

  group('the looks', () {
    late CelLooks looks;

    setUp(() => looks = CelLooks(store));

    Future<void> readAhead(List<String> frames) => looks.ahead([
      for (final frame in frames) key(frame),
    ], canvasSize: canvasSize);

    test('🚨a cel the looks let go — two frames that do not look at it — '
        'is handed to the store as it goes', () async {
      await readAhead(['a']);
      final read = looks.surfaces.single;

      looks.nextFrame();
      expect(shells.handed, isEmpty, reason: 'held for one more frame');
      looks.nextFrame();

      expect(shells.handed, [same(read)]);
      expect(looks.held, 0);
    });

    test('a cel the next frame looks at again is not let go', () async {
      await readAhead(['a']);
      looks.nextFrame();
      await readAhead(['a']);

      looks.nextFrame();

      expect(shells.handed, isEmpty);
    });

    test('letting go at the end hands every cel held to the store', () async {
      await readAhead(['a']);
      looks.nextFrame();
      await readAhead(['b']);

      looks.letGo();

      expect(shells.handed, hasLength(2));
      expect(await lookAhead('a'), same(shells.made.first));
    });
  });
}

/// A keeper that makes a shell of every surface it is handed — the
/// surface's tiles in a surface of their own — and says whether the engine
/// holds them all by [whole].
final class _Shells implements CelShells {
  final handed = <BitmapSurface>[];
  final made = <BitmapSurface>[];
  bool whole = true;

  @override
  BitmapSurface? shellOf(BitmapSurface surface) {
    handed.add(surface);
    final shell = BitmapSurface(
      canvasSize: surface.canvasSize,
      tileSize: surface.tileSize,
      tiles: {...surface.tiles},
    );
    made.add(shell);
    return shell;
  }

  @override
  bool isWhole(BitmapSurface shell) => whole;
}
