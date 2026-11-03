import 'package:flutter/widgets.dart';

import '../../models/cut_id.dart';
import '../dialogs/link_window.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';

/// A linked cut's link window (I-25): the cuts it is linked with, and the
/// button that makes it independent — 「해제버튼은 현재 컷을 독립시킴」, which
/// is `CutVerbs.unlinkCuts` on this cut alone, the verb the pill's 「링크
/// 독립」 already presses for a cut. A 동기컷 lists the cut it is in the other
/// timelines apart, with 동기 해제 beside (I-150-Q3 · Q6) — and where that is
/// all it is linked to, 링크 해제 stays in place, off, and says so.
Future<void> showCutLinkWindow(
  BuildContext context, {
  required EditorSessionManager session,
  required CutId cutId,
}) => showLinkWindow(
  context,
  targets: session.cutVerbs.linkedCutLines(cutId),
  unlink: session.cutVerbs.cutIsLinked(cutId)
      ? () => session.cutVerbs.unlinkCuts([cutId])
      : null,
  unlinkOffReason: AppText.strings.linkWindowUnlinkSyncedCut,
  synced: session.cutVerbs.syncedCutLines(cutId),
  unsync: () => session.cutVerbs.unsyncCut(cutId),
);
