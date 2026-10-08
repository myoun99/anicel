import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// [key] pressed with Ctrl held, as a hand presses it: Ctrl down, the key,
/// Ctrl up — and a frame for whatever heard it.
Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}
