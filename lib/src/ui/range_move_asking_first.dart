import 'package:flutter/widgets.dart';

import 'dialogs/frame_name_conflict_dialog.dart';
import 'editor_session_manager.dart';
import 'session/frame_range_move_drag.dart' show CarriedNameJoins;
import 'text/place_lines.dart' show drawingPlaceLines;

/// Lets a frame-range move go, asking first where it would carry a drawing
/// onto a row that already holds its name.
///
/// 🚨F-413 (유저 2026-10-19): 「A1,A2를 B행으로 옮기면 1이라는 이름의 그림이
/// 두개존재함. 그래서 B행에 이동하고 손 뗄 때 링크프레임 창
/// 작동시키도록」. The rename's own window ([offerLink], in its words): it
/// lists the carried drawings a join discards, each where it stands before
/// the move. Link lands the move with them joined, as one undo; Cancel puts
/// the blocks back where they were and writes nothing.
Future<void> releaseRangeMoveAskingFirst(
  BuildContext context,
  EditorSessionManager session,
) async {
  final joins = session.rangeMove.endFrameRangeMoveDrag();
  if (joins == null) {
    return;
  }
  await offerLink<CarriedNameJoins>(
    context,
    joins,
    onConflict: (
      lines: (joins) => [
        for (final row in joins)
          ...drawingPlaceLines(
            session.repository.requireProject(),
            row.from,
            row.held.keys,
            framePlace: session.framePlaceLabel,
          ),
      ],
      join: (_) =>
          session.rangeMove.endFrameRangeMoveDrag(joinTakenNames: true),
      decline: session.rangeMove.cancelFrameRangeMoveDrag,
    ),
  );
}
