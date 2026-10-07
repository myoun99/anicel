import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../project_repository.dart';
import 'link_mirrored_layer_field_command.dart';

/// Folds or opens a row's GROUP — a folder's members — mirrored across its
/// link group, like its blend and its static opacity. One undo step puts
/// back every member's own.
///
/// 🚨유저 2026-10-05 (F-302): 「겸용컷, 레이어에서 fx 접기펼치기, 폴더/어태치
/// 접기/펼치기 버튼도 공유. 지금 겸용컷별로 독립적임. 펼친 상태 접힌 상태
/// 공유하라는것. 법통일」. A linked row is one row seen from several cuts, and
/// how it is folded is how the row is laid out — its own, like its name.
///
/// ↩️THIS REVERSES THE TWIRL'S PART OF T9. The fold was each use's own,
/// written by [UpdateLayerDisplayCommand] beside the eye (「the eye, the
/// twirl and an SE row's mix」 stayed there when F-278 took the blend and
/// the opacity back to the group). The eye is still each use's own (F-278:
/// 「보이기만 독립적으로 하고」).
class UpdateLayerCollapsedCommand extends LinkMirroredLayerFieldCommand<bool> {
  UpdateLayerCollapsedCommand({
    required super.repository,
    required super.cutId,
    required super.layerId,
    required bool collapsed,
  }) : super(
         value: collapsed,
         fieldName: 'collapsed',
         read: (layer) => layer.collapsed,
         write: writeCollapsed,
       );

  /// [value] on ONE row: the setter the mirror walks — and the reveal's,
  /// which opens a folder outside history and reaches the group the same
  /// way (`Standing`'s folder walk).
  static void writeCollapsed(
    ProjectRepository repository, {
    required CutId cutId,
    required LayerId layerId,
    required bool value,
  }) => repository.updateLayer(
    layerId: layerId,
    update: (layer) =>
        layer.collapsed == value ? layer : layer.copyWith(collapsed: value),
  );
}
