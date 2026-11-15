import '../../core/collection_equality.dart' show setEquals;
import '../../models/attached_placement.dart';
import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../project_repository.dart';
import 'link_mirrored_layer_field_command.dart';

/// Folds or opens the SIDES of a base's attach group (`Layer.foldedAttaches`,
/// I-175) — mirrored across its link group and its head as a folder's fold
/// is ([UpdateLayerCollapsedCommand], F-302). One undo step puts back every
/// member's own.
class UpdateLayerAttachFoldsCommand
    extends LinkMirroredLayerFieldCommand<Set<AttachedPlacement>> {
  UpdateLayerAttachFoldsCommand({
    required super.repository,
    required super.cutId,
    required super.layerId,
    required Set<AttachedPlacement> folded,
  }) : super(
         value: folded,
         fieldName: 'foldedAttaches',
         read: (layer) => layer.foldedAttaches,
         write: writeFoldedAttaches,
       );

  /// [value] on ONE row: the setter the mirror walks — and the reveal's,
  /// which opens a side outside history (`Standing`'s attach walk).
  static void writeFoldedAttaches(
    ProjectRepository repository, {
    required CutId cutId,
    required LayerId layerId,
    required Set<AttachedPlacement> value,
  }) => repository.updateLayer(
    layerId: layerId,
    update: (layer) => setEquals(layer.foldedAttaches, value)
        ? layer
        : layer.copyWith(foldedAttaches: Set.unmodifiable(value)),
  );
}
