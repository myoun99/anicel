import '../../models/cut_id.dart';
import '../../models/fx_basis.dart';
import '../../models/layer_id.dart';
import '../project_repository.dart';
import 'link_mirrored_layer_field_command.dart';

/// Sets what a layer's TRANSFORM reads its keys by ([Layer.transformBasis],
/// I-120-Q10) — mirrored across its link group and a track's conte rows,
/// like the transform's own switch beside it. One undo step puts back every
/// member's own.
///
/// The basis is part of the fx's shape, as an effect's is: an effect's
/// mirrors with the chain ([effectChainWithSharedShape]), and the
/// transform's is the transform group's.
class UpdateLayerTransformBasisCommand
    extends LinkMirroredLayerFieldCommand<FxBasis> {
  UpdateLayerTransformBasisCommand({
    required super.repository,
    required super.cutId,
    required super.layerId,
    required FxBasis basis,
  }) : super(
         value: basis,
         fieldName: 'transform basis',
         read: (layer) => layer.transformBasis,
         write: _writeBasis,
       );

  static void _writeBasis(
    ProjectRepository repository, {
    required CutId cutId,
    required LayerId layerId,
    required FxBasis value,
  }) => repository.updateLayer(
    layerId: layerId,
    update: (layer) => layer.transformBasis == value
        ? layer
        : layer.copyWith(transformBasis: value),
  );
}
