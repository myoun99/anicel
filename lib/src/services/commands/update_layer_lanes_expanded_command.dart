import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../project_repository.dart';
import 'link_mirrored_layer_field_command.dart';

/// Twirls a row's property lanes open or shut (`Layer.lanesExpanded`) — on
/// every row of its head: its link group (F-302), its track's conte rows at
/// its seat (I-73) and its track's cameras (I-73 ④ⓔ, whose one row the
/// storyboard twirls). One undo step puts back every row's own.
///
/// 🗣️유저 2026-08-29: 「fx접기도 마찬가지고. 아무튼 레이어에 있는 버튼
/// 싹다」 — the twirl undoes, as every button on a row does. ⛔Where the bit
/// lives was never the user's question (「프로젝트 파일이 바뀌란건 무슨소리지?
/// 아무튼 어니언 적용 미적용만 되면 되는건데」); keeping it is (F-360, 유저
/// 2026-10-14: 「fx나 폴더나 이런 접음/펼침상태가 기록이 안되는건지? 제대로
/// 기록되도록」) — so it lives on the row, where the folder's fold does.
class UpdateLayerLanesExpandedCommand
    extends LinkMirroredLayerFieldCommand<bool> {
  UpdateLayerLanesExpandedCommand({
    required super.repository,
    required super.cutId,
    required super.layerId,
    required bool expanded,
  }) : super(
         value: expanded,
         fieldName: 'lanesExpanded',
         read: (layer) => layer.lanesExpanded,
         write: _write,
         ofTheCameraHead: true,
       );

  static void _write(
    ProjectRepository repository, {
    required CutId cutId,
    required LayerId layerId,
    required bool value,
  }) => repository.updateLayer(
    layerId: layerId,
    update: (layer) => layer.lanesExpanded == value
        ? layer
        : layer.copyWith(lanesExpanded: value),
  );
}
