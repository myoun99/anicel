import 'package:flutter/widgets.dart';

import '../../models/layer_id.dart';
import '../dialogs/link_window.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';

/// A row's link window (I-25): whom the pressed row shares its pictures with,
/// and the button that makes it independent — on every row the press acts on
/// (`RowSelection.rowsActedOnBy`), the reference button's rule, which I-25
/// asks for by name: 「레이어 여러개 선택후 작동하는건 참조버튼 그대로 공용화된거
/// 사용」.
///
/// A linked cut's rows share as the cut does, so on one the button stays in
/// place, off, and says why (「링크컷일경우엔 링크해제버튼 비활성화하고
/// 툴팁으로 링크컷이기때문에 불가능하다고 띄움」).
///
/// Its [kind] the sync, a 동기컷's row's (I-150-Q3): the cut its cut is in
/// the other timelines, and 동기 해제 (I-150-Q6) — the cut's, which the row
/// stands for there.
Future<void> showLayerLinkWindow(
  BuildContext context, {
  required EditorSessionManager session,
  required LayerId layerId,
  required LinkKind kind,
}) {
  final layerVerbs = session.layerVerbs;
  final rows = session.rowSelectionVerbs.rowsActedOnBy(layerId);
  final cutId = session.activeCutOrNull?.id;
  return showLinkWindow(context, switch (kind) {
    LinkKind.link => LinkWindow(
      kind: kind,
      targets: layerVerbs.linkPartnersOf(layerId),
      action: layerVerbs.activeCutIsLinkedCut
          ? null
          : (
              step: () => layerVerbs.unlinkLayers(rows),
              landsOn: () => layerVerbs.drawingsOfRows(rows),
            ),
      actionOffReason: AppText.strings.linkWindowUnlinkLinkedCut,
    ),
    LinkKind.sync => LinkWindow(
      kind: kind,
      targets: layerVerbs.syncPartnersOf(layerId),
      action: cutId == null
          ? null
          : (
              step: () => session.cutVerbs.unsyncCut(cutId),
              landsOn: () => session.cutVerbs.drawingsOfCuts([cutId]),
            ),
    ),
  });
}
