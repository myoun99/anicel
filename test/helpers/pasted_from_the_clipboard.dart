import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pastes [text] into the field [field] finds as a person does: the
/// platform's clipboard holds it, and the field is focused and handed the
/// paste keys — Flutter reads the clipboard and the field takes what its
/// formatters keep (`EditableTextState.pasteText`).
///
/// A Windows clipboard ends its lines in CR LF ([windowsLines]).
Future<void> pasteInto(WidgetTester tester, Finder field, String text) async {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    return switch (call.method) {
      'Clipboard.getData' => <String, dynamic>{'text': text},
      'Clipboard.hasStrings' => <String, dynamic>{'value': true},
      _ => null,
    };
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  await tester.showKeyboard(field);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// [lines] as a Windows clipboard holds them: each line ended in CR LF.
String windowsLines(List<String> lines) => lines.join('\r\n');
