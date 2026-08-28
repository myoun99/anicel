import 'package:flutter/widgets.dart';

import 'value_control_pointers.dart';

/// 🚨★★★A PRESS THAT LANDS ON A CONTROL BELONGS TO THAT CONTROL.
///
/// The law is in CLAUDE.md and 유저 has stated it three times — 2026-08-14
/// for sliders (「슬라이더위에서 조작하기 시작하면 슬라이더조작하는거고 **그
/// 외가 스크롤인거야**」), 08-28 for buttons, and 08-29:
///
/// > 「**터치 좌표가 버튼인데 거기서 움직였다고 스크롤이 발생하는게 심각한
/// > 버그야**」
///
/// This widget IS the law's code. It takes the WEAK claim — a button owns
/// its TAP, not every drag from it — which is enough, because
/// [EagerPanGestureRecognizer] declines any pointer either claim holds.
///
/// ⛔IT DOES NOT LIVE IN THE TIMELINE. It used to, as `RailControlPointer`
/// in `layer_label_controls.dart`, and the name plus the address is why the
/// x-sheet's toggles, the top strip's blend lock and the toolbar's 1·2·3·4·N
/// were still bare on 2026-08-29: a surface that is not the rail does not go
/// looking in a rail file for a rule that turns out to be the whole app's.
/// [AppIconButton] wrote the same three lines a second time for the same
/// reason. One home, so a button anywhere can wear it.
///
/// ⚠️Nesting is safe and the rail relies on it: the claims are `Set`s, so a
/// second claim on the same pointer is a no-op and both wrappers release on
/// the same event ([RailSwipeColumnPointer] adds the strong claim over this
/// one).
class ControlPressClaim extends StatelessWidget {
  const ControlPressClaim({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) => claimTapForControl(event.pointer),
      onPointerUp: (event) => releaseTapForControl(event.pointer),
      // ⛔Cancel too: a claim that outlives its gesture silently deafens
      // every later press handed the same pointer id.
      onPointerCancel: (event) => releaseTapForControl(event.pointer),
      child: child,
    );
  }
}
