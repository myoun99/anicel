import 'package:flutter/widgets.dart';

import 'dialogs/frame_name_conflict_dialog.dart';
import 'editor_session_manager.dart';
import 'session/frame_clipboard.dart' show LinkedPasteJoins;
import 'text/app_strings.dart';
import 'text/place_lines.dart' show drawingPlaceLines;

/// 링크 붙여넣기, asking first where it would link by NAME.
///
/// 🗣️I-71 (유저 2026-10-05): 「그 외에도 그냥 다른레이어에 붙여넣을때
/// 독립붙여넣기밖에 안되는데, 링크붙여넣기 가능하게. 동작은 말한대로 이름
/// 유지되는붙여넣기. 해당행동시 기존에 이름 존재한다면 링크시킬지 묻는것도
/// 띄우고」.
///
/// The press IS the question, so there is no window before the paste: it
/// lands at once unless a name it carries is already held on a row it lands
/// on. Then nothing is written and the link window asks ONCE, listing the
/// row's own frames the pasted blocks would show ([offerLink] — the
/// rename's own guard). Link pastes joined to them, as one undo; Cancel
/// writes nothing.
Future<void> pasteLinkedAskingFirst(
  BuildContext context,
  EditorSessionManager session,
) async {
  final joins = session.clipboard.pasteLinkedFrameAtCurrentFrame();
  if (joins == null) {
    return;
  }
  await offerLink<LinkedPasteJoins>(
    context,
    joins,
    notice: AppText.strings.linkedPasteConflictBody,
    onConflict: (
      lines: (joins) => [
        for (final row in joins)
          ...drawingPlaceLines(
            session.repository.requireProject(),
            row.layerId,
            row.held,
          ),
      ],
      join: (_) => session.clipboard.pasteLinkedFrameAtCurrentFrame(
        joinTakenNames: true,
      ),
      decline: null,
    ),
  );
}
