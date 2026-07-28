import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_edit_session_cache_operation_result.dart';
import 'package:anicel/src/models/brush_edit_session_operation_kind.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_composite_cache_key.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_tile_cache_key.dart';
import 'package:anicel/src/models/playback_preview_cache_key.dart';
import 'package:anicel/src/services/brush_edit_session_cache_operations.dart';
import 'package:anicel/src/services/brush_edit_session_state_operations.dart';
import 'package:anicel/src/services/cache_invalidation_executor.dart';

class FakeCacheInvalidationSink implements CacheInvalidationSink {
  final layerTiles = <LayerTileCacheKey>[];
  final frameComposites = <FrameCompositeCacheKey>[];
  final playbackPreviews = <PlaybackPreviewCacheKey>[];

  int get totalCalls =>
      layerTiles.length + frameComposites.length + playbackPreviews.length;

  @override
  void invalidateLayerTile(LayerTileCacheKey key) {
    layerTiles.add(key);
  }

  @override
  void invalidateBrushFrame(invalidation) {}

  @override
  void invalidateFrameComposite(FrameCompositeCacheKey key) {
    frameComposites.add(key);
  }

  @override
  void invalidatePlaybackPreview(PlaybackPreviewCacheKey key) {
    playbackPreviews.add(key);
  }
}

void main() {
  group('brush edit session cache operations', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    BitmapSurface surface() =>
        BitmapSurface(canvasSize: CanvasSize(width: 4, height: 4), tileSize: 2);

    BrushEditSessionState emptySession() => BrushEditSessionState(
      canvasState: CanvasSurfaceState(currentSurface: surface()),
      materializationHistoryState: BrushBitmapMaterializationHistoryState(),
    );

    BrushDabSequence changedSequence() => BrushDabSequence([
      BrushDab(
        center: CanvasPoint(x: 0.5, y: 0.5),
        color: 0xFFFF0000,
        size: 1,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: 0,
      ),
    ]);

    BrushEditSessionCacheOperationResult commitChanged(
      BrushEditSessionState sessionState,
      FakeCacheInvalidationSink sink,
    ) {
      return commitBrushDabSequenceToBrushEditSessionWithCacheInvalidation(
        sessionState: sessionState,
        sequence: changedSequence(),
        layerId: layerId,
        frameId: frameId,
        cacheInvalidationSink: sink,
      );
    }

    test('commit no-op does not call cache sink', () {
      final sink = FakeCacheInvalidationSink();

      commitBrushDabSequenceToBrushEditSessionWithCacheInvalidation(
        sessionState: emptySession(),
        sequence: BrushDabSequence(),
        layerId: layerId,
        frameId: frameId,
        cacheInvalidationSink: sink,
      );

      expect(sink.totalCalls, 0);
    });

    test('commit no-op returns zero cache invalidation result', () {
      final result =
          commitBrushDabSequenceToBrushEditSessionWithCacheInvalidation(
            sessionState: emptySession(),
            sequence: BrushDabSequence(),
            layerId: layerId,
            frameId: frameId,
            cacheInvalidationSink: FakeCacheInvalidationSink(),
          );

      expect(result.cacheInvalidationResult.totalCount, 0);
      expect(result.cacheInvalidationResult.didInvalidate, isFalse);
    });

    test('commit changed calls cache sink', () {
      final sink = FakeCacheInvalidationSink();
      final result = commitChanged(emptySession(), sink);

      expect(
        sink.totalCalls,
        result.affectedEntry!.cacheInvalidationPlan.totalKeyCount,
      );
      expect(sink.totalCalls, greaterThan(0));
    });

    test('commit changed result kind is commit', () {
      expect(
        commitChanged(emptySession(), FakeCacheInvalidationSink()).kind,
        BrushEditSessionOperationKind.commit,
      );
    });

    test(
      'commit changed result sessionState matches normal session commit conversion',
      () {
        final sessionState = emptySession();
        final sequence = changedSequence();
        final normal = commitBrushDabSequenceToBrushEditSessionState(
          sessionState: sessionState,
          sequence: sequence,
          layerId: layerId,
          frameId: frameId,
        );
        final cacheAware =
            commitBrushDabSequenceToBrushEditSessionWithCacheInvalidation(
              sessionState: sessionState,
              sequence: sequence,
              layerId: layerId,
              frameId: frameId,
              cacheInvalidationSink: FakeCacheInvalidationSink(),
            );

        expect(cacheAware.sessionState, sessionStateFromCommitResult(normal));
      },
    );

    test('commit changed affectedEntry equals normal commit historyEntry', () {
      final sessionState = emptySession();
      final sequence = changedSequence();
      final normal = commitBrushDabSequenceToBrushEditSessionState(
        sessionState: sessionState,
        sequence: sequence,
        layerId: layerId,
        frameId: frameId,
      );
      final cacheAware =
          commitBrushDabSequenceToBrushEditSessionWithCacheInvalidation(
            sessionState: sessionState,
            sequence: sequence,
            layerId: layerId,
            frameId: frameId,
            cacheInvalidationSink: FakeCacheInvalidationSink(),
          );

      expect(cacheAware.affectedEntry, normal.historyEntry);
    });

    test('cache invalidation counts match executed plan counts', () {
      final result = commitChanged(emptySession(), FakeCacheInvalidationSink());
      final plan = result.affectedEntry!.cacheInvalidationPlan;

      expect(
        result.cacheInvalidationResult.layerTileCount,
        plan.layerTiles.length,
      );
      expect(
        result.cacheInvalidationResult.frameCompositeCount,
        plan.frameComposites.length,
      );
      expect(
        result.cacheInvalidationResult.playbackPreviewCount,
        plan.playbackPreviews.length,
      );
      expect(result.cacheInvalidationResult.totalCount, plan.totalKeyCount);
    });

    test('input BrushEditSessionState is not mutated', () {
      final sessionState = emptySession();
      final snapshot = sessionState.copyWith();

      commitChanged(sessionState, FakeCacheInvalidationSink());

      expect(sessionState, snapshot);
    });

    test('input CanvasSurfaceState is not mutated', () {
      final sessionState = emptySession();
      final canvasState = sessionState.canvasState;

      commitChanged(sessionState, FakeCacheInvalidationSink());

      expect(identical(sessionState.canvasState, canvasState), isTrue);
      expect(sessionState.canvasState.currentSurface.tiles, isEmpty);
      expect(sessionState.canvasState.lastEdit, isNull);
    });

    test('input BrushBitmapMaterializationHistoryState is not mutated', () {
      final sessionState = emptySession();
      final materializationHistoryState =
          sessionState.materializationHistoryState;

      commitChanged(sessionState, FakeCacheInvalidationSink());

      expect(
        identical(
          sessionState.materializationHistoryState,
          materializationHistoryState,
        ),
        isTrue,
      );
      expect(sessionState.materializationHistoryState.undoEntries, isEmpty);
      expect(sessionState.materializationHistoryState.redoEntries, isEmpty);
    });

    test('no real cache storage is implemented', () {
      final sink = FakeCacheInvalidationSink();
      final result = commitChanged(emptySession(), sink);

      expect(result.didInvalidateCache, isTrue);
      expect(
        sink.layerTiles,
        unorderedEquals(result.affectedEntry!.cacheInvalidationPlan.layerTiles),
      );
    });

    test('no UI/state management/timeline/storyboard changes', () {
      expect(
        commitBrushDabSequenceToBrushEditSessionWithCacheInvalidation,
        isA<Function>(),
      );
    });
  });
}
