import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/commands/brush_stroke_history_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// R13 accumulation-budget guards: a drawing session must not grow the
/// heap per cel forever. Pinned here:
///
/// 1. the edit-session store retains at most
///    [BrushHistoryPolicy.retainedSessionLimit] live sessions (LRU);
/// 2. undo of an EVICTED cel's stroke still lands exactly (the command
///    replay fallback);
/// 3. display caches ALIAS the baked truth (R19 P3a) — they carry no
///    independent bytes, which is why they need no budget of their own;
/// 4. the tile-image cache pins stale-fallback tiles for at most
///    [BitmapTileImageCache.retainedScopeLimit] scopes.
void main() {
  const canvasSize = CanvasSize(width: 512, height: 512);

  BrushFrameKey celKey(int index) => BrushFrameKey(
    projectId: const ProjectId('guard-project'),
    trackId: const TrackId('guard-track'),
    cutId: const CutId('guard-cut'),
    layerId: const LayerId('guard-layer'),
    frameId: FrameId('guard-frame-$index'),
  );

  List<BrushDab> strokeDabs() => [
    for (var index = 0; index < 6; index += 1)
      BrushDab(
        center: CanvasPoint(x: 60.0 + index * 12.0, y: 80),
        color: 0xFF224488,
        size: 24,
        opacity: 1,
        flow: 1,
        hardness: 0.8,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: index,
      ),
  ];

  (BrushFrameEditingCoordinator, BrushFrameEditSessionStore, HistoryManager)
  coordinatorFixture() {
    final sessionStore = BrushFrameEditSessionStore(canvasSize: canvasSize);
    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: celKey(0),
      frameStore: BrushFrameStore(),
      sessionStore: sessionStore,
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 24,
        deferredBakeRatio: 0,
      ),
    );
    return (coordinator, sessionStore, HistoryManager());
  }

  void commitStroke(
    BrushFrameEditingCoordinator coordinator,
    HistoryManager history,
  ) {
    history.execute(
      BrushStrokeHistoryCommand(
        coordinator: coordinator,
        strokeData: BrushStrokeCommitData(sourceDabs: strokeDabs()),
      ),
    );
  }

  test('the session store retains at most retainedSessionLimit sessions '
      '(LRU, active always kept)', () {
    final (coordinator, sessionStore, history) = coordinatorFixture();

    for (var cel = 0; cel < 10; cel += 1) {
      coordinator.selectFrame(celKey(cel));
      commitStroke(coordinator, history);
    }

    expect(
      sessionStore.sessionCount,
      BrushHistoryPolicy.defaultRetainedSessionLimit,
    );
    expect(sessionStore.sessionOrNull(celKey(9)), isNotNull);
    expect(
      sessionStore.sessionOrNull(celKey(0)),
      isNull,
      reason: 'the oldest cel evicted',
    );
  });

  test('undo and redo of an EVICTED cel still land byte-exactly: surface '
      'snapshots are self-contained (R19 P3b — stronger than the old '
      'replay fallback)', () {
    final (coordinator, sessionStore, history) = coordinatorFixture();

    coordinator.selectFrame(celKey(0));
    commitStroke(coordinator, history);
    expect(coordinator.frameStore.celHasRenderableContent(celKey(0)), isTrue);

    // Draw across enough cels to evict cel 0's session.
    for (var cel = 1; cel < 7; cel += 1) {
      coordinator.selectFrame(celKey(cel));
      commitStroke(coordinator, history);
    }
    expect(sessionStore.sessionOrNull(celKey(0)), isNull);

    // Undo everything back through cel 0's stroke (its session is gone —
    // the snapshot needs no session state at all).
    for (var i = 0; i < 7; i += 1) {
      history.undo();
    }
    expect(coordinator.frameStore.celHasRenderableContent(celKey(0)), isFalse);
    coordinator.selectFrame(celKey(0));
    expect(
      coordinator.activeSessionState.canvasState.currentSurface.tiles,
      isEmpty,
      reason: 'undo restored the blank pre-stroke surface exactly',
    );

    // Redo lands the stroke back from the post snapshot.
    history.redo();
    expect(coordinator.frameStore.celHasRenderableContent(celKey(0)), isTrue);
    coordinator.selectFrame(celKey(0));
    expect(
      coordinator.activeSessionState.canvasState.currentSurface.tiles,
      isNotEmpty,
      reason: 'redo restored the stroke pixels',
    );
  });

  test('display caches are ALIASES of the baked truth (R19 P3a): storing '
      'and re-reading shares the surface object, so the old byte-budget '
      'eviction would have freed nothing', () {
    final store = BrushFrameStore();

    BitmapSurface surfaceWithTile() => BitmapSurface(
      canvasSize: canvasSize,
    ).putTile(BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 256));

    for (var cel = 0; cel < 3; cel += 1) {
      final surface = surfaceWithTile();
      // The donation path stores the SAME immutable surface into both maps.
      store.storeBakedSurface(celKey(cel), surface);
      store.storeRebuiltDisplayCache(key: celKey(cel), previewSurface: surface);
    }

    for (var cel = 0; cel < 3; cel += 1) {
      final cache = store.displayCacheOrNull(celKey(cel));
      expect(cache, isNotNull, reason: 'no eviction: caches are all kept');
      expect(
        identical(cache!.previewSurface, store.bakedSurfaceOrNull(celKey(cel))),
        isTrue,
        reason: 'the cache aliases the baked truth — zero independent bytes',
      );
    }
  });

  test('the tile-image cache pins at most retainedScopeLimit scopes', () async {
    final cache = BitmapTileImageCache();
    final coord = TileCoord(x: 0, y: 0);

    Future<void> decodeInScope(Object scope) async {
      final tile = BitmapTile.blank(coord: coord, size: 8);
      cache.ensureDecoded(tile, staleScope: scope);
      while (cache.imageFor(tile) == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    final scopeCount = BitmapTileImageCache.retainedScopeLimit + 3;
    for (var scope = 0; scope < scopeCount; scope += 1) {
      await decodeInScope('scope-$scope');
    }

    expect(
      cache.latestImageForCoord(coord, scope: 'scope-${scopeCount - 1}'),
      isNotNull,
    );
    expect(
      cache.latestImageForCoord(coord, scope: 'scope-0'),
      isNull,
      reason: 'the least-recent scope evicted',
    );
  });
}
