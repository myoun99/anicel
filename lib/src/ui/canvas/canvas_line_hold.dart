import 'package:flutter/foundation.dart';

/// Whether the key of 「직전 획에서 직선」 is held (I-119).
///
/// 🗣️유저 2026-10-21: 「브러시 도구(브러시,지우개) 전용기능, …
/// 누르고있으면 저번에 찍은 마지막 dab? 점 부터 현재 호버중인 커서까지
/// 라이브로 직선 보여주고 … 거기서 찍으면 직선 그림」 — I-119-Q2: 「도중에
/// … 키를 떼면 취소임」. While it is held a canvas whose tool paints runs a
/// line from its last stroke to the hand; let go, the line goes.
///
/// ⚠️App-wide and static, as the view's hold is (`CanvasViewHold`): a key
/// is held for the app, not for one panel. Written only by the shell's held
/// keys (`EditorKeyHolds`).
abstract final class CanvasLineHold {
  static final ValueNotifier<bool> held = ValueNotifier<bool>(false);
}
