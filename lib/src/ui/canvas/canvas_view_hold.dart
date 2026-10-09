import 'package:flutter/material.dart';

/// What a press on the canvas does while a key of the view is held.
enum ViewHold {
  /// 「이동」 (I-15): the press pans.
  pan,

  /// 「회전」 (I-88): the press turns the view about its middle.
  turn,
}

/// The view hold in force, or null — which key of the view is held.
///
/// 🗣️유저 2026-09-11 (I-15): 「단축키에 이동? 추가하는건 추가하고, 기본값을
/// 휠클릭이 아니라 스페이스바로 이동」. While it is held, a primary press on
/// ANY canvas panel pans — the same pan a wheel click mapped to 이동 starts,
/// held from the keyboard — and the panel's tools stand down for it.
/// 🗣️I-88 (유저 2026-10-09): 「지금 스페이스바는 이동이니까
/// 스페이스바+컨트롤상태에선 회전으로 작동하도록」 — the other hold: the press
/// turns the view, and the tools stand down the same way. ONE value, so the
/// view is never held for both at once.
///
/// ⚠️App-wide and static, like the app-wide touch census: a key is held for
/// the app, not for one panel, and every panel reads the same answer.
/// Written only by the shell's held keys (`EditorKeyHolds`).
abstract final class CanvasViewHold {
  static final ValueNotifier<ViewHold?> held = ValueNotifier<ViewHold?>(null);
}

/// While a key of the view is held, [child] takes no pointer and the hand
/// says what a press will do — every tool under it stands down at once.
///
/// The canvas's deck and every panel that pans the canvas's way (R26 #34)
/// stand down through this one gate; the pan or the turn itself is heard
/// ABOVE it, by a translucent listener that still receives the press.
class ViewHoldGate extends StatelessWidget {
  const ViewHoldGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ViewHold?>(
    valueListenable: CanvasViewHold.held,
    builder: (context, held, deck) => MouseRegion(
      opaque: false,
      cursor: held == null ? MouseCursor.defer : SystemMouseCursors.grab,
      child: IgnorePointer(ignoring: held != null, child: deck),
    ),
    child: child,
  );
}
