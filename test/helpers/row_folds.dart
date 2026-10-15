import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// A ROW'S FOLDS AND TWIRLS AS A FILE WOULD HOLD THEM — a fixture's
/// starting state, written onto the row outside history and read by the
/// rail at once (`RailView.readFolds`).
///
/// F-360 (유저 2026-10-14: 「어태치레이어 분명 접은채로 저장했는데 다시열면
/// 펼쳐져있음 … 제대로 기록되도록」) put them on the rows: `Layer.collapsed`
/// for a base's attach group as for a folder, `Layer.lanesExpanded`,
/// `Layer.expandedLaneGroups`. ↩️Fixtures set the rail's own sets —
/// `railView.collapsedAttachBaseIds.value = {…}` — which nothing outside
/// the rail can write now.
///
/// ⚠️[row] alone: a fixture that wants a link group or a head folded as one
/// presses the row's button instead, which folds every row of it.
void setRowFolds(
  EditorSessionManager session,
  LayerId row, {
  bool? collapsed,
  bool? lanesExpanded,
  Set<String>? expandedLaneGroups,
}) {
  session.repository.updateLayer(
    layerId: row,
    update: (layer) => layer.copyWith(
      collapsed: collapsed,
      lanesExpanded: lanesExpanded,
      expandedLaneGroups: expandedLaneGroups,
    ),
  );
  session.railView.readFolds(session.repository.currentProject);
}
