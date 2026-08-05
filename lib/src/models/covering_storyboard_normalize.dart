import 'cut.dart';
import 'layer.dart';
import 'layer_kind.dart';
import 'storyboard_coverage.dart';

/// [cut] with its STORYBOARD row's stored blocks tiling the cut exactly —
/// the covering grammar ([layerKindCoversWithoutGaps]) kept true in
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
/// Identity-preserving on no-ops, so an already-normal cut passes through
/// untouched.
Cut cutWithCoveringStoryboardRow(Cut cut) {
  if (cut.duration < 1) {
    return cut;
  }
  List<Layer>? nextLayers;
  for (var i = 0; i < cut.layers.length; i += 1) {
    final layer = cut.layers[i];
    if (layer.kind != LayerKind.storyboard || layer.timeline.isEmpty) {
      continue;
    }
    if (_hasDivisionOutsideCut(layer, cut.duration)) {
      continue;
    }
    final filled = storyboardTimelineFilledToCover(
      timeline: layer.timeline,
      cutDuration: cut.duration,
    );
    if (filled == null || _sameTiling(filled, layer)) {
      continue;
    }
    (nextLayers ??= [...cut.layers])[i] = layer.copyWith(timeline: filled);
  }
  return nextLayers == null ? cut : cut.copyWith(layers: nextLayers);
}

bool _hasDivisionOutsideCut(Layer layer, int cutDuration) {
  for (final entry in layer.timeline.entries) {
    if (!entry.value.isDrawing || entry.value.ghost) {
      continue;
    }
    if (entry.key < 0 || entry.key >= cutDuration) {
      return true;
    }
  }
  return false;
}

bool _sameTiling(Map<int, dynamic> filled, Layer layer) {
  if (filled.length != layer.timeline.length) {
    return false;
  }
  for (final entry in filled.entries) {
    final current = layer.timeline[entry.key];
    if (current == null || current.length != entry.value.length) {
      return false;
    }
  }
  return true;
}
