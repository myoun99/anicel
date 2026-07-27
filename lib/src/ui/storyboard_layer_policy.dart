import '../models/cut.dart';
import '../models/layer.dart';
import '../models/layer_kind.dart';

/// What a cut block prints where its storyboard layer's name would go when
/// the cut has none.
const String storyboardCutBlockNoLayerLabel = 'No Storyboard Layer';

Layer? storyboardLayerForCut(Cut cut) {
  Layer? storyboardLayer;

  for (final layer in cut.layers) {
    if (layer.kind != LayerKind.storyboard) {
      continue;
    }

    if (storyboardLayer != null) {
      throw StateError(
        'Cut ${cut.id.value} contains multiple storyboard layers.',
      );
    }

    storyboardLayer = layer;
  }

  return storyboardLayer;
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
