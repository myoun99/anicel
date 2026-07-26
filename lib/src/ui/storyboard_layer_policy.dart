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
