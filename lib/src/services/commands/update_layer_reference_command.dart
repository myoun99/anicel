import '../../models/media_reference.dart';
import 'layer_field_command.dart';

/// Sets what a reference row shows of its file (`Layer.mediaReference`) in
/// one undo step — where in the file it starts, where it was placed, its
/// fx — beside the reference fx command a lane edit writes its keys with.
///
/// 🗣️유저 2026-11-17 · 18 (card 「파일마다 배치 기본값」-Q5 · Q6 「시안대로」
/// · Q9 · Q10): the sync window sets a placed file's start, its fit and its
/// kind to its preset again; the fit is the placed size, the size keys
/// carried by the same ratio. ↩️It set the offset alone, until the fit
/// asked for the pose and the keys as well: one reference, one write.
class UpdateLayerReferenceCommand extends LayerFieldCommand<MediaReference?> {
  UpdateLayerReferenceCommand({
    required super.repository,
    required super.layerId,
    required MediaReference reference,
    String description = 'Edit layer reference',
  }) : super(
         value: reference,
         field: (
           name: 'reference',
           label: description,
           read: (layer) => layer.mediaReference,
           write: (value) => repository.updateLayer(
             layerId: layerId,
             update: (layer) => layer.copyWith(mediaReference: value),
           ),
         ),
       );
}
