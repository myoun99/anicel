import 'dart:typed_data';

import '../models/placed_tile.dart';
import '../models/bitmap_surface.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab_sequence.dart';
import '../models/dirty_region.dart';
import '../models/brush_edit_session_cache_operation_result.dart';
import '../models/brush_edit_session_operation_kind.dart';
import '../models/brush_edit_session_state.dart';
import '../models/cache_invalidation_execution_result.dart';
import '../models/frame_id.dart';
import '../models/layer_id.dart';
import 'brush_edit_session_state_operations.dart';
import 'cache_invalidation_executor.dart';

BrushEditSessionCacheOperationResult
commitBrushDabSequenceToBrushEditSessionWithCacheInvalidation({
  required BrushEditSessionState sessionState,
  required BrushDabSequence sequence,
  required LayerId layerId,
  required FrameId frameId,
  required CacheInvalidationSink cacheInvalidationSink,
  Uint8List? prerasterizedStrokePixels,
  DirtyRegion? prerasterizedStrokeBounds,
  BrushBlendMode blendMode = BrushBlendMode.color,
  BitmapSurface? promotedBase,
  List<PlacedTile>? promotedTiles,
}) {
  final commitResult = commitBrushDabSequenceToBrushEditSessionState(
    sessionState: sessionState,
    sequence: sequence,
    layerId: layerId,
    frameId: frameId,
    prerasterizedStrokePixels: prerasterizedStrokePixels,
    prerasterizedStrokeBounds: prerasterizedStrokeBounds,
    blendMode: blendMode,
    promotedBase: promotedBase,
    promotedTiles: promotedTiles,
  );
  final historyEntry = commitResult.historyEntry;

  return BrushEditSessionCacheOperationResult(
    kind: BrushEditSessionOperationKind.commit,
    sessionState: sessionStateFromCommitResult(commitResult),
    affectedEntry: historyEntry,
    cacheInvalidationResult: historyEntry == null
        ? _zeroCacheInvalidationResult()
        : executeCacheInvalidationPlan(
            plan: historyEntry.cacheInvalidationPlan,
            sink: cacheInvalidationSink,
          ),
  );
}

CacheInvalidationExecutionResult _zeroCacheInvalidationResult() {
  return CacheInvalidationExecutionResult(
    layerTileCount: 0,
    frameCompositeCount: 0,
    playbackPreviewCount: 0,
  );
}
