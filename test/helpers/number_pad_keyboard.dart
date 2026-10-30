import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/number_pad.dart';

/// The open number pad's (`showNumberPad`) part [name]: `number` at its
/// top, or a key — `minus`, `point`, a digit, `backspace`, `enter`.
Finder _thePads(String name) => find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.endsWith('-pad-$name'),
    _ => false,
  },
);

/// The number at the top of the open number pad.
final Finder theNumberPadsNumber = _thePads('number');

/// Whether the open number pad's key [name] takes a press: a key its value
/// cannot take is dark.
bool thePadsKeyIsLit(WidgetTester tester, String name) =>
    tester.widget<AppIconButtonFace>(_thePads(name)).onPressed != null;

/// Which of the open number pad's − and . take a press ([NumberPadKeys]).
NumberPadKeys thePadsLitKeys(WidgetTester tester) => (
  minus: thePadsKeyIsLit(tester, 'minus'),
  point: thePadsKeyIsLit(tester, 'point'),
);

/// Presses the number at the top of the number pad a pencil opened, which
/// brings the keyboard up on it, all of it selected — the way a hand types
/// a number with the keyboard (I-134). The field it types into keeps the
/// key its host gave it (`<keyValue>-input`).
///
/// Two frames: the field takes the keyboard in the frame after the one it
/// is built in, and only then hears a press away from it — one frame would
/// press the pad's keys while no press could close it.
Future<void> openThePadsKeyboard(WidgetTester tester) async {
  await tester.tap(theNumberPadsNumber);
  await tester.pump();
  await tester.pump();
}

/// Types [text] as a hand types the number of the readout [keyValue]
/// (`DragValueLabel`, `WindowNumber`): its pencil, the pad's number pressed
/// for the keyboard, the text, Enter. Settles once the pad is gone.
Future<void> typeOnThePad(
  WidgetTester tester,
  String keyValue,
  String text,
) async {
  await tester.tap(find.byKey(ValueKey<String>('$keyValue-edit')));
  await tester.pumpAndSettle();
  await openThePadsKeyboard(tester);
  await tester.enterText(find.byKey(ValueKey<String>('$keyValue-input')), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}
