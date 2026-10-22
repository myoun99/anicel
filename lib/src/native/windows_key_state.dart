import 'dart:ffi';
import 'dart:io' show Platform;

/// Whether Windows says the key [virtualKey] is down: `GetKeyState`, the
/// state as of the last message this thread read — the record the engine
/// itself syncs its own to before every key event. False wherever it cannot
/// be asked: every platform but Windows.
///
/// Asked of `user32` straight, as the screen reader is
/// (`windowsScreenReaderRunning`): the engine has no channel for it. The
/// app's Dart runs on the window's own thread (the engine merges the two),
/// so this thread is the one whose messages Windows counted.
bool windowsKeyIsDown(int virtualKey) {
  final ask = _getKeyState;
  return ask != null && ask(virtualKey) < 0;
}

/// `VK_SHIFT` · `VK_CONTROL` · `VK_MENU` (Alt) · `VK_LWIN` · `VK_RWIN`
/// (winuser.h) — either side of the key, for the first three.
const int vkShift = 0x10;
const int vkControl = 0x11;
const int vkMenu = 0x12;
const int vkLeftWindows = 0x5B;
const int vkRightWindows = 0x5C;

/// `GetKeyState`, looked up once — null where there is no `user32`. A key
/// that is down sets the high bit of the SHORT it answers.
final int Function(int)? _getKeyState = _lookUpGetKeyState();

int Function(int)? _lookUpGetKeyState() {
  if (!Platform.isWindows) {
    return null;
  }
  try {
    return DynamicLibrary.open(
      'user32.dll',
    ).lookupFunction<Int16 Function(Int32), int Function(int)>('GetKeyState');
  } on Object {
    return null;
  }
}
