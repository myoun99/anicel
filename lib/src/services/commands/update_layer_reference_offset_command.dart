import 'layer_field_command.dart';

/// Sets where in its file a reference row starts showing it
/// (`MediaReference.frameOffset`) in one undo step — the reference fx
/// command's sibling for a movie's time. The block stays where it is: its
/// first position shows the file from the new offset on, as a sound's clip
/// slid in its block plays from another sample.
///
/// 🗣️유저 2026-11-17 (card 「파일마다 배치 기본값」-Q5 · Q6 「시안대로」): the
/// sync window sets a placed movie's start to its file's preset again. The
/// rest of the reference — where it stands, its keys, where its pixels are
/// laid — is not this command's.
class UpdateLayerReferenceOffsetCommand extends LayerFieldCommand<int> {
  UpdateLayerReferenceOffsetCommand({
    required super.repository,
    required super.layerId,
    required int frameOffset,
    String description = 'Edit layer reference',
  }) : super(
         value: frameOffset,
         field: (
           name: 'reference offset',
           label: description,
           read: (layer) => layer.mediaReference?.frameOffset ?? 0,
           write: (value) => repository.updateLayer(
             layerId: layerId,
             update: (layer) => layer.copyWith(
               mediaReference: layer.mediaReference?.copyWith(
                 frameOffset: value,
               ),
             ),
           ),
         ),
       );
}
