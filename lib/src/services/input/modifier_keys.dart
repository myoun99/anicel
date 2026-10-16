import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../../native/windows_key_state.dart';

/// WHETHER A MODIFIER KEY IS HELD — asked here, and answered the same
/// whatever the pointer: a mouse, a pen, a finger.
///
/// 🗣️I-61 (유저 2026-10-16): 「마우스로는 작동하는거 확인했는데 왜 펜으로는
/// 작동안하는지? 마우스던 펜이던 터치묘화던 그림 그리는 동작이라면
/// 해야하는건데 왜 이렇게 로직이 나뉘어져버린건지?」 — the stroke asked Shift
/// at one place for every pointer, and a pen's stroke still never locked:
/// the answer it was given was wrong.
///
/// 🚨NOT [HardwareKeyboard] ALONE. Its record is the engine's, and the
/// Windows engine (Flutter 3.47.4, `flutter_window.cc`) hands every pen and
/// touch move over with no modifiers (`/* modifiers_state=*/0`) and syncs
/// its record to that (`SyncModifiersIfNeeded`): Shift and Ctrl are let go
/// of — a synthesized key-up — the moment a pen hovers or a finger moves,
/// with the key still down, and the real release that comes after is
/// dropped as one already made. A mouse move carries the keys (`MK_SHIFT`,
/// `MK_CONTROL`), which is why a mouse held Shift and a pen did not. The
/// macOS and Linux engines sync to what each event says; the iOS and
/// Android ones do not sync on a pointer at all. So on Windows, Windows is
/// asked too ([windowsKeyIsDown]) — what the engine itself syncs to before
/// every key event. ⛔Not only of the two the engine drops: every modifier
/// is asked the same way, so no reader has to know which.
///
/// ⚠️A widget test never touches the hardware: under `FLUTTER_TEST` the
/// machine's own keyboard is not asked, and [debugWindowsKeyDown] stands in
/// for it — on any machine.
abstract final class ModifierKeys {
  static bool get isShiftPressed =>
      HardwareKeyboard.instance.isShiftPressed || _windowsHolds(vkShift);

  static bool get isControlPressed =>
      HardwareKeyboard.instance.isControlPressed || _windowsHolds(vkControl);

  static bool get isAltPressed =>
      HardwareKeyboard.instance.isAltPressed || _windowsHolds(vkMenu);

  static bool get isMetaPressed =>
      HardwareKeyboard.instance.isMetaPressed ||
      _windowsHolds(vkLeftWindows) ||
      _windowsHolds(vkRightWindows);

  /// The keyboard as a shortcut's activator reads it (`accepts`): the
  /// engine's record, with each modifier these getters say is held put
  /// back where the record let go of it.
  static final HardwareKeyboard keyboard = _HeldKeyboard();

  /// Stands in for what Windows says of a virtual key, in a test.
  @visibleForTesting
  static bool Function(int virtualKey)? debugWindowsKeyDown;

  static final bool _underTest =
      Platform.environment['FLUTTER_TEST'] == 'true';

  static bool _windowsHolds(int virtualKey) {
    final standIn = debugWindowsKeyDown;
    if (standIn != null) {
      return standIn(virtualKey);
    }
    return !_underTest && windowsKeyIsDown(virtualKey);
  }
}

/// [HardwareKeyboard]'s record as [ModifierKeys] answers it — what a
/// shortcut's activator is handed when the modifiers it reads must be the
/// held ones. A modifier put back is put back as its left key: an
/// activator asks for either side.
///
/// ⚠️A view to be read, not a keyboard: no event is ever dispatched to it,
/// and its physical keys are the record's.
final class _HeldKeyboard extends HardwareKeyboard {
  HardwareKeyboard get _record => HardwareKeyboard.instance;

  @override
  Set<LogicalKeyboardKey> get logicalKeysPressed {
    final record = _record;
    return {
      ...record.logicalKeysPressed,
      if (!record.isShiftPressed && ModifierKeys.isShiftPressed)
        LogicalKeyboardKey.shiftLeft,
      if (!record.isControlPressed && ModifierKeys.isControlPressed)
        LogicalKeyboardKey.controlLeft,
      if (!record.isAltPressed && ModifierKeys.isAltPressed)
        LogicalKeyboardKey.altLeft,
      if (!record.isMetaPressed && ModifierKeys.isMetaPressed)
        LogicalKeyboardKey.metaLeft,
    };
  }

  @override
  bool isLogicalKeyPressed(LogicalKeyboardKey key) =>
      logicalKeysPressed.contains(key);

  @override
  Set<PhysicalKeyboardKey> get physicalKeysPressed =>
      _record.physicalKeysPressed;

  @override
  bool isPhysicalKeyPressed(PhysicalKeyboardKey key) =>
      _record.isPhysicalKeyPressed(key);

  @override
  LogicalKeyboardKey? lookUpLayout(PhysicalKeyboardKey physicalKey) =>
      _record.lookUpLayout(physicalKey);

  @override
  Set<KeyboardLockMode> get lockModesEnabled => _record.lockModesEnabled;
}
