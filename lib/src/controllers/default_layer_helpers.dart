import '../models/cut.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../models/timeline_exposure.dart';

LayerId defaultLayerIdForSequence(int sequence) {
  if (sequence < 1) {
    throw ArgumentError.value(
      sequence,
      'sequence',
      'Default layer id sequence must be positive.',
    );
  }
  return LayerId('default-layer-$sequence');
}

String celLayerNameForIndex(int index) {
  if (index < 0) {
    throw ArgumentError.value(
      index,
      'index',
      'Cel layer name index must be non-negative.',
    );
  }

  var value = index;
  var name = '';
  do {
    final letter = String.fromCharCode('A'.codeUnitAt(0) + (value % 26));
    name = letter + name;
    value = (value ~/ 26) - 1;
  } while (value >= 0);

  return name;
}

String nextCelLayerNameForCut(Cut cut) {
  final usedNames = cut.layers.map((layer) => layer.name).toSet();
  var index = 0;
  while (true) {
    final name = celLayerNameForIndex(index);
    if (!usedNames.contains(name)) {
      return name;
    }
    index += 1;
  }
}

Layer createDefaultAnimationLayer({
  required LayerId layerId,
  required Cut cut,
}) {
  // A new cel layer is all empty cells ("X" everywhere): emptiness needs no
  // timeline entry in the unified model.
  return Layer(
    id: layerId,
    name: nextCelLayerNameForCut(cut),
    frames: const [],
    timeline: const {},
  );
}

/// A COVERING layer ([layerKindCoversWithoutGaps]) is born covering its
/// cut — one cell, edge to edge (user's rule 2026-07-27 for storyboard;
/// the image layer speaks the same grammar).
///
/// These rows have no empty cells at all: there is no "X" in their world,
/// so a drawing holds to the end of the cut the way a division does.
/// Starting full is what makes that true from the first instant instead
/// of after the first edit — the cut cannot then shrink past it
/// ([minimumCutDurationFor]), and the coverage rule never meets a hole.
Layer createCoveringLayer({
  required LayerId layerId,
  required FrameId frameId,
  required Cut cut,
  LayerKind kind = LayerKind.storyboard,
}) {
  assert(layerKindCoversWithoutGaps(kind));
  final duration = cut.duration < 1 ? 1 : cut.duration;
  return Layer(
    id: layerId,
    name: nextCelLayerNameForCut(cut),
    kind: kind,
    frames: [Frame(id: frameId, duration: duration, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(frameId, length: duration)},
  );
}

/// The storyboard-kind shorthand for [createCoveringLayer] (its original
/// name — the storyboard row was the first covering kind).
Layer createStoryboardLayer({
  required LayerId layerId,
  required FrameId frameId,
  required Cut cut,
}) => createCoveringLayer(layerId: layerId, frameId: frameId, cut: cut);
