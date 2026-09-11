import 'package:flutter/foundation.dart';

/// Whether the key bound to 「이동」 is held (I-15).
///
/// 🗣️유저 2026-09-11: 「단축키에 이동? 추가하는건 추가하고, 기본값을
/// 휠클릭이 아니라 스페이스바로 이동」. While it is held, a primary press on
/// ANY canvas panel pans — the same pan a wheel click mapped to 이동 starts,
/// held from the keyboard — and the panel's tools stand down for it.
///
/// ⚠️App-wide and static, like the app-wide touch census: a key is held for
/// the app, not for one panel, and every panel reads the same answer.
/// Written only by the shell's held keys (`EditorKeyHolds`).
abstract final class CanvasPanHold {
  static final ValueNotifier<bool> held = ValueNotifier<bool>(false);
}
