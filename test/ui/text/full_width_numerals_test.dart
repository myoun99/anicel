import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/app_prompt_dialog.dart';
import 'package:anicel/src/ui/text/full_width_numerals.dart';

/// R9 #15 — a Japanese IME sitting in 全角 types numerals the app used to
/// refuse outright: `digitsOnly` does not consider `１` a digit, and
/// `int.tryParse('１２')` is null. Converting at INPUT time is the local
/// convention, and it is what makes one change enough — no parse site can
/// see a full-width numeral afterwards.
void main() {
  group('toHalfWidthNumerals', () {
    test('numerals, the decimal point and the minus sign convert', () {
      expect(toHalfWidthNumerals('１２３'), '123');
      expect(toHalfWidthNumerals('０９'), '09');
      expect(toHalfWidthNumerals('１．５'), '1.5');
      expect(toHalfWidthNumerals('－１２'), '-12');
    });

    test('everything else is left alone', () {
      expect(toHalfWidthNumerals('12'), '12');
      expect(toHalfWidthNumerals(''), '');
      expect(
        toHalfWidthNumerals('カット１２'),
        'カット12',
        reason: 'only the numerals convert — the text around them is text',
      );
    });

    test('the converted text parses, which the original never did', () {
      expect(int.tryParse('１２'), isNull);
      expect(int.tryParse(toHalfWidthNumerals('１２')), 12);
      expect(double.tryParse(toHalfWidthNumerals('－１．５')), -1.5);
    });
  });

  group('the formatter', () {
    const formatter = HalfWidthNumeralsFormatter();

    TextEditingValue format(String text, {int? selection}) =>
        formatter.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(
              offset: selection ?? text.length,
            ),
          ),
        );

    test('converts in place and leaves the caret where it was', () {
      final result = format('１２３', selection: 2);
      expect(result.text, '123');
      expect(
        result.selection.baseOffset,
        2,
        reason: 'one code unit for one, so the caret does not jump to the '
            'end while the user is still typing',
      );
    });

    test('untouched text comes back as the SAME value', () {
      final value = format('123');
      expect(value.text, '123');
    });
  });

  test('the integer list converts BEFORE it filters — the order is the '
      'whole point', () {
    var value = const TextEditingValue(text: '１２a３');
    for (final formatter in halfWidthDigitsOnly) {
      value = formatter.formatEditUpdate(TextEditingValue.empty, value);
    }
    expect(
      value.text,
      '123',
      reason: 'digitsOnly ahead of the conversion would delete the '
          'full-width numerals before they could become digits — exactly '
          'the behaviour the user reported',
    );
  });

  testWidgets('the shared numeric prompt accepts 全角 digits', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppPromptDialog(
            title: 'Frames',
            fieldLabel: 'Count',
            initialValue: '',
            confirmLabel: 'Set',
            numeric: true,
            fieldKey: ValueKey<String>('prompt-field'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('prompt-field')),
      '１２',
    );
    await tester.pumpAndSettle();

    expect(find.text('12'), findsOneWidget);
  });
}
