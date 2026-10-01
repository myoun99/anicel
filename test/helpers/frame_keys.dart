import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The frame keys as a hand presses them — Shift and the arrow along the
/// timeline's frames (F-241: 「이전/다음 프레임은 ,.가 아니라 쉬프트<>만」).
/// On an X-sheet the same keys are read turned, so a test that means the
/// sheet's own arrow presses it with [arrow].
Future<void> pressNextFrame(
  WidgetTester tester, {
  LogicalKeyboardKey arrow = LogicalKeyboardKey.arrowRight,
}) => _shifted(tester, arrow);

Future<void> pressPreviousFrame(
  WidgetTester tester, {
  LogicalKeyboardKey arrow = LogicalKeyboardKey.arrowLeft,
}) => _shifted(tester, arrow);

Future<void> _shifted(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}
