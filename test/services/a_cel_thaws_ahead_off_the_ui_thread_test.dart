@TestOn('vm')
library;

import 'dart:async';
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
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/persistence/thaw_in_worker.dart';

import '../helpers/project_scratch_folder.dart';

/// 🚨Card `cel-thaw-holds-the-ui-thread`: a cel's thaw — zstd, then a copy
/// per tile — ran on the UI thread, 60–70 ms of a first playback's late
/// frames. [BrushFrameStore.thawAhead] makes it ahead, on a worker, and
/// keeps the card's promises: it completes when the read thaws nothing
/// here, a second ask is the same thaw, a cel that moved on keeps what it
/// has, and a failure is quiet.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 16);

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  /// Two tiles of distinct bytes — a thaw that laid one tile's pixels in
  /// the other's block reads wrong.
  BitmapSurface inkSurface({int seed = 1, CanvasSize canvas = canvasSize}) {
    BitmapTile tile(int salt) {
      final pixels = Uint8List(8 * 8 * 4);
      for (var i = 0; i < pixels.length; i += 1) {
        pixels[i] = (i * seed * 31 + salt) & 0xFF;
      }
      return BitmapTile(size: 8, pixels: pixels);
    }

    return BitmapSurface(
      canvasSize: canvas,
      tileSize: 8,
      tiles: {
        TileCoord(x: 0, y: 0): tile(3),
        TileCoord(x: 1, y: 1): tile(7),
      },
    );
  }

  AnicelCelBlob blobOf(BrushFrameKey k, BitmapSurface surface) =>
      AnicelCelBlob.encode(AnicelCelEntry.fromSurface(k, surface));

  Map<TileCoord, List<int>> pixelsOf(BitmapSurface surface) => {
    for (final entry in surface.tiles.entries)
      entry.key: entry.value.pixels.toList(),
  };

  /// [source] kept as an opened project keeps it: a stretch of its file,
  /// which the store reads and never lets go of while the bytes are the
  /// same.
  Future<void> keepInAFile(
    BrushFrameStore store,
    BrushFrameKey k,
    BitmapSurface source,
  ) async {
    final directory = await Directory.systemTemp.createTemp('qa-thaw-ahead');
    deleteAfterSessionEnds(directory);
    final blob = blobOf(k, source);
    final path = '${directory.path}/cel.bin';
    File(path).writeAsBytesSync(blob.bytes);
    store.restoreFromFile({
      k: AnicelCelFileRef(
        filePath: path,
        dataOffset: 0,
        length: blob.bytes.length,
        canvasSize: canvasSize,
        tileSize: blob.tileSize,
      ),
    });
  }

  /// [body] run while every worker's turn is taken — as by a frame's other
  /// rows — and the turns given back after it, whatever it did.
  Future<void> whileEveryTurnIsTaken(Future<void> Function() body) async {
    final held = Completer<void>();
    final holding = [
      for (var i = 0; i < celThawTurns.atOnce; i += 1)
        celThawTurns.run(() => held.future),
    ];
    try {
      await body();
    } finally {
      held.complete();
      await Future.wait(holding);
    }
  }

  /// Whether [thaws] have all answered once what is queued has run — none
  /// of them waiting for a worker's turn.
  Future<bool> answeredAtOnce(List<Future<void>> thaws) async {
    var answered = false;
    unawaited(Future.wait(thaws).then((_) => answered = true));
    await pumpEventQueue();
    return answered;
  }

  test('🚨a parked cel thawed ahead is hot when it completes — the read '
      'after it thaws nothing, and shows the picture the read here '
      'would have made', () async {
    final store = BrushFrameStore();
    final k = key('a');
    final source = inkSurface();
    store.restoreBaked({k: blobOf(k, source)});
    expect(store.isCelCold(k), isTrue, reason: 'premise');

    await store.thawAhead(k, canvasSize: canvasSize);

    expect(store.isCelCold(k), isFalse, reason: 'kept hot, parking let go');
    final hot = store.hotBakedSurfaceOrNull(k);
    expect(hot, isNotNull);
    expect(
      store.validPreviewSurfaceOrNull(k),
      same(hot),
      reason: 'kept as a read keeps it — its display cache seeded from it',
    );
    expect(store.bakedSurfaceOrNull(k), same(hot), reason: 'nothing thawed');
    expect(pixelsOf(hot!), pixelsOf(source));
  });

  test('a cel in the saved file thawed ahead is hot, and its ref stays — '
      'the file still holds those bytes', () async {
    final store = BrushFrameStore();
    final k = key('f');
    final source = inkSurface(seed: 5);
    await keepInAFile(store, k, source);

    await store.thawAhead(k, canvasSize: canvasSize);

    expect(pixelsOf(store.hotBakedSurfaceOrNull(k)!), pixelsOf(source));
    expect(store.isCelFileBacked(k), isTrue);
  });

  test('asked again while it runs, the same thaw — the cel is thawed '
      'once', () async {
    final store = BrushFrameStore();
    final k = key('a');
    store.restoreBaked({k: blobOf(k, inkSurface())});

    final first = store.thawAhead(k, canvasSize: canvasSize);
    final second = store.thawAhead(k, canvasSize: canvasSize);

    expect(second, same(first));
    await first;
    final hot = store.hotBakedSurfaceOrNull(k);
    await store.thawAhead(k, canvasSize: canvasSize);
    expect(
      store.hotBakedSurfaceOrNull(k),
      same(hot),
      reason: 'asked once it is hot, nothing is thawed again',
    );
  });

  test('nothing to thaw, nothing moves, and nothing waits for a worker — a '
      'hot cel, an empty one, and one kept at another size, which a read at '
      'this size never thaws', () async {
    final store = BrushFrameStore();
    final other = key('other');
    // A restore swaps the WHOLE store, so it goes first.
    store.restoreBaked({other: blobOf(other, inkSurface())});
    final hotKey = key('hot');
    final hot = inkSurface();
    store.storeBakedSurface(hotKey, hot);

    await whileEveryTurnIsTaken(() async {
      expect(
        await answeredAtOnce([
          store.thawAhead(hotKey, canvasSize: canvasSize),
          store.thawAhead(key('empty'), canvasSize: canvasSize),
          store.thawAhead(
            other,
            canvasSize: const CanvasSize(width: 32, height: 32),
          ),
        ]),
        isTrue,
        reason: 'none of them stood in line',
      );
    });

    expect(store.hotBakedSurfaceOrNull(hotKey), same(hot));
    expect(store.celHasRenderableContent(key('empty')), isFalse);
    expect(store.isCelCold(other), isTrue, reason: 'still parked');
  });

  test('a cel hot and still in its file answers at once too — read here, it '
      'keeps its ref, and nothing is left to thaw', () async {
    final store = BrushFrameStore();
    final k = key('f');
    await keepInAFile(store, k, inkSurface(seed: 5));
    final read = store.bakedSurfaceOrNull(k);
    expect(store.isCelFileBacked(k), isTrue, reason: 'premise: still kept');

    await whileEveryTurnIsTaken(() async {
      expect(
        await answeredAtOnce([store.thawAhead(k, canvasSize: canvasSize)]),
        isTrue,
      );
    });

    expect(store.hotBakedSurfaceOrNull(k), same(read));
  });

  test('a cel kept anew at another size while it waits for a worker thaws '
      'nothing — a read at the size it was asked at never would', () async {
    final store = BrushFrameStore();
    final k = key('a');
    store.restoreBaked({k: blobOf(k, inkSurface())});
    late final Future<void> thaw;

    await whileEveryTurnIsTaken(() async {
      thaw = store.thawAhead(k, canvasSize: canvasSize);
      const bigger = CanvasSize(width: 32, height: 32);
      store.restoreBaked({k: blobOf(k, inkSurface(canvas: bigger))});
    });
    await thaw;

    expect(store.isCelCold(k), isTrue, reason: 'still parked, at its size');
  });

  test('🚨a cel drawn on while it thaws keeps the drawing — the thaw is let '
      'go, never written over it', () async {
    final store = BrushFrameStore();
    final k = key('a');
    store.restoreBaked({k: blobOf(k, inkSurface())});

    final thaw = store.thawAhead(k, canvasSize: canvasSize);
    final drawn = inkSurface(seed: 9);
    store.storeBakedSurface(k, drawn);
    await thaw;

    expect(store.bakedSurfaceOrNull(k), same(drawn));
  });

  test('🚨a cel READ here while it thaws keeps what the read made — the '
      'thaw is let go, though the file still holds the bytes both '
      'read', () async {
    final store = BrushFrameStore();
    final k = key('f');
    await keepInAFile(store, k, inkSurface(seed: 5));

    final thaw = store.thawAhead(k, canvasSize: canvasSize);
    final read = store.bakedSurfaceOrNull(k);
    await thaw;

    expect(read, isNotNull, reason: 'premise: the read thawed it here');
    expect(store.hotBakedSurfaceOrNull(k), same(read));
  });

  test('a cel that cooled after its thaw thaws again when asked — a thaw '
      'that ended is no answer for ever', () async {
    final store = BrushFrameStore();
    final k = key('f');
    final source = inkSurface(seed: 5);
    await keepInAFile(store, k, source);
    await store.thawAhead(k, canvasSize: canvasSize);
    // The cel used last never cools, so another is used after it.
    store
      ..storeBakedSurface(key('after'), inkSurface())
      ..hotCelByteBudget = 0
      ..coolToBudget();
    await store.drainCooling();
    expect(store.hotBakedSurfaceOrNull(k), isNull, reason: 'premise: cooled');
    store.hotCelByteBudget = 1 << 30;

    await store.thawAhead(k, canvasSize: canvasSize);

    expect(pixelsOf(store.hotBakedSurfaceOrNull(k)!), pixelsOf(source));
  });

  test('a linked row\'s key thaws the one cel its rows share', () async {
    final store = BrushFrameStore();
    final bank = key('a');
    const window = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('linked'),
      frameId: FrameId('a'),
    );
    store
      ..restoreBaked({bank: blobOf(bank, inkSurface())})
      ..setLinkResolver((k) => k == window ? bank : k);

    await store.thawAhead(window, canvasSize: canvasSize);

    expect(store.isCelCold(bank), isFalse);
  });

  test('a cel emptied while it thaws stays empty', () async {
    final store = BrushFrameStore();
    final k = key('a');
    store.restoreBaked({k: blobOf(k, inkSurface())});

    final thaw = store.thawAhead(k, canvasSize: canvasSize);
    store.storeBakedSurface(k, BitmapSurface(canvasSize: canvasSize));
    await thaw;

    expect(store.bakedSurfaceOrNull(k), isNull);
    expect(store.celHasRenderableContent(k), isFalse);
  });

  test('a cel parked anew while it thaws keeps its new bytes — the thaw of '
      'the old ones is let go', () async {
    final store = BrushFrameStore();
    final k = key('a');
    store.restoreBaked({k: blobOf(k, inkSurface())});

    final thaw = store.thawAhead(k, canvasSize: canvasSize);
    final again = inkSurface(seed: 11);
    store.restoreBaked({k: blobOf(k, again)});
    await thaw;

    expect(store.isCelCold(k), isTrue, reason: 'the new bytes stay parked');
    expect(pixelsOf(store.bakedSurfaceOrNull(k)!), pixelsOf(again));
  });

  test('🚨bytes that will not decode: the thaw completes and throws '
      'nothing, and the cel stays parked — its only copy', () async {
    final store = BrushFrameStore();
    final k = key('a');
    final bytes = Uint8List.fromList(blobOf(k, inkSurface()).bytes);
    for (var i = bytes.length - 16; i < bytes.length; i += 1) {
      bytes[i] ^= 0xFF;
    }
    store.restoreBaked({k: AnicelCelBlob(bytes)});
    expect(
      () => BrushFrameStore()
        ..restoreBaked({k: AnicelCelBlob(bytes)})
        ..bakedSurfaceOrNull(k),
      throwsA(anything),
      reason: 'premise: the read here refuses them too',
    );

    await store.thawAhead(k, canvasSize: canvasSize);

    expect(store.isCelCold(k), isTrue);
  });
}
