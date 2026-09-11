import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_store.dart';

/// A movie kept as a reference is decoded when shown, and its pictures live
/// in the cel store BESIDE the tiers: never saved, never banked twice, paid
/// for in bytes from the hot budget, let go of first.
void main() {
  const canvas = CanvasSize(width: 8, height: 8);

  BrushFrameKey key(int elapsed) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('movie'),
    frameId: movieCelFrameId(const FrameId('held'), elapsed),
  );

  /// A picture that HOLDS something — one tile of [seed]-coloured pixels.
  BitmapSurface picture(int seed) => BitmapSurface(
    canvasSize: canvas,
    tileSize: 8,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: 8,
        pixels: Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, seed),
      ),
    },
  );

  test('a movie cel HAS a picture before it is decoded — so the display '
      'cache does not bank a blank one as valid', () {
    final store = BrushFrameStore();

    expect(store.celHasRenderableContent(key(5)), isTrue);
    expect(store.frameOrNull(key(5)), isNotNull);
    expect(
      store.currentSurfaceWithoutReplay(key(5), canvasSize: canvas),
      isNull,
    );
    final preview = BrushFrameDisplayCacheService(
      frameStore: store,
      canvasSize: canvas,
    ).prepareFramePreview(key(5));
    expect(preview.isValid, isFalse, reason: 'a miss, not an empty cel');
  });

  test('installed, it IS the cel\'s picture: the revision moves, the pixel '
      'signal fires, and nothing is marked for saving', () {
    final store = BrushFrameStore();
    final revision = store.frameOrNull(key(5))!.sourceRevision;
    final pixels = store.celPixelRevision.value;
    final surface = picture(1);

    store.installMovieCel(key(5), surface);

    expect(
      identical(
        store.currentSurfaceWithoutReplay(key(5), canvasSize: canvas),
        surface,
      ),
      isTrue,
    );
    expect(store.frameOrNull(key(5))!.sourceRevision, revision + 1);
    expect(store.celPixelRevision.value, pixels + 1);
    expect(store.hasMovieCel(key(5), canvas), isTrue);
    expect(
      store.hasMovieCel(key(5), const CanvasSize(width: 16, height: 16)),
      isFalse,
      reason: 'a resized cut decodes again',
    );
    expect(
      store.currentSurfaceWithoutReplay(
        key(5),
        canvasSize: const CanvasSize(width: 16, height: 16),
      ),
      isNull,
      reason:
          'and draws nothing meanwhile — a picture fitted to another '
          'canvas is not this one\'s',
    );
    expect(
      store.dirtyCelKeysSinceSave,
      isEmpty,
      reason: 'a decoded picture is not the project\'s',
    );
  });

  test('the same picture again moves nothing', () {
    final store = BrushFrameStore();
    final surface = picture(1);
    store.installMovieCel(key(5), surface);
    final revision = store.frameOrNull(key(5))!.sourceRevision;
    final pixels = store.celPixelRevision.value;

    store.installMovieCel(key(5), surface);

    expect(store.frameOrNull(key(5))!.sourceRevision, revision);
    expect(store.celPixelRevision.value, pixels);
  });

  test('its display cache is not banked, and memory pressure lets the '
      'pictures go', () {
    final store = BrushFrameStore()..installMovieCel(key(5), picture(1));

    BrushFrameDisplayCacheService(
      frameStore: store,
      canvasSize: canvas,
    ).prepareFramePreview(key(5));
    expect(store.displayCacheOrNull(key(5)), isNull);

    store.respondToMemoryPressure();
    expect(store.hasMovieCel(key(5), canvas), isFalse);
    expect(store.movieCelBytes, 0);
  });

  test('movie pictures are paid for in BYTES from the hot budget — least '
      'recently used go first, and the newest always stays', () {
    final store = BrushFrameStore()..installMovieCel(key(0), picture(1));
    final cost = store.movieCelBytes;
    expect(cost, greaterThan(0), reason: 'fixture: a picture holds a tile');
    store.hotCelByteBudget = 3 * cost;

    for (var i = 1; i <= 3; i += 1) {
      store.installMovieCel(key(i), picture(i + 1));
    }

    expect(store.movieCelBytes, 3 * cost);
    expect(store.hasMovieCel(key(0), canvas), isFalse, reason: 'the oldest');
    expect(store.hasMovieCel(key(3), canvas), isTrue);

    store.hotCelByteBudget = cost ~/ 2;
    store.installMovieCel(key(4), picture(9));

    expect(
      store.hasMovieCel(key(4), canvas),
      isTrue,
      reason: 'the one about to be drawn stays, even alone over budget',
    );
    expect(store.movieCelBytes, cost);
  });

  test('a picture drawn from is used: it outlives one that was not', () {
    final store = BrushFrameStore()..installMovieCel(key(0), picture(1));
    store
      ..hotCelByteBudget = 2 * store.movieCelBytes
      ..installMovieCel(key(1), picture(2))
      ..currentSurfaceWithoutReplay(key(0), canvasSize: canvas)
      ..installMovieCel(key(2), picture(3));

    expect(store.hasMovieCel(key(0), canvas), isTrue);
    expect(store.hasMovieCel(key(1), canvas), isFalse);
  });

  test('a picture two positions show is paid for ONCE', () {
    final store = BrushFrameStore();
    final shared = picture(1);
    store.installMovieCel(key(0), shared);
    final cost = store.movieCelBytes;

    store.installMovieCel(key(1), shared);
    expect(store.movieCelBytes, cost);

    store.installMovieCel(key(0), picture(2));
    expect(
      store.movieCelBytes,
      2 * cost,
      reason: 'position 1 still holds the shared one',
    );

    store.installMovieCel(key(1), picture(3));
    expect(
      store.movieCelBytes,
      2 * cost,
      reason: 'the shared one goes with its last holder',
    );
  });

  test('a drawing that grows takes its room back from the movie pictures — '
      'and no drawing cools for a movie', () async {
    final store = BrushFrameStore()..installMovieCel(key(0), picture(1));
    final cost = store.movieCelBytes;
    store
      ..hotCelByteBudget = 3 * cost
      ..installMovieCel(key(1), picture(2))
      ..installMovieCel(key(2), picture(3));
    expect(store.movieCelBytes, 3 * cost);

    store.storeBakedSurface(
      const BrushFrameKey(
        projectId: ProjectId('p'),
        trackId: TrackId('t'),
        cutId: CutId('c'),
        layerId: LayerId('ink'),
        frameId: FrameId('drawn'),
      ),
      picture(7),
    );
    await store.drainCooling();

    expect(store.hotBakedBytes, cost, reason: 'the drawing stays hot');
    expect(store.movieCelBytes, 2 * cost);
    expect(
      store.hasMovieCel(key(0), canvas),
      isFalse,
      reason: 'the oldest picture made the room',
    );
  });
}
