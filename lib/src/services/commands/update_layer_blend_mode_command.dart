import '../../models/cut_id.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../project_repository.dart';
import 'link_mirrored_layer_field_command.dart';

/// Sets a layer's composite blend — mirrored across its link group, like
/// its name, mark and kind. One undo step puts back every member's own.
///
/// 🚨유저 2026-10-04 (F-278): 「겸용컷 블렌드모드도 공유하도록 하자. 지금
/// 블렌드모드 겸용컷끼리 같은레이어인데 독립적이야 … 보이기만 독립적으로
/// 하고」. How a layer blends is what the layer IS in the composite; whether
/// a cut shows it is that cut's own.
///
/// ↩️T9 (유저 확정 2026-08-13) had made the blend each use's own, along with
/// the eye and the static opacity — 「비지블/정적불투명도는 독립되게
/// 하고싶음」 named those two, and the blend went with them because the
/// three shared one mirror helper. The static opacity came back to the
/// group the same day ([UpdateLayerOpacityCommand]); the eye is still each
/// use's own ([UpdateLayerDisplayCommand]).
///
/// ⚠️THE WHOLE GROUP, a link-duplicated row of the SAME cut included: the
/// registry holds one group per shared layer and every mirrored field walks
/// all of it ([linkMirrorTargets]) — there is no 「the other cut's row」
/// narrower than that to ask for.
class UpdateLayerBlendModeCommand
    extends LinkMirroredLayerFieldCommand<LayerBlendMode> {
  UpdateLayerBlendModeCommand({
    required super.repository,
    required super.cutId,
    required super.layerId,
    required LayerBlendMode blendMode,
  }) : super(
         value: blendMode,
         fieldName: 'blend mode',
         read: (layer) => layer.blendMode,
         write: _writeBlendMode,
       );

  static void _writeBlendMode(
    ProjectRepository repository, {
    required CutId cutId,
    required LayerId layerId,
    required LayerBlendMode value,
  }) => repository.updateLayer(
    layerId: layerId,
    update: (layer) =>
        layer.blendMode == value ? layer : layer.copyWith(blendMode: value),
  );
}
