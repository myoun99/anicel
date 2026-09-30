import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

const _key = ValueKey<String>('yes-no');
const _words = (on: 'Filled', off: 'Left empty for now');

Future<void> _pump(
  WidgetTester tester, {
  required bool on,
  ValueChanged<bool>? onChanged,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: TogglePill(
          keyValue: 'yes-no',
          on: on,
          words: _words,
          onChanged: onChanged,
        ),
      ),
    ),
  ),
);

Pill _pill(WidgetTester tester) =>
    tester.widget<Pill>(find.byKey(_key));

/// The word the pill paints — the one NOT set in no colour to hold the
/// width.
String _shownWord(WidgetTester tester) {
  final shown = [
    for (final text in tester.widgetList<Text>(
      find.descendant(of: find.byKey(_key), matching: find.byType(Text)),
    ))
      if ((text.style?.color?.a ?? 1) > 0) text.data!,
  ];
  expect(shown, hasLength(1), reason: 'the pill paints exactly one word');
  return shown.single;
}

void main() {
  testWidgets('on, the pill is lit and says the ON word; off, it is plain '
      'and says the OFF word (유저 09-25 「강조색/칠함 … 일반색/비움」)', (
    tester,
  ) async {
    await _pump(tester, on: true, onChanged: (_) {});
    expect(_pill(tester).selected, isTrue);
    expect(_shownWord(tester), _words.on);

    await _pump(tester, on: false, onChanged: (_) {});
    expect(_pill(tester).selected, isFalse);
    expect(_shownWord(tester), _words.off);
  });

  testWidgets('a press reports the flipped value', (tester) async {
    final reported = <bool>[];
    await _pump(tester, on: true, onChanged: reported.add);
    await tester.tap(find.byKey(_key));
    await _pump(tester, on: false, onChanged: reported.add);
    await tester.tap(find.byKey(_key));
    expect(reported, [false, true]);
  });

  testWidgets('the pill keeps ONE width whichever word it says, so the next '
      'press lands where the last one did', (tester) async {
    await _pump(tester, on: true, onChanged: (_) {});
    final whileOn = tester.getSize(find.byKey(_key));
    await _pump(tester, on: false, onChanged: (_) {});
    final whileOff = tester.getSize(find.byKey(_key));
    expect(whileOn, whileOff);
  });

  testWidgets('refused, it keeps its word and its place and takes no press', (
    tester,
  ) async {
    await _pump(tester, on: false);
    expect(_pill(tester).onTap, isNull);
    expect(_shownWord(tester), _words.off);
    await tester.tap(find.byKey(_key));
    await tester.pump();
    expect(_shownWord(tester), _words.off);
  });
}
