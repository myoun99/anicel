import 'package:flutter/widgets.dart';

import '../../models/cut_id.dart';
import '../dialogs/link_window.dart';
import '../editor_session_manager.dart';

/// A linked cut's link window (I-25): the cuts it is linked with, and the
/// button that makes it independent — 「해제버튼은 현재 컷을 독립시킴」, which
/// is `CutVerbs.unlinkCuts` on this cut alone, the verb the pill's 「링크
/// 독립」 already presses for a cut.
///
/// Its [kind] the sync, a 동기컷's (I-150-Q3): the cut it is in the other
/// timelines, and 동기 해제 (I-150-Q6).
Future<void> showCutLinkWindow(
  BuildContext context, {
  required EditorSessionManager session,
  required CutId cutId,
  required LinkKind kind,
}) => showLinkWindow(context, switch (kind) {
  LinkKind.link => LinkWindow(
    kind: kind,
    targets: session.cutVerbs.linkedCutLines(cutId),
    action: (
      step: () => session.cutVerbs.unlinkCuts([cutId]),
      landsOn: () => session.cutVerbs.drawingsOfCuts([cutId]),
    ),
  ),
  LinkKind.sync => LinkWindow(
    kind: kind,
    targets: session.cutVerbs.syncedCutLines(cutId),
    action: (
      step: () => session.cutVerbs.unsyncCut(cutId),
      landsOn: () => session.cutVerbs.drawingsOfCuts([cutId]),
    ),
  ),
});
