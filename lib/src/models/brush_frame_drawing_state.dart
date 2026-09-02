import 'brush_frame_key.dart';
import 'dirty_tile_set.dart';

/// Frame-local cel bookkeeping (R19 P3b — command lists retired: the
/// cel's picture is its baked raster in the store; undo entries hold
/// surface snapshots at the app level).
///
/// What remains is the mutation ledger consumers key their caches on:
/// [sourceRevision] bumps on every pixel edit, [cacheDirtyTiles] and
/// [inactivePreviewDirty] track display-cache staleness between an edit
/// and its follow-up donation.
class BrushFrameDrawingState {
  BrushFrameDrawingState({
    required this.key,
    this.inactivePreviewDirty = false,
    this.sourceRevision = 0,
    DirtyTileSet? cacheDirtyTiles,
  }) : cacheDirtyTiles = cacheDirtyTiles ?? DirtyTileSet.empty();

  final BrushFrameKey key;
  final bool inactivePreviewDirty;
  final int sourceRevision;
  final DirtyTileSet cacheDirtyTiles;

  /// The same cel under a different store key (a cross-layer block move
  /// re-homing it, R10-④b) — bookkeeping unchanged.
  BrushFrameDrawingState copyWithKey(BrushFrameKey key) {
    return BrushFrameDrawingState(
      key: key,
      inactivePreviewDirty: inactivePreviewDirty,
      sourceRevision: sourceRevision,
      cacheDirtyTiles: cacheDirtyTiles,
    );
  }

  BrushFrameDrawingState copyWith({
    bool? inactivePreviewDirty,
    int? sourceRevision,
    DirtyTileSet? cacheDirtyTiles,
  }) {
    return BrushFrameDrawingState(
      key: key,
      inactivePreviewDirty: inactivePreviewDirty ?? this.inactivePreviewDirty,
      sourceRevision: sourceRevision ?? this.sourceRevision,
      cacheDirtyTiles: cacheDirtyTiles ?? this.cacheDirtyTiles,
    );
  }
}
