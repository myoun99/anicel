import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'focused_text_field.dart';

/// 🗣️I-19 ④ (유저 2026-09-13): 「일본어 키보드나 한국어 상태등 키보드가
/// 영어가 아닐때도 대응하도록」 — 「숏컷 얘기임. 지금은 일본어 히라가나상태로
/// 치면 이상한 텍스트입력기? 같은 게 뜸.」
///
/// 🔬WHY NO SHORTCUT SEES THOSE KEYS. Flutter's Windows engine drops every
/// key press an IME takes — its `KeyboardHookImpl` reads VK_PROCESSKEY as
/// 「the key press is used by an IME. These key presses are considered
/// handled and not sent to Flutter」 — and it never turns a window's IME
/// off: `flutter_windows.dll` imports no `ImmAssociateContextEx` (read
/// 2026-09-23). So with a Japanese or Korean IME composing, `B` reaches no
/// shortcut table, text field or not, and the IME composes into a window of
/// its own — the 「이상한 텍스트입력기」.
///
/// ★So the IME listens exactly while a text field does — the question the
/// shortcut manager already asks before a field may keep a key
/// ([focusedTextField]) — and is off everywhere else, where a key is a
/// command. The field gets the IME back in the mode the user left it in.
///
/// ⚠️WINDOWS ONLY, because the loss is the Windows engine's: macOS hands a
/// key to the framework's responders BEFORE its text system
/// (`FlutterKeyboardManager.performProcessEvent`, read 2026-09-23).
///
/// The runner does the switching (`windows/runner/flutter_window.cpp`);
/// `the_ime_listens_only_with_a_text_field_test.dart` reads its literals, so
/// neither half can drift from the other unseen.
class KeyboardImeSwitch {
  KeyboardImeSwitch._();

  /// The runner's channel and its one method, spelled again in
  /// `windows/runner/flutter_window.cpp`.
  static const channel = MethodChannel('anicel/keyboard');
  static const setImeOpen = 'setImeOpen';

  /// Follows focus from now on; null off Windows. Once, from `main()`.
  static KeyboardImeSwitch? install() {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return null;
    }
    final ime = KeyboardImeSwitch._();
    FocusManager.instance.addListener(ime._follow);
    ime._follow();
    return ime;
  }

  bool? _open;

  void _follow() {
    final open = focusedTextField() != null;
    if (open == _open) {
      return;
    }
    _open = open;
    unawaited(channel.invokeMethod<void>(setImeOpen, open));
  }

  /// Stops following focus — for a test; the app never lets go.
  void uninstall() => FocusManager.instance.removeListener(_follow);
}
