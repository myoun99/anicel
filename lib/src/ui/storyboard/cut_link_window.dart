import 'package:flutter/widgets.dart';

import '../../models/cut_id.dart';
import '../dialogs/link_window.dart';
import '../editor_session_manager.dart';

/// A linked cut's link window (I-25): the cuts it is linked with, and the
/// button that makes it independent — 「해제버튼은 현재 컷을 독립시킴」, which
/// is `CutVerbs.unlinkCuts` on this cut alone, the verb the pill's 「링크
/// 독립」 already presses for a cut.
Future<void> showCutLinkWindow(
  BuildContext context, {
  required EditorSessionManager session,
  required CutId cutId,
}) => showLinkWindow(
  context,
  targets: session.cutVerbs.linkedCutLines(cutId),
  unlink: () => session.cutVerbs.unlinkCuts([cutId]),
);
