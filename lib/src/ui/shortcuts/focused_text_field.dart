import 'package:flutter/widgets.dart';

/// The focused context while a TEXT FIELD holds the keyboard, else null.
///
/// ★ONE QUESTION, TWO ASKERS: the shortcut manager lets that field keep its
/// keys ([EditorShortcutManager]), and the IME listens only then
/// ([KeyboardImeSwitch]). Spelled twice, the two would answer differently
/// the day one of them learned a new kind of field.
///
/// 🚨F-22 (유저 2026-08-24: 「멤버에서 클릭해서 숫자 수동편집시 **1부터
/// 5까지의 숫자입력이 안먹히는거같음**」) — and 1…5 are the five bare-key
/// shortcuts. The shortcut guard was written for exactly this and never
/// fired once.
///
/// ⛔`primaryFocus.context.widget is EditableText` is not the test it
/// reads as. `EditableText` builds a `Focus` around itself and hands that
/// node out, so the primary focus context's own widget is that `Focus` —
/// measured, and the comparison had been false for every text field in
/// the app since it was written. Typing a digit into any field ran the
/// shortcut instead, and 'b' in a rename dialog did switch tools.
///
/// ★So ask the tree, not the node: the field is an ANCESTOR of the
/// element holding focus, which is a fact about how `EditableText` is
/// built rather than about which widget happens to own the node.
BuildContext? focusedTextField() {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) {
    return null;
  }
  final inField =
      focusContext.widget is EditableText ||
      focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  return inField ? focusContext : null;
}
