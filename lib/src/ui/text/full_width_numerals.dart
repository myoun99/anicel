import 'package:flutter/services.dart';

/// R9 #15 — full-width numerals are numerals.
///
/// A Japanese IME sits in 全角 for ordinary text, and the user types a
/// frame count without leaving it. The app then rejected the input
/// outright: `FilteringTextInputFormatter.digitsOnly` does not consider
/// `１` a digit, and `int.tryParse('１２')` is null. Nothing was wrong with
/// what they typed — the field simply refused Japanese numerals.
///
/// 🐛F-355 (유저 2026-10-13): 「５０이라고 입력할때 숫자가 두번 등록되는거같은?
/// 5500 이런식으로」. The numerals were converted AS THEY WERE TYPED — while
/// the IME was still composing them — and on Windows a draft the app
/// changes is a draft the engine forgets: the change ends its composing
/// (`TextInputModel::SetText`), and the IME's next draft is then laid in
/// beside the old one, twice. ↩️Converting at input time was what let no
/// parse site need a guard. A draft is the IME's, so the law has two
/// halves now, both here:
///
/// · The FIELD shows them half-width once the IME commits them — Enter, or
///   its own confirm ([HalfWidthNumeralsFormatter]). Nothing touches a
///   draft.
/// · Whatever READS a number field's text reads its numerals half-width
///   ([toHalfWidthNumerals] · [halfWidthInt]) — so a draft counts as the
///   number it shows, and so does one a field lost the focus in the middle
///   of: Flutter commits that one as it is, past the formatters.
///
/// The range is the numerals plus the two marks that ride with them in a
/// number: U+FF10–FF19, U+FF0E (．) and U+FF0D (－).
const int _fullWidthZero = 0xFF10;
const int _fullWidthNine = 0xFF19;
const int _fullWidthFullStop = 0xFF0E;
const int _fullWidthHyphenMinus = 0xFF0D;

/// Rewrites every full-width numeral, decimal point and minus sign in
/// [text] as its ASCII counterpart; everything else is left alone.
String toHalfWidthNumerals(String text) {
  if (text.isEmpty) {
    return text;
  }
  var changed = false;
  final units = text.codeUnits;
  final out = List<int>.filled(units.length, 0);
  for (var i = 0; i < units.length; i += 1) {
    final unit = units[i];
    final mapped = switch (unit) {
      >= _fullWidthZero && <= _fullWidthNine =>
        0x30 + (unit - _fullWidthZero),
      _fullWidthFullStop => 0x2E,
      _fullWidthHyphenMinus => 0x2D,
      _ => unit,
    };
    changed |= mapped != unit;
    out[i] = mapped;
  }
  return changed ? String.fromCharCodes(out) : text;
}

/// The whole number a number field's [text] says, its numerals read
/// half-width. Null where it says none.
int? halfWidthInt(String text) =>
    int.tryParse(toHalfWidthNumerals(text).trim());

/// A number field's formatter: in what the IME COMMITS, the full-width
/// numerals made half-width, and then [then] takes what the field takes of
/// it. A draft the IME is still composing comes back as it is — Flutter
/// formats again the moment it is committed.
///
/// Length is preserved (one code unit for one), so the selection survives
/// untouched — the caret does not jump to the end while the user is still
/// typing.
class HalfWidthNumeralsFormatter extends TextInputFormatter {
  const HalfWidthNumeralsFormatter({this.then});

  /// The filter, run on the CONVERTED text. Order is the whole point —
  /// `digitsOnly` ahead of the conversion would delete the full-width
  /// numerals before they could become digits, which is exactly the
  /// behaviour the user reported. Null takes it all.
  final TextInputFormatter? then;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) {
      return newValue;
    }
    final converted = toHalfWidthNumerals(newValue.text);
    final halfWidth = converted == newValue.text
        ? newValue
        : newValue.copyWith(text: converted);
    return then?.formatEditUpdate(oldValue, halfWidth) ?? halfWidth;
  }
}

/// THE integer field's formatters.
final List<TextInputFormatter> halfWidthDigitsOnly = List.unmodifiable([
  HalfWidthNumeralsFormatter(then: FilteringTextInputFormatter.digitsOnly),
]);

/// The formatters of a field of whole numbers and the ranges between them
/// — 「1-200」 — and the spaces around.
final List<TextInputFormatter> halfWidthNumberRanges = List.unmodifiable([
  HalfWidthNumeralsFormatter(
    then: FilteringTextInputFormatter.allow(RegExp(r'[\d\-\s]')),
  ),
]);

/// The decimal field's formatters: conversion alone, so signs, points and
/// units the field's own parser understands still come through.
const List<TextInputFormatter> halfWidthNumerals = [
  HalfWidthNumeralsFormatter(),
];
