import 'brush_frame_key.dart';

/// Frame-local cel bookkeeping (R19 P3b — command lists retired: the
/// cel's picture is its baked raster in the store; undo entries hold
/// surface snapshots at the app level).
///
/// What remains is the mutation ledger consumers key their caches on:
/// [sourceRevision] bumps on every pixel edit, and [inactivePreviewDirty]
/// tracks display-cache staleness between an edit and its follow-up
/// donation.
///
/// 🪦A `cacheDirtyTiles` set used to sit beside them, added with the
/// display-cache foundation in 2026-07 and meant to say WHICH tiles had
/// gone stale. Its reader never arrived — the caches key on
/// [sourceRevision] and the flag above instead — so for a year it was a
/// set the store unioned into and nobody ever asked. ⛔It also made
/// `markCelEdited(dirtyTiles: null)` mean「add nothing」while the
/// coordinator's `_invalidateBrushFrame(dirtyTiles: null)` one call away
/// meant「the whole frame」: one word, two opposite answers, kept alive by
/// a field with no reader.
class BrushFrameDrawingState {
  BrushFrameDrawingState({
    required this.key,
    this.inactivePreviewDirty = false,
    this.sourceRevision = 0,
  });

  final BrushFrameKey key;
  final bool inactivePreviewDirty;
  final int sourceRevision;

  /// The same cel under a different store key (a cross-layer block move
  /// re-homing it, R10-④b) — bookkeeping unchanged.
  BrushFrameDrawingState copyWithKey(BrushFrameKey key) {
    return BrushFrameDrawingState(
      key: key,
      inactivePreviewDirty: inactivePreviewDirty,
      sourceRevision: sourceRevision,
    );
  }

  BrushFrameDrawingState copyWith({
    bool? inactivePreviewDirty,
    int? sourceRevision,
  }) {
    return BrushFrameDrawingState(
      key: key,
      inactivePreviewDirty: inactivePreviewDirty ?? this.inactivePreviewDirty,
      sourceRevision: sourceRevision ?? this.sourceRevision,
    );
  }
}
