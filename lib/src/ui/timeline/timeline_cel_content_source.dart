import 'package:flutter/foundation.dart';

import '../../models/layer.dart';

/// The unworked-block tint's source (R26 #44): the FACT and the EVENT that
/// changes it, in one place.
///
/// Whether a cel holds any picture lives in the brush store, not in the
/// immutable `Layer`, so it is DERIVED state — and derived state needs its
/// own signal or nothing downstream can know it moved. It had none: the
/// timeline only caught up when an unrelated edit announced app-wide, so a
/// freshly drawn block stayed grey until you switched layers or renamed a
/// frame.
///
/// [revision] is that signal. The row painters take it as a repaint
/// listenable and re-read [hasContent]; the grid's tile store takes its
/// value, because a baked tile whose resolver identity is unchanged would
/// otherwise keep serving the old tint back.
///
/// It replaces a pair of parameters threaded side by side through the panel,
/// the grids and the rows — the fact and a per-layer "empty cels" token
/// string rebuilt on every pass. One bundle, and the token's O(frames) join
/// per row per build goes with it.
@immutable
class TimelineCelContentSource {
  const TimelineCelContentSource({
    required this.hasContent,
    required this.cannotRead,
    required this.revision,
  });

  /// Whether the drawing block covering [frameIndex] holds any picture.
  /// True everywhere the tint does not apply (non-drawing sections).
  final bool Function(Layer layer, int frameIndex) hasContent;

  /// Whether the drawing block covering [frameIndex] shows a cel whose
  /// picture data could not be read — the block goes red
  /// (frame-picture-indicator-Q1 b). A file cel answers [hasContent] by
  /// what it is said to hold, so such a block reads as drawn without this.
  final bool Function(Layer layer, int frameIndex) cannotRead;

  /// Bumps whenever [hasContent] or [cannotRead] can have changed anywhere.
  final ValueListenable<int> revision;
}
