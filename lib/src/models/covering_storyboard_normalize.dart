import 'dart:collection';
import 'dart:math' as math;

import '../core/mapped_or_same.dart';
import 'cut.dart';
import 'layer.dart';
import 'timeline_exposure.dart';
import 'layer_kind.dart';
import 'storyboard_coverage.dart';
import 'timeline_run_behavior.dart';
import 'transition_geometry.dart' show CutTransitionHandles;

/// [cut] with its STORYBOARD row's stored blocks tiling the cut exactly —
/// the covering grammar ([LayerKind.coversWithoutGaps]) kept true in
/// STORAGE, the same way [cutWithCoveringImageRows] keeps the image row's.
///
/// The storyboard row was left out of this when the image row got it, on
/// the reasoning that its coverage is DERIVED and therefore unbreakable
/// ([storyboardCoverageCells]). That premise is false, and it is false in a
/// way that shows: the derivation is what the STRIP reads, while the
/// timeline paints the row's stored blocks. So a stored hole is invisible
/// where it is made and plain where it is not, and every verb that writes
/// the row without writing the cut — delete, the comma buttons, "X here",
/// push/pull, block move, paste — can make one. Deriving hid the damage
/// instead of preventing it.
///
/// Running as a repository-write normalization covers all of them at once,
/// including undo/redo replay and file load, which is the only way to be
/// sure a row that is already broken in the field comes back.
///
/// REFUSES rather than repairs when a division sits at or past the cut's
/// end. The reader drops those keys, so filling from it would DELETE that
/// panel — a normalization must never be the thing that loses a drawing.
/// The cut's own floor ([minimumCutDurationFor]) is what keeps a live edit
/// out of that state; this clause is for the file that arrives in it.
///
/// 🗣️F-227 — THE PANELS KEEP THE CONTE'S TIME; THE のりしろ HOLDS THE PANEL
/// AT ITS EDGE. 유저 2026-09-29/30: 「ol주는컷은 콘티블록의 마지막블록을
/// 늘리고 받는컷은 처음블록을 늘리라」. A cut an O.L arrives into draws from
/// the O.L's start — [CutTransitionHandles.head] frames before its conte —
/// so its real blocks tile `[head, head + duration)` of its own frames and
/// its FIRST panel holds back over the head; a cut an O.L leaves draws past
/// its conte end and its LAST panel holds through the tail. Both holds are
/// end-side/start-side run properties the run-edge pass fills, the D22
/// image row's shape: derived from the O.L, so no edit can shorten them —
/// the first block of a cut owing 0+12 can never be less than 12 + 1.
///
/// [previousConteStart] is where the stored blocks were tiled from when
/// the caller knows it (the repository's last write); a row it has never
/// seen tells it itself ([storyboardConteStart]) — a new row is tiled from
/// 0, a loaded one from where it was saved.
///
/// Identity-preserving on no-ops, so an already-normal cut passes through
/// untouched.
Cut cutWithCoveringStoryboardRow(
  Cut cut, {
  required CutTransitionHandles handles,
  int? previousConteStart,
}) {
  if (cut.duration < 1) {
    return cut;
  }
  final layers = mappedOrSame(
    cut.layers,
    (layer) => _coveringStoryboardRow(
      layer,
      cut.duration,
      handles: handles,
      from: previousConteStart ?? storyboardConteStart(layer.timeline),
    ),
  );
  return identical(layers, cut.layers) ? cut : cut.copyWith(layers: layers);
}

/// [layer] tiled to [cutDuration] from its cut's conte start when it is a
/// storyboard row that can be — else [layer] itself (a non-storyboard row,
/// an empty one, one that already tiles, or one the REFUSES clause above
/// leaves alone). [from] is where its blocks were tiled from.
Layer _coveringStoryboardRow(
  Layer layer,
  int cutDuration, {
  required CutTransitionHandles handles,
  required int from,
}) {
  if (layer.kind != LayerKind.storyboard || layer.timeline.isEmpty) {
    return layer;
  }
  final conteStart = handles.head;
  final real = _realBlocksMoved(layer, by: conteStart - from);
  if (_hasDivisionOutsideCut(real, conteStart + cutDuration)) {
    return layer;
  }
  final filled = storyboardTimelineFilledToCover(
    timeline: real,
    cutDuration: cutDuration,
    conteStart: conteStart,
  );
  if (filled == null) {
    return layer;
  }
  final shaped = _withTheEdgesTheCutOwes(filled, handles: handles);
  return _sameBlocks(shaped, layer)
      ? layer
      : layer.copyWith(timeline: shaped);
}

/// [layer]'s REAL blocks — its ghosts are the run-edge pass's — each moved
/// [by] frames: the conte's panels following the cut's conte start when the
/// のりしろ in front of it changes. Never before frame 0: a key the move
/// would push out folds onto the first cell, the coverage rule's own net.
SplayTreeMap<int, TimelineExposure> _realBlocksMoved(
  Layer layer, {
  required int by,
}) => SplayTreeMap<int, TimelineExposure>.of({
  for (final entry in layer.timeline.entries)
    if (!entry.value.ghost) math.max(0, entry.key + by): entry.value,
});

/// [tiled] with the storyboard row's run edges, which are the geometry's
/// and nobody else's: the row takes no run property of its own (design E —
/// it refuses repeat regions, and no surface offers one), so the ones it
/// carries are the holds the のりしろ asks of its first and last panels,
/// and only while the cut owes them.
SplayTreeMap<int, TimelineExposure> _withTheEdgesTheCutOwes(
  Map<int, TimelineExposure> tiled, {
  required CutTransitionHandles handles,
}) {
  final keys = tiled.keys.toList()..sort();
  return SplayTreeMap<int, TimelineExposure>.of({
    for (final entry in tiled.entries)
      entry.key: entry.value.copyWith(
        startEdge: handles.head > 0 && entry.key == keys.first
            ? _panelHold
            : TimelineRunEdgeMark.none,
        endEdge: handles.tail > 0 && entry.key == keys.last
            ? _panelHold
            : TimelineRunEdgeMark.none,
      ),
  });
}

const _panelHold = TimelineRunEdgeMark(mode: TimelineRunEdgeMode.hold);

/// Whether a division sits at or past [conteEnd] — the conte's end in the
/// cut's own frames — which the REFUSES clause above leaves alone.
bool _hasDivisionOutsideCut(
  Map<int, TimelineExposure> real,
  int conteEnd,
) {
  for (final entry in real.entries) {
    if (entry.value.isDrawing && entry.key >= conteEnd) {
      return true;
    }
  }
  return false;
}

/// Whether [layer]'s REAL blocks already are [shaped] — where each starts,
/// how long it holds, and the edges it carries. Its ghosts are the run-edge
/// pass's to derive and are not compared: a row whose blocks are right is
/// passed through with its ghosts, so its identity survives the write.
bool _sameBlocks(Map<int, TimelineExposure> shaped, Layer layer) {
  var real = 0;
  for (final entry in layer.timeline.entries) {
    if (entry.value.ghost) {
      continue;
    }
    real += 1;
    final want = shaped[entry.key];
    if (want == null ||
        want.length != entry.value.length ||
        want.startEdge != entry.value.startEdge ||
        want.endEdge != entry.value.endEdge) {
      return false;
    }
  }
  return real == shaped.length;
}
