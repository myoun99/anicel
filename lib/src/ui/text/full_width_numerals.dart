import 'package:flutter/services.dart';

/// R9 #15 — full-width numerals become half-width AS THEY ARE TYPED.
///
/// A Japanese IME sits in 全角 for ordinary text, and the user types a
/// frame count without leaving it. The app then rejected the input
/// outright: `FilteringTextInputFormatter.digitsOnly` does not consider
/// `１` a digit, and `int.tryParse('１２')` is null. Nothing was wrong with
/// what they typed — the field simply refused Japanese numerals.
///
/// Converting at INPUT time is the local convention, and it is also what
/// makes this ONE change enough: no parse site anywhere can see a
/// full-width numeral afterwards, so none of them needs its own guard.
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

/// The formatter form. Length is preserved (one code unit for one), so the
/// selection survives untouched — the caret does not jump to the end while
/// the user is still typing.
class HalfWidthNumeralsFormatter extends TextInputFormatter {
  const HalfWidthNumeralsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final converted = toHalfWidthNumerals(newValue.text);
    if (converted == newValue.text) {
      return newValue;
    }
    return newValue.copyWith(text: converted);
  }
}

/// THE integer-field formatter list: convert first, then filter. Order is
/// the whole point — `digitsOnly` ahead of the conversion would delete the
/// full-width numerals before they could become digits, which is exactly
/// the behaviour the user reported.
final List<TextInputFormatter> halfWidthDigitsOnly = List.unmodifiable([
  const HalfWidthNumeralsFormatter(),
  FilteringTextInputFormatter.digitsOnly,
]);

/// The decimal-field formatter: conversion alone, so signs, points and
/// units the field's own parser understands still come through.
const List<TextInputFormatter> halfWidthNumerals = [
  HalfWidthNumeralsFormatter(),
];
