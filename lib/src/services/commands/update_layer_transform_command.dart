import '../../models/cut_id.dart';
import '../../models/transform_track.dart';
import 'layer_field_command.dart';

/// Replaces a layer's whole transform track in one undo step (lane edits
/// are computed as pure functions on the track, then committed here —
/// mirrors the instruction and camera-track commands).
class UpdateLayerTransformCommand extends LayerFieldCommand<TransformTrack> {
  UpdateLayerTransformCommand({
    required super.repository,
    required CutId cutId,
    required super.layerId,
    required TransformTrack transformTrack,
    String description = 'Edit layer transform',
  }) : super(
         value: transformTrack,
         field: (
           name: 'transform',
           label: description,
           read: (layer) => layer.transformTrack,
           write: (value) => repository.updateLayerTransformTrack(
             cutId: cutId,
             layerId: layerId,
             transformTrack: value,
           ),
         ),
       );
}
