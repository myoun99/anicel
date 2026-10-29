import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;

import '../models/standing_place.dart';
import 'command.dart';

/// 🚨★★★I-41 — WHERE EACH HISTORY ENTRY WAS MADE.
///
/// 🗣️유저 2026-09-24: 「그곳으로 이동해서 편집되돌리고 리두대칭」 — the
/// first undo walks to the edit, the next one takes it back. So every entry
/// remembers where the user stood, written where every entry comes through
/// the history ([HistoryManager]'s push, groups included, and each step).
/// ⛔Not per command: which kind of edit it is has nothing to do with where
/// the user was.
///
/// Its own object because it is its own question: the history keeps the
/// stacks and their bytes, and this keeps the places beside them.
class HistoryPlaces {
  /// Where the user stands now. Null keeps no places (a history no editor
  /// stands in).
  StandingPlace? Function()? placeNow;

  /// Weak, so an entry that falls off the deep end takes its place along.
  final Expando<StandingPlace> _places = Expando<StandingPlace>('I-41');

  /// Where each entry FOUND the user — written once, as it is first
  /// stamped ([foundAt]).
  final Expando<StandingPlace> _found = Expando<StandingPlace>('F-350');

  /// The entry the last action pushed or stepped, until that action has
  /// settled.
  Command? _settling;

  /// Where [entry] was made, or null when nothing says.
  StandingPlace? of(Command entry) => _places[entry];

  /// Where [entry] found the user — what an undo that takes away the row
  /// they stand on hands back.
  ///
  /// 🗣️F-350 (유저 2026-10-12): 「레이어 여러개 생성하고 언두할때 매번
  /// 카메라 레이어로 이동하는 1개 과정이 있음. 한번에 바로 삭제해야하는데」.
  /// Taking a new row back left the user on the row that took its place in
  /// the list — the one above, the camera at the top of the stack — so the
  /// next undo walked to the row the row before was made on ([of]), and
  /// every row took two presses. Handed back to where the add found them,
  /// they stand where the next undo was made.
  StandingPlace? foundAt(Command entry) => _found[entry];

  /// 🚨WHERE THE ACTION LEFT THE USER, not where it found them.
  ///
  /// [entry] is stamped as it lands — as it is pushed, and as an undo or a
  /// redo moves it to the other side, so a redo finds the user where the
  /// undo left them — and stamped again once the action has settled
  /// ([settle]): before the user's next move, press or edit, and in a
  /// microtask when nothing of theirs comes first.
  ///
  /// ⚠️For every edit that does not move the user the two are one place —
  /// the case 유저 answered (「다른 행의 블록을 옮긴 것처럼 … 「서 있던 곳」으로
  /// 간다」: you stay on your row while another row's block moves). An edit
  /// that SEATS the user — a new or pasted row, the folder a fold hands the
  /// row to, a new cut — is looked at from the seat it gave. 🧪Stamped where
  /// it found them, the first undo after a paste walked back to the row the
  /// paste replaced and took nothing back (`home_frame_and_clipboard_test`).
  void stamp(Command entry) {
    // A new push or step is a new action: the one before it has settled.
    settle();
    final placeNow = this.placeNow;
    if (placeNow == null) {
      return;
    }
    final place = placeNow();
    if (place != null) {
      _places[entry] = place;
      _found[entry] ??= place;
    }
    _settling = entry;
    scheduleMicrotask(() {
      if (identical(_settling, entry)) {
        settle();
      }
    });
  }

  /// The last action has settled: its entry was made where the user stands
  /// now. Once per entry.
  void settle() {
    final entry = _settling;
    _settling = null;
    final placeNow = this.placeNow;
    if (entry == null || placeNow == null) {
      return;
    }
    final place = placeNow();
    if (place != null) {
      _places[entry] = place;
    }
  }

  /// What a walk lets go of, landed where the user still stands — set by
  /// whoever holds a hand, as `HistoryManager.onBeforeUndoRedo` is.
  ///
  /// 🗣️For a hand the user WALKS OFF (I-41's 「그곳으로 이동해서 편집되돌리고」,
  /// 유저 2026-09-24): a text in hand lands on its cel, and its edit is
  /// where they stood holding it — where the first undo has to walk.
  ///
  /// ↩️It landed AFTER the walk until 2026-10-29, once another cel was
  /// under the tool, stamped back where it was held (`madeAt`). But by then
  /// the canvas was the walk's: into a gap, or a cut of another size, the
  /// text landed on a blank of THAT size and the cel lost everything else
  /// it carried (board `a-text-walked-into-a-gap-lands-at-its-size`).
  /// Landed here, at the door, the walk has not happened yet.
  VoidCallback? onLeave;

  /// The user walks off where they stand — what every door that moves them
  /// does first (`EditorSessionManager.selectCut` and the rest): what is
  /// in hand lands HERE ([onLeave]), and the last action settles here
  /// ([settle]).
  void leave() {
    onLeave?.call();
    settle();
  }
}

/// The way back from an undo that walked to an edit (I-41): redone, it
/// walks the user back to where they stood. It is never an edit, so it
/// never reaches the undo side (`HistoryManager.leaveWalkBack`).
class WalkBack implements Command {
  WalkBack(this._walk);

  final VoidCallback _walk;

  @override
  String get description => 'Walk back';

  @override
  void execute() => _walk();

  /// Never called: a walk back leaves the redo side only by being redone,
  /// and a redone one is spent.
  @override
  void undo() {}
}
