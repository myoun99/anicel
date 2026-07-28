import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_commit_result.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_entry.dart';
import 'package:anicel/src/models/cache_invalidation_plan.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_tile_set.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';

void main() {
  group('BrushBitmapMaterializationHistoryEntry', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    BitmapSurface surface({bool withTile = false, int tileX = 0}) {
      final coord = TileCoord(x: tileX, y: 0);
      return BitmapSurface(
        canvasSize: CanvasSize(width: 4, height: 4),
        tileSize: 2,
        tiles: withTile
            ? {coord: BitmapTile.blank(coord: coord, size: 2)}
            : const {},
      );
    }

    BrushCommitResult changedResult({
      BitmapSurface? beforeSurface,
      BitmapSurface? afterSurface,
      DirtyTileSet? dirtyTiles,
      LayerId layer = layerId,
      FrameId frame = frameId,
    }) {
      final before = beforeSurface ?? surface();
      final after = afterSurface ?? surface(withTile: true);
      final tiles = dirtyTiles ?? DirtyTileSet([TileCoord(x: 0, y: 0)]);
      return BrushCommitResult.changed(
        beforeSurface: before,
        afterSurface: after,
        dirtyTiles: tiles,
        cacheInvalidationPlan: CacheInvalidationPlan.fromDirtyTiles(
          layerId: layer,
          frameId: frame,
          dirtyTiles: tiles,
        ),
      );
    }

    BrushBitmapMaterializationHistoryEntry entry({
      LayerId layer = layerId,
      FrameId frame = frameId,
      BrushCommitResult? commitResult,
    }) {
      return BrushBitmapMaterializationHistoryEntry(
        layerId: layer,
        frameId: frame,
        commitResult: commitResult ?? changedResult(layer: layer, frame: frame),
      );
    }

    test('stores layerId, frameId, and commitResult', () {
      final commit = changedResult();
      final historyEntry = entry(commitResult: commit);

      expect(historyEntry.layerId, layerId);
      expect(historyEntry.frameId, frameId);
      expect(historyEntry.commitResult, commit);
    });

    test('rejects no-op BrushCommitResult', () {
      final original = surface();

      expect(
        () => BrushBitmapMaterializationHistoryEntry(
          layerId: layerId,
          frameId: frameId,
          commitResult: BrushCommitResult.noOp(surface: original),
        ),
        throwsArgumentError,
      );
    });

    test('cacheInvalidationPlan getter delegates to commitResult', () {
      final commit = changedResult();
      final historyEntry = entry(commitResult: commit);

      expect(historyEntry.cacheInvalidationPlan, commit.cacheInvalidationPlan);
    });

    test('dirtyTiles getter delegates to commitResult', () {
      final commit = changedResult();
      final historyEntry = entry(commitResult: commit);

      expect(historyEntry.dirtyTiles, commit.dirtyTiles);
    });

    test('changedTileCount delegates to commitResult', () {
      final commit = changedResult(
        dirtyTiles: DirtyTileSet([
          TileCoord(x: 0, y: 0),
          TileCoord(x: 1, y: 0),
        ]),
      );
      final historyEntry = entry(commitResult: commit);

      expect(historyEntry.changedTileCount, commit.changedTileCount);
    });

    test('copyWith preserves omitted values', () {
      final original = entry();
      final copied = original.copyWith();

      expect(copied.layerId, original.layerId);
      expect(copied.frameId, original.frameId);
      expect(copied.commitResult, original.commitResult);
    });

    test('copyWith updates layerId, frameId, and commitResult', () {
      final original = entry();
      const nextLayerId = LayerId('layer-b');
      const nextFrameId = FrameId('frame-b');
      final nextCommit = changedResult(
        afterSurface: surface(withTile: true, tileX: 1),
        dirtyTiles: DirtyTileSet([TileCoord(x: 1, y: 0)]),
        layer: nextLayerId,
        frame: nextFrameId,
      );

      final copied = original.copyWith(
        layerId: nextLayerId,
        frameId: nextFrameId,
        commitResult: nextCommit,
      );

      expect(copied.layerId, nextLayerId);
      expect(copied.frameId, nextFrameId);
      expect(copied.commitResult, nextCommit);
    });

    test('equality and hashCode compare value fields', () {
      final commit = changedResult();
      final a = entry(commitResult: commit);
      final b = entry(commitResult: commit);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('toString describes history entry without command payload', () {
      final historyEntry = entry();

      expect(
        historyEntry.toString(),
        contains('BrushBitmapMaterializationHistoryEntry'),
      );
      expect(historyEntry.toString(), contains('layerId'));
      expect(historyEntry.toString(), contains('frameId'));
      expect(historyEntry.toString(), isNot(contains('TileDeltaCommand')));
    });
  });
}
