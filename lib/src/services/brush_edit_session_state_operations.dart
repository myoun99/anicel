import 'dart:typed_data';

import '../models/placed_tile.dart';
import '../models/bitmap_surface.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab_sequence.dart';
import '../models/dirty_region.dart';
import '../models/brush_edit_session_commit_result.dart';
import '../models/brush_edit_session_state.dart';
import '../models/frame_id.dart';
import '../models/layer_id.dart';
import 'brush_edit_session_commit.dart';

BrushEditSessionCommitResult commitBrushDabSequenceToBrushEditSessionState({
  required BrushEditSessionState sessionState,
  required BrushDabSequence sequence,
  required LayerId layerId,
  required FrameId frameId,
  Uint8List? prerasterizedStrokePixels,
  DirtyRegion? prerasterizedStrokeBounds,
  BrushBlendMode blendMode = BrushBlendMode.color,
  BitmapSurface? promotedBase,
  List<PlacedTile>? promotedTiles,
}) {
  return commitBrushDabSequenceToBrushEditSession(
    canvasState: sessionState.canvasState,
    materializationHistoryState: sessionState.materializationHistoryState,
    sequence: sequence,
    layerId: layerId,
    frameId: frameId,
    prerasterizedStrokePixels: prerasterizedStrokePixels,
    prerasterizedStrokeBounds: prerasterizedStrokeBounds,
    blendMode: blendMode,
    promotedBase: promotedBase,
    promotedTiles: promotedTiles,
  );
}

BrushEditSessionState sessionStateFromCommitResult(
  BrushEditSessionCommitResult result,
) {
  return BrushEditSessionState(
    canvasState: result.canvasState,
    materializationHistoryState: result.materializationHistoryState,
  );
}
