import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import 'effect_lane_policy.dart' show parseEffectLaneId;
import 'reference_lane_policy.dart' show laneIsReference;
import 'se_name_tag_lane_policy.dart' show laneIsSeNameTag;
import 'transform_lane_policy.dart' show transformGroupHeaderLane;

/// What a LANE ROW of [layer] shows for [laneId] — the object whose identity
/// changes when, and only when, a preview can change that row.
///
/// 🔬F-195 (measured 2026-09-27): a lane edit in flight hands EVERY row of
/// its layer a new Layer through the row gates, and a value scrubbed on one
/// lane rebuilt all fourteen lane rows (rail and frames) — 646 widgets a step
/// against the opacity drag's 66 — to redraw two of them. The rows gate on
/// this instead ([TimelineDragPreviewRowGate.slice]).
///
/// It answers with the row's OWN part because the model keeps what an edit
/// did not touch as the same object: `TransformTrack.copyWith` keeps its
/// other properties, an effect edit its other effects and parameters, a
/// transform edit the name tag.
///
/// ⛔ANYTHING THIS DOES NOT KNOW ANSWERS WITH THE WHOLE LAYER — a lane family
/// added later, the camera row (whose lanes are the cut's camera, read
/// through the session: its marker is a fresh clone per step), the audio
/// lane (its band is the row's blocks) — so a row nobody taught this rebuilds
/// exactly as it always did. Only a WRONG answer here can leave a row stale.
Object laneRowSlice(Layer layer, String laneId) {
  if (layer.kind == LayerKind.camera) {
    return layer;
  }
  final track = layer.transformTrack;
  switch (laneId) {
    case 'anchor-point':
      return track.anchorPoint;
    case 'position':
      return track.position;
    case 'scale':
      return track.scale;
    case 'rotation':
      return track.rotation;
    case 'opacity':
      return track.opacity;
  }
  if (laneId == transformGroupHeaderLane.laneId) {
    return track;
  }
  if (laneIsSeNameTag(laneId)) {
    return layer.seNameTag ?? layer;
  }
  // I-68: the reference fx's rows show its keys over the pose they rest on
  // (F-374), and only an edit of either makes a new reference.
  if (laneIsReference(laneId)) {
    return layer.mediaReference ?? layer;
  }
  final address = parseEffectLaneId(laneId);
  if (address == null) {
    return layer;
  }
  for (final effect in layer.effects) {
    if (effect.id == address.effectId) {
      final parameterId = address.parameterId;
      if (parameterId == null) {
        return effect;
      }
      // Where the effect stands its picture is a transform's lane of its
      // own, and its colours lanes of their own too.
      return effect.standLaneOf(parameterId) == null &&
              effect.colors[parameterId] == null
          ? effect.parameters[parameterId] ?? effect
          : effect.laneTrack(parameterId)!;
    }
  }
  return layer;
}
