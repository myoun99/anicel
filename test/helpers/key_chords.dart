import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wait_window.dart' show waitOutTheWaitWindow;

/// [key] pressed with Ctrl held, as a hand presses it: Ctrl down, the key,
/// Ctrl up — and a frame for whatever heard it. A press that stood behind
/// the app's wait window (F-551: the copy, the paste, the cut) is waited
/// out, as the hand waits for it before its next key.
Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await waitOutTheWaitWindow(tester);
}
