import 'package:flutter/foundation.dart';

import '../models/cut_piece.dart';

/// The one piece the cut tool is holding.
///
/// ONE slot, deliberately. The user's objection to the first design was that
/// cutting would grow the brush tip library every time; Photoshop, Clip
/// Studio and TVPaint all answer that the same way — the everyday piece is
/// transient and unnamed, and getting into a library is a separate explicit
/// command. TVPaint's `Tool History` is the counter-example that proves it:
/// it accumulates unnamed near-duplicates automatically and its own users
/// gave up on it as a store.
///
/// Lifetime (유저 확정 2026-08-12): the piece survives switching tools,
/// frames, cuts — and PROJECTS. "다른 프로젝트에 붙여넣고 싶을 수 있으니."
/// Only quitting the app loses it. So this must NOT be cleared alongside the
/// frame/layer clipboards on project load, and it must never hold a
/// reference into the project it came from — [CutPiece] is a raw pixel copy
/// for exactly that reason.
class CutPieceSlot extends ChangeNotifier {
  CutPiece? _piece;

  CutPiece? get piece => _piece;

  bool get isEmpty => _piece == null;
  bool get isNotEmpty => _piece != null;

  /// Fills the slot, replacing whatever was held.
  ///
  /// Replacing is the whole of "cut again" (유저: "잘라내기 할 때마다 가지고
  /// 있는 찍기 팁 교체야") — there is no accumulate mode and no combine mode,
  /// because the cut drag makes no selection for a mode to combine WITH.
  void hold(CutPiece piece) {
    _piece = piece;
    notifyListeners();
  }

  /// Re-poses the held piece. No-op when the slot is empty, so the settings
  /// panel can wire its knobs without null-guarding each one.
  void updatePose({bool? flipHorizontal, bool? flipVertical, int? scalePercent}) {
    final current = _piece;
    if (current == null) {
      return;
    }
    final next = current.copyWith(
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
      scalePercent: scalePercent,
    );
    if (next.flipHorizontal == current.flipHorizontal &&
        next.flipVertical == current.flipVertical &&
        next.scalePercent == current.scalePercent) {
      return;
    }
    _piece = next;
    notifyListeners();
  }

  /// Drops the pose, keeps the pixels — the Reset button.
  void resetPose() {
    final current = _piece;
    if (current == null || !current.isPosed) {
      return;
    }
    _piece = current.reset();
    notifyListeners();
  }

  /// Installed by the mounted canvas panel, which is the only thing that
  /// can reach a cel to write into. Null while no canvas is up.
  ///
  /// The same imperative-channel shape the selection commands already use:
  /// the tool settings panel and the canvas live in different subtrees, and
  /// threading a callback down and an action back up through both would be
  /// more wiring than a slot the canvas fills in.
  void Function({required bool behind})? pasteAtOriginHandler;

  /// True when a canvas is mounted AND something is held — what the paste
  /// buttons gate on.
  bool get canPasteAtOrigin => pasteAtOriginHandler != null && isNotEmpty;

  void pasteAtOrigin({required bool behind}) =>
      pasteAtOriginHandler?.call(behind: behind);

  /// Empties the slot. Nothing in the shipped UI calls this yet: the piece
  /// is meant to sit there until the next cut replaces it, and a stray
  /// "scrape an empty area" must NOT wipe it — the slot is a long-term
  /// holder, not a scratch buffer. Kept for tests and for a future explicit
  /// clear command.
  @visibleForTesting
  void clear() {
    if (_piece == null) {
      return;
    }
    _piece = null;
    notifyListeners();
  }
}
