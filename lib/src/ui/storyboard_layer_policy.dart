import '../models/cut.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';

/// What a cut block prints where its storyboard layer's name would go when
/// the cut has none.
const String storyboardCutBlockNoLayerLabel = 'No Storyboard Layer';

/// The cut's storyboard row, or null when it has none.
///
/// A cut may hold at most ONE (the conte has one strip per cut, and the
/// coverage rule has one row to tile it). The verbs that could make a
/// second refuse — see [cutAcceptsAnotherStoryboardLayer] — but this does
/// NOT throw when it finds one anyway: it is read from painters and row
/// builds, and a throw there took the whole frame down with a red screen
/// (user, 2026-07-28). A file written by an older build, or a path nobody
/// guarded yet, must degrade to "the first one is the row" rather than to
/// no editor at all. [storyboardLayersOfCut] is how a caller that wants to
/// SAY something about the duplicate finds it.
Layer? storyboardLayerForCut(Cut cut) {
  for (final layer in cut.layers) {
    if (layer.kind == LayerKind.storyboard) {
      return layer;
    }
  }
  return null;
}

/// Every storyboard row on [cut] — one in every reachable state, more only
/// where something already went wrong.
List<Layer> storyboardLayersOfCut(Cut cut) => [
  for (final layer in cut.layers)
    if (layer.kind == LayerKind.storyboard) layer,
];

/// Whether [cut] may take another storyboard row — false once it has one.
///
/// [exceptLayerId] is the layer being CONVERTED, which does not count
/// against itself: re-applying the kind to the row that already is one is
/// a no-op, not a second row.
bool cutAcceptsAnotherStoryboardLayer(Cut cut, {LayerId? exceptLayerId}) {
  for (final layer in cut.layers) {
    if (layer.kind == LayerKind.storyboard && layer.id != exceptLayerId) {
      return false;
    }
  }
  return true;
}

/// The shortest [cut] may become without leaving a storyboard drawing
/// outside it (user's rule 2026-07-27).
///
/// The storyboard row lives INSIDE its cut — that is the whole basis of
/// the conte, where a cell is a panel OF this cut. So the cut's end cannot
/// be dragged past the last division on it: to shrink further, delete the
/// cells first. Everything else keeps the plain one-frame floor.
///
/// This is the invariant's near half. The far half is that the row is born
/// covering the cut, so the two together mean the coverage rule never has
/// a hole to repair.
int minimumCutDurationFor(Cut cut) {
  final layer = storyboardLayerForCut(cut);
  if (layer == null) {
    return 1;
  }
  var lastDivision = 0;
  for (final entry in layer.timeline.entries) {
    if (entry.value.isDrawing && !entry.value.ghost) {
      lastDivision = entry.key > lastDivision ? entry.key : lastDivision;
    }
  }
  return lastDivision + 1;
}
