import '../../models/transform_track.dart';
import 'layer_field_command.dart';

/// Replaces a reference row's REFERENCE FX keys in one undo step — the
/// reference fx's twin of `UpdateLayerTransformCommand`: lane edits are
/// computed as pure functions on the track, then committed here.
///
/// 🗣️F-374 (유저 2026-10-17): 「참조fx도 똑같이 fx로서 법 통일 … 언두도
/// 가능하게」. ↩️A reference fx was ONE pose, and every write of it laid the
/// file again first, so its undo step only landed once the file had been
/// read. Its keys are written the moment they change, as every fx's are;
/// where the file was placed (`MediaReference.pose`) and where its pixels
/// are laid (`MediaReference.laid`) are not this command's — it keeps the
/// rest of the reference as it finds it.
class UpdateLayerReferenceFxCommand extends LayerFieldCommand<TransformTrack> {
  UpdateLayerReferenceFxCommand({
    required super.repository,
    required super.layerId,
    required TransformTrack fx,
    String description = 'Edit layer reference',
  }) : super(
         value: fx,
         field: (
           name: 'reference fx',
           label: description,
           read: (layer) => layer.mediaReference?.fx ?? TransformTrack.empty(),
           write: (value) => repository.updateLayer(
             layerId: layerId,
             update: (layer) => layer.copyWith(
               mediaReference: layer.mediaReference?.copyWith(fx: value),
             ),
           ),
         ),
       );
}
