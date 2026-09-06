import 'layer.dart';
import 'layer_id.dart';

/// How far [to] sits from [from] in a layer stack, or null when either
/// row is missing from it.
///
/// The null is the point of the function, not a convenience: a dangling
/// anchor (deleting a base out from under its group is a supported state)
/// answers -1 from `indexWhere`, which must not read as "below" — nor as
/// a hop the caller can walk.
int? layerIndexDelta(List<Layer> layers, LayerId from, LayerId to) {
  final fromIndex = layers.indexWhere((layer) => layer.id == from);
  final toIndex = layers.indexWhere((layer) => layer.id == to);
  if (fromIndex < 0 || toIndex < 0) {
    return null;
  }
  return toIndex - fromIndex;
}
