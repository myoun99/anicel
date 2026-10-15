import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/full_width_numerals.dart';

import '../../helpers/dart_sources.dart';

/// R9 #15 — a Japanese IME sitting in 全角 types numerals the app used to
/// refuse outright: `digitsOnly` does not consider `１` a digit, and
/// `int.tryParse('１２')` is null.
///
/// 🐛F-355 (유저 2026-10-13): 「５０이라고 입력할때 숫자가 두번 등록되는거같은?」
/// — converting a numeral while the IME still composed it doubled what was
/// typed next on Windows. The field converts what the IME COMMITS, and
/// whatever reads a number field reads its numerals half-width.
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

  test('halfWidthInt reads a number field\'s whole number, full-width or '
      'not, around its spaces', () {
    expect(halfWidthInt('５０'), 50);
    expect(halfWidthInt(' １２ '), 12);
    expect(halfWidthInt('－３'), -3);
    expect(halfWidthInt('34'), 34);
    expect(halfWidthInt('５ａ'), isNull);
    expect(halfWidthInt(''), isNull);
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

    test('🚨a draft the IME is still composing comes back as it is — '
        'changed, it doubled what was typed next', () {
      const draft = TextEditingValue(
        text: '５０',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, draft),
        same(draft),
      );
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

  test('the integer list leaves a draft whole — what it would drop too — '
      'and filters it once committed', () {
    TextEditingValue format(TextEditingValue value) {
      for (final formatter in halfWidthDigitsOnly) {
        value = formatter.formatEditUpdate(TextEditingValue.empty, value);
      }
      return value;
    }

    const draft = TextEditingValue(
      text: '５ａ',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    expect(format(draft).text, '５ａ');
    expect(
      format(draft.copyWith(composing: TextRange.empty)).text,
      '5',
    );
  });

  test('the range list converts the minus between two numbers', () {
    var value = const TextEditingValue(text: '１－２０ａ');
    for (final formatter in halfWidthNumberRanges) {
      value = formatter.formatEditUpdate(TextEditingValue.empty, value);
    }
    expect(value.text, '1-20');
  });

  group('every number field keeps this law', () {
    test('a filter of what is typed is a number field\'s, run on what the '
        'IME commits — no file but the law hands one to a field', () {
      final strays = [
        for (final file in dartFilesUnder('lib'))
          if (libPath(file) != 'lib/src/ui/text/full_width_numerals.dart' &&
              file.readAsStringSync().contains('FilteringTextInputFormatter'))
            libPath(file),
      ];
      expect(
        strays,
        isEmpty,
        reason: 'a filter of its own touches the draft the IME is composing '
            '— on Windows that doubles what is typed next (F-355)',
      );
    });

    test('every field with a number pad takes full-width numerals', () {
      final numberPads = [
        for (final file in dartFilesUnder('lib'))
          if (RegExp(
            r'TextInputType\.number|numberWithOptions',
          ).hasMatch(file.readAsStringSync()))
            file,
      ];
      expect(numberPads, isNotEmpty, reason: '⛔the scan measured nothing');
      final strays = [
        for (final file in numberPads)
          if (!file.readAsStringSync().contains('full_width_numerals.dart'))
            libPath(file),
      ];
      expect(strays, isEmpty);
    });
  });
}
