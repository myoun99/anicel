import 'package:flutter/foundation.dart';

import '../editor_session_manager.dart';
import 'canvas_selection_commands.dart';

/// 🚨★★★**UNDO AND REDO — ONE verb each, and every door opens the same
/// one.** Ctrl+Z / Ctrl+Y and whatever the user bound them to, the two- and
/// three-finger taps, a pen or mouse button mapped to them, and the tool
/// rail's ↶ ↷.
///
/// 🗣️H42 (유저 2026-09-24): 「두손가락 핑거로 언두랑 세손가락 리두가
/// 안먹히는거같으니 **다른부분도 조사해줘**」. The survey found the rail's two
/// buttons calling the DOCUMENT's undo straight past the questions every
/// other door asks: with a polygon trace open, Ctrl+Z took a vertex back and
/// ↶ an edit; inside a transform box, Ctrl+Z took one operation back and ↶
/// landed the whole transform and undid it (유저 2026-09-20: 「변형도구
/// 사용시 변형에 대한 조작마다 언두로 기록 … 확정하면 변형 하나로서의 언두만
/// 작동」 — undo, not a key); and with a pen mid-stroke ↶ still undid.
///
/// ⛔[canUndo] and [undo] read ONE function, as [ConfirmVerb]'s two do: a
/// door that is lit always does something and a grey one never does.
class HistoryVerbs {
  HistoryVerbs({
    required this.selection,
    required this.session,
    required this.contactIsDown,
  });

  final CanvasSelectionCommands selection;
  final EditorSessionManager session;

  /// 🚨★★★**A VERB IN FLIGHT REFUSES UNDO AND REDO** — asked when a door
  /// opens, never folded into [canUndo]: a button that went grey under every
  /// stroke would flicker with the hand.
  ///
  /// 🗣️유저 2026-09-21 (F-173): 「**선 그리는 도중 언두가 작동함.** 선
  /// 말고도 **도구를 사용중이면 언두/리두 작동불가**하도록」.
  ///
  /// ⛔**A CONTACT DOWN IS THE WHOLE TEST, and the fact was already there**:
  /// the shell's census is fed by the global pointer route, and the autosave
  /// clock has read it as 「a stroke is in flight」 since F-1. A second way
  /// to ask 「is the user in the middle of something」 is how the two come
  /// to disagree ([[no-copy-to-share]]).
  ///
  /// ⚠️It stands BEFORE the channels rather than beside them. They answer
  /// 「is this about the thing I am in the middle of?」 and each falls
  /// through when it is not; this one says the press is not a press at all
  /// yet, which is a different sentence and has to come first.
  ///
  /// ⚠️The census hears a lift LAST (the pointer router runs after every
  /// hit-test target), so a door that opens on its own lift must open after
  /// the lift has been heard, or it counts itself — the H42 failure.
  final bool Function() contactIsDown;

  /// Everything [canUndo] and [canRedo] depend on.
  Listenable get changes => Listenable.merge([selection, session.historyManager]);

  bool get canUndo => _undo() != null;

  bool get canRedo => _redo() != null;

  void undo() {
    if (contactIsDown()) {
      return;
    }
    _undo()?.call();
  }

  void redo() {
    if (contactIsDown()) {
      return;
    }
    _redo()?.call();
  }

  /// Undo means the thing the user is in the MIDDLE of, if there is one.
  ///
  /// While a polygon outline is open, it takes that trace's last vertex
  /// back (유저 확정). They are NOT document history: a trace of twenty
  /// taps would otherwise bury the twenty real edits under it, and the
  /// undo cap is 200. An open transform box answers the same way for its
  /// own operations (유저 2026-09-20).
  ///
  /// ⛔Each channel answers false once its own thing is back where it
  /// started, so undo falls straight through to the document — undo never
  /// becomes a dead key just because something was open a moment ago. And
  /// the document is LAST: asked first, it would land an open session and
  /// undo somebody else's edit while the user was still transforming.
  VoidCallback? _undo() {
    if (selection.hasOpenPolygon) {
      return selection.undoPolygonPoint;
    }
    // 🚨★★★**AN OPEN TRANSFORM BOX TAKES UNDO THE SAME WAY** — 유저
    // 2026-09-20: 「**변형도구 사용시 변형에 대한 조작마다 언두로 기록**
    // 된단거야 … **확정하면 변형 하나로서의 언두만 작동**」.
    //
    // ⛔It answers false once the box stands as it opened, so undo falls
    // through to the document exactly as it does after the last vertex —
    // 「is this about the thing I am in the middle of?」 is one question with
    // one shape, asked twice.
    if (selection.canUndoTransformStep) {
      return selection.undoTransformStep;
    }
    return session.canUndo ? session.undo : null;
  }

  /// The mirror of [_undo]: a vertex the trace took back is put back before
  /// the document's redo. A transform box has no redo of its own — 유저 asked
  /// for its undo only.
  VoidCallback? _redo() {
    if (selection.canRedoPolygonPoint) {
      return selection.redoPolygonPoint;
    }
    return session.canRedo ? session.redo : null;
  }
}
