import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../project_repository.dart';
import 'link_mirrored_layer_field_command.dart';

/// Sets a layer's STATIC opacity — mirrored across its link group, like its
/// blend ([UpdateLayerBlendModeCommand]). One undo step puts back every
/// member's own.
///
/// 🚨유저 2026-10-04 (F-278): 「불투명도도 공유하도록할까 생각하는데 어떻지?
/// 보이기만 독립적으로 하고」, then 「불투명도 공유도 같이 작업한거지? 블렌드
/// 공유랑 같이?」. How strongly a layer shows is, with its blend, what the
/// layer IS in the composite; whether a cut shows it at all is that cut's.
///
/// ↩️THIS REVERSES THE OPACITY HALF OF T9 (유저 확정 2026-08-13: 「링크레이어
/// … 비지블/정적불투명도는 독립되게 하고싶음. 지금 하나 바꾸면 링크된
/// 레이어들 바꿈」). The eye is still each use's own
/// ([UpdateLayerDisplayCommand]).
///
/// ⚠️A use that must show the layer at its own strength keys the transform's
/// OPACITY LANE: lanes are each use's own, and the lane multiplies this
/// value (`OpacityVerbs.stackLayerOpacity`).
///
/// ⚠️THE WHOLE GROUP, a link-duplicated row of the SAME cut included — the
/// blend command's note says why there is nothing narrower to ask for.
class UpdateLayerOpacityCommand extends LinkMirroredLayerFieldCommand<double> {
  UpdateLayerOpacityCommand({
    required super.repository,
    required super.cutId,
    required super.layerId,
    required double opacity,
  }) : super(
         value: opacity,
         fieldName: 'opacity',
         read: (layer) => layer.opacity,
         write: _writeOpacity,
       );

  static void _writeOpacity(
    ProjectRepository repository, {
    required CutId cutId,
    required LayerId layerId,
    required double value,
  }) => repository.updateLayer(
    layerId: layerId,
    update: (layer) =>
        layer.opacity == value ? layer : layer.copyWith(opacity: value),
  );
}
