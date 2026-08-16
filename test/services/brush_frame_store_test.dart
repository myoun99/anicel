import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/dirty_tile_set.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';

/// R19 P3b store contract: the baked raster IS the cel; the drawing
/// state is a mutation ledger; display caches are aliases.
void main() {
  BrushFrameKey key({
    String project = 'p',
    String cut = 'c',
    String layer = 'l',
    String frame = 'f',
  }) => BrushFrameKey(
    projectId: ProjectId(project),
    trackId: TrackId('t'),
    cutId: CutId(cut),
    layerId: LayerId(layer),
    frameId: FrameId(frame),
  );

  BitmapSurface surfaceWithInk({int size = 4}) {
    final pixels = Uint8List(4 * 4 * 4)..fillRange(0, 16, 255);
    return BitmapSurface(
      canvasSize: CanvasSize(width: size, height: size),
      tileSize: 4,
    ).putTile(
      BitmapTile(coord: TileCoord(x: 0, y: 0), size: 4, pixels: pixels),
    );
  }

  group('link resolver (L1): linked members address ONE physical cel', () {
    /// cut-b/layer-9 links to canonical cut-a/layer-1.
    void installLink(BrushFrameStore store) {
      final registry = LayerLinkRegistry(
        groups: [
          LayerLinkGroup(
            id: 'g1',
            members: const [
              LayerLinkMember(
                trackId: TrackId('t'),
                cutId: CutId('c'),
                layerId: LayerId('l'),
              ),
              LayerLinkMember(
                trackId: TrackId('t'),
                cutId: CutId('cut-b'),
                layerId: LayerId('layer-9'),
              ),
            ],
          ),
        ],
      );
      store.setLinkResolver(registry.canonicalCelKey);
    }

    test('writes through a member land under the canonical key and reads '
        'through EITHER member see them', () {
      final store = BrushFrameStore();
      installLink(store);
      final memberKey = key(cut: 'cut-b', layer: 'layer-9');
      final canonicalKey = key();

      store.storeBakedSurface(memberKey, surfaceWithInk());

      expect(store.celHasRenderableContent(canonicalKey), isTrue);
      expect(store.celHasRenderableContent(memberKey), isTrue);
      expect(
        identical(
          store.bakedSurfaceOrNull(memberKey),
          store.bakedSurfaceOrNull(canonicalKey),
        ),
        isTrue,
        reason: 'one physical surface — the member is a window onto it',
      );
      // The invariant: non-canonical keys never enter storage, so the
      // save payload holds the linked bank exactly once.
      expect(store.bakedSnapshotForSave().hot.keys, [canonicalKey]);
    });

    test('an edit through a member bumps the revision the OTHER member '
        'reads (cache validity propagates with zero fan-out)', () {
      final store = BrushFrameStore();
      installLink(store);
      final memberKey = key(cut: 'cut-b', layer: 'layer-9');
      final canonicalKey = key();
      store.storeBakedSurface(canonicalKey, surfaceWithInk());
      final before = store.getOrCreateFrame(canonicalKey).sourceRevision;

      store.markCelEdited(memberKey);

      expect(store.frameOrNull(canonicalKey)!.sourceRevision, before + 1);
      expect(store.frameOrNull(memberKey)!.sourceRevision, before + 1);
    });

    test('unlinked keys resolve to themselves', () {
      final store = BrushFrameStore();
      installLink(store);
      final unlinked = key(cut: 'cut-x', layer: 'layer-1');
      store.storeBakedSurface(unlinked, surfaceWithInk());
      expect(store.bakedSnapshotForSave().hot.keys, [unlinked]);
    });
  });

  test('storeBakedSurface is the content oracle; empty tiles REMOVE the '
      'cel (an all-undone cel is empty)', () {
    final store = BrushFrameStore();
    final k = key();
    expect(store.celHasRenderableContent(k), isFalse);

    store.storeBakedSurface(k, surfaceWithInk());
    expect(store.celHasRenderableContent(k), isTrue);

    store.storeBakedSurface(
      k,
      BitmapSurface(canvasSize: const CanvasSize(width: 4, height: 4)),
    );
    expect(store.celHasRenderableContent(k), isFalse);
    expect(store.bakedSurfaceOrNull(k), isNull);
  });

  test('markCelEdited bumps the revision and dirties an existing display '
      'cache; the follow-up donation refreshes it', () {
    final store = BrushFrameStore();
    final k = key();
    final surface = surfaceWithInk();
    store.storeBakedSurface(k, surface);
    store.storeRebuiltDisplayCache(key: k, previewSurface: surface);
    final revisionBefore = store.getOrCreateFrame(k).sourceRevision;

    store.markCelEdited(
      k,
      dirtyTiles: DirtyTileSet.empty().add(TileCoord(x: 0, y: 0)),
    );

    expect(
      store.getOrCreateFrame(k).sourceRevision,
      greaterThan(revisionBefore),
    );
    expect(store.hasValidDisplayCache(k), isFalse);

    store.storeRebuiltDisplayCache(key: k, previewSurface: surface);
    expect(store.hasValidDisplayCache(k), isTrue);
  });

  test('currentSurfaceWithoutReplay: valid cache first, else baked, null '
      'for a size mismatch', () {
    final store = BrushFrameStore();
    final k = key();
    final surface = surfaceWithInk();
    store.storeBakedSurface(k, surface);

    expect(
      identical(
        store.currentSurfaceWithoutReplay(
          k,
          canvasSize: const CanvasSize(width: 4, height: 4),
        ),
        surface,
      ),
      isTrue,
    );
    expect(
      store.currentSurfaceWithoutReplay(
        k,
        canvasSize: const CanvasSize(width: 8, height: 8),
      ),
      isNull,
    );
  });

  test('rekeyFrames moves ledger, cache and baked truth together', () {
    final store = BrushFrameStore();
    final from = key(layer: 'a');
    final to = key(layer: 'b');
    final surface = surfaceWithInk();
    store.storeBakedSurface(from, surface);
    store.storeRebuiltDisplayCache(key: from, previewSurface: surface);
    store.markCelEdited(from);

    store.rekeyFrames([(from, to)]);

    expect(store.bakedSurfaceOrNull(from), isNull);
    expect(identical(store.bakedSurfaceOrNull(to), surface), isTrue);
    expect(store.displayCacheOrNull(to), isNotNull);
    expect(store.frameOrNull(to)?.key, to);
  });

  test('rekeyFrames is a content CROSSING the timeline hears: '
      'celContentRevision bumps for both ends of the move', () {
    final store = BrushFrameStore();
    final from = key(layer: 'a');
    final to = key(layer: 'b');
    store.storeBakedSurface(from, surfaceWithInk());

    final before = store.celContentRevision.value;
    store.rekeyFrames([(from, to)]);
    expect(
      store.celContentRevision.value,
      greaterThan(before),
      reason:
          'the move flips [from] to empty and [to] to has-picture; without '
          'a bump the timeline tile store keeps serving tiles whose pixels '
          'answered for the pre-move world (the open-staleness family)',
    );

    // The inverse pair crosses back — same law, same signal.
    final beforeUndo = store.celContentRevision.value;
    store.rekeyFrames([(to, from)]);
    expect(store.celContentRevision.value, greaterThan(beforeUndo));

    // A move of NOTHING is not a crossing: no content, no bump.
    final beforeNoop = store.celContentRevision.value;
    store.rekeyFrames([(key(layer: 'empty-1'), key(layer: 'empty-2'))]);
    expect(store.celContentRevision.value, beforeNoop);
  });

  test('adoptSavedFile re-registering a cel that lost every tier is a '
      'crossing; the everyday save of a still-hot cel is not', () {
    final store = BrushFrameStore();
    final k = key();
    final ref = AnicelCelFileRef(
      filePath: 'unused.anicel',
      dataOffset: 0,
      length: 1,
      canvasSize: const CanvasSize(width: 4, height: 4),
      tileSize: 4,
    );

    // Everyday save: the cel is hot before and after — no crossing.
    store.storeBakedSurface(k, surfaceWithInk());
    final beforeClean = store.celContentRevision.value;
    store.adoptSavedFile({k: ref});
    expect(store.celContentRevision.value, beforeClean);

    // The cel empties between the save snapshot and the adoption: the ref
    // landing makes it renderable again, and the timeline must hear it.
    store.storeBakedSurface(
      k,
      BitmapSurface(
        canvasSize: const CanvasSize(width: 4, height: 4),
        tileSize: 4,
      ),
    );
    expect(store.celHasRenderableContent(k), isFalse);
    final beforeAdopt = store.celContentRevision.value;
    store.adoptSavedFile({k: ref});
    expect(store.celHasRenderableContent(k), isTrue);
    expect(
      store.celContentRevision.value,
      greaterThan(beforeAdopt),
      reason:
          'a silent tier move: the ref flipped the content answer and '
          'nothing else tells the timeline to look again',
    );
  });

  test('bakedSnapshotForSave is a reference-cheap copy of the truth', () {
    final store = BrushFrameStore();
    final k = key();
    final surface = surfaceWithInk();
    store.storeBakedSurface(k, surface);

    final snapshot = store.bakedSnapshotForSave();

    expect(identical(snapshot.hot[k], surface), isTrue);
    expect(snapshot.cold, isEmpty);
    snapshot.hot.remove(k);
    expect(store.bakedSurfaceOrNull(k), isNotNull, reason: 'copy, not view');
  });

  test('full-path BrushFrameKey isolates cels sharing the same frame id', () {
    final store = BrushFrameStore();
    final first = key(project: 'p1');
    final second = key(project: 'p2');
    store.storeBakedSurface(first, surfaceWithInk());

    expect(store.celHasRenderableContent(first), isTrue);
    expect(store.celHasRenderableContent(second), isFalse);
  });
}
