import 'dart:async';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;

/// 「Is this click the second of a double click?」 — the ONE answer for a
/// control a press may also drag, or that answers its press itself
/// (`PressClaim`): a press that lands while the previous click's
/// [kDoubleTapTimeout] still runs IS the second click, and its click is the
/// double click.
///
/// ⛔**NO DISTANCE IS COMPARED** — a press that wandered is still the press
/// it was, the answer the claim gives a button (`control_press_claim.dart`,
/// 유저 2026-08-30 「1px 이동했는지 같은 px 이동으로 판단하는거 … 싹 깔끔하게
/// 걷어내」 · I-177 11-17 「몇px로 더블클릭하면같은 과거에 몇번이나
/// 문제시했던거 하지말고 막대안에서 더블클릭 일어나면」). ⛔And not a
/// `DoubleTapGestureRecognizer`: a drag that accepts on the first movement
/// wins the arena and rejects it — 🧪two presses that each moved two pixels
/// reset nothing, on a pen, a finger and a mouse alike (the dock splitter's
/// grip, which met it first).
///
/// ⛔**IT HOLDS NO PRESS BACK.** Each click does what a click does when it
/// comes; the second does that and then the double click's. The time is the
/// frame panels' own double click's ([kDoubleTapTimeout] — the recognizer
/// `TimelineDoubleTapGate` stands behind), as 유저 asked of every double
/// click there (I-48, 2026-09-26 「시간간격같은거 프레임블록 로직 그대로
/// 재사용/법통일」).
///
/// 🚨Three controls spelled this each for itself — the dock splitter's grip,
/// a colour place's edit, and a rail bar's typing (I-177) came third — so it
/// is one now (CLAUDE.md, the rule of three).
class SecondClickWindow {
  Timer? _window;
  bool _second = false;

  /// A press came down: the second click's, where the previous click's
  /// window still runs. The window closes either way, so a press that comes
  /// to no click — cancelled, or let go away from the control — leaves the
  /// next one a first.
  void pressed() {
    _second = _window?.isActive ?? false;
    _window?.cancel();
  }

  /// The press came up a click: whether it is the second of a double click.
  /// The first opens the window the second must land in.
  bool clicked() {
    if (_second) {
      _second = false;
      return true;
    }
    _window = Timer(kDoubleTapTimeout, () {});
    return false;
  }

  /// Lets the window go with its owner.
  void dispose() => _window?.cancel();
}
