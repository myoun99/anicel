import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// F-9 — **a slider shows the value it actually has.**
///
/// 유저 2026-08-24: 「슬라이더 값에 소수점 텍스트 표시 (1.2px) … 브러시
/// 사이즈만이 아니라 조절 가능한 모든 슬라이더」.
///
/// Every panel used to `.round()` at its own call site, so a bar you could set
/// to 1.2 read `1` — and then setting it again from the number you could see
/// moved the value. Rounding is a DISPLAY choice, and it was being made
/// twenty times over by call sites that could not agree.
///
/// F-34 (유저 확정 2026-09-01) took the OTHER half of the decision away from
/// the call sites: 「슬라이더가 스스로 정한다 — 위젯이 자기 스텝을 보고
/// 자릿수를 고른다」. The bar's own digit rule is pinned in
/// `field_slider_test.dart`; what is pinned here is that the formatter keeps
/// the count it is GIVEN, at every value.
void main() {
  group('the formatter', () {
    test('it writes the digits it was given — the same count at every '
        'value, which is the whole of F-34', () {
      expect(sliderValueText(1.2, decimals: 1, unit: ' px'), '1.2 px');
      expect(sliderValueText(2, decimals: 1, unit: ' px'), '2.0 px');
      expect(sliderValueText(2.0, decimals: 0, unit: ' px'), '2 px');
      expect(sliderValueText(50, decimals: 0, unit: '%'), '50%');
    });

    test('it rounds rather than truncating', () {
      expect(sliderValueText(1.24, decimals: 1), '1.2');
      expect(sliderValueText(1.25, decimals: 1), '1.3');
      expect(sliderValueText(1.96, decimals: 1), '2.0');
      expect(sliderValueText(1.96, decimals: 0), '2');
    });

    test('a value a hair below zero does not read as a different number '
        'from the zero beside it', () {
      expect(sliderValueText(-0.2, decimals: 0, unit: '%'), '0%');
      expect(sliderValueText(-0.04, decimals: 1, unit: '%'), '0.0%');
      // ⚠️And the guard stops there: a real negative keeps its sign.
      expect(sliderValueText(-3, decimals: 0, unit: ' px'), '-3 px');
      expect(sliderValueText(-0.6, decimals: 0), '-1');
    });
  });

  /// ⚠️The formatter being right proves nothing about the panels: the bug was
  /// that each of them formatted for itself.
  test('no slider rounds its own value text', () {
    final offenders = <String>[];
    // ⛔`valueText:` is GONE from the widget — a call site cannot hand a bar
    // a preformatted number any more, and the compiler says so. What is left
    // to catch is the EXCEPTION hook rounding inside itself.
    final rounding = RegExp(r'\.round\(\)|\.toStringAsFixed\(0\)');

    for (final entry
        in Directory('lib/src/ui')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final relative = entry.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/src/ui'));
      if (key == 'lib/src/ui/widgets/field_slider.dart') {
        // The formatter itself.
        continue;
      }
      final lines = entry.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        if (!lines[i].contains('valueTextBuilder:')) {
          continue;
        }
        // The argument's own text: this line from the field name onward,
        // plus continuation lines until the NEXT named argument starts.
        // Without that stop, a neighbouring `onChanged: value.round()` —
        // which is the model's business, not the label's — reads as a hit.
        final buffer = StringBuffer(
          lines[i].substring(lines[i].indexOf('valueTextBuilder')),
        );
        final newArgument = RegExp(r'^\s*[a-zA-Z]\w*:');
        for (var j = i + 1; j < lines.length; j += 1) {
          if (newArgument.hasMatch(lines[j])) {
            break;
          }
          buffer.write(' ${lines[j]}');
        }
        if (rounding.hasMatch(buffer.toString())) {
          offenders.add('$key:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'the exception hook is handed the number the bar WOULD have '
          'written — decorate that, do not round a second one',
    );
  });

  /// 🚨THE CHEAT THAT HID FOR A MONTH. Seventeen brush rows wrote
  /// `'${(state.spacing * 100).round()}%'` into a wrapper parameter called
  /// `valueLabel`, so the scan above — which knew the name `valueText` —
  /// walked straight past them, and every one of those bars rounded a
  /// per cent the bar itself had not rounded.
  ///
  /// ⛔So this one does not look at parameter names at all — it looks for the
  /// SHAPE, in every file that builds a bar. (Scoped to those: a progress
  /// dialog writing `${(fraction * 100).round()}%` is not a slider label and
  /// has no bar to ask.)
  test('no per-cent label is built by hand where the bars are', () {
    final offenders = <String>[];
    final handRolled = RegExp(r'\$\{\(?[\w.]+ \* 100\)?\.round\(\)\}%');

    for (final entry
        in Directory('lib/src/ui')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final relative = entry.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/src/ui'));
      final lines = entry.readAsLinesSync();
      if (!lines.any((line) => line.contains('FieldSlider'))) {
        continue;
      }
      for (var i = 0; i < lines.length; i += 1) {
        // A comment may QUOTE the shape — this one's own header does.
        if (lines[i].trimLeft().startsWith('//')) {
          continue;
        }
        if (handRolled.hasMatch(lines[i])) {
          offenders.add('$key:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'pass the bar a unit and a displayScale: the DIGITS are the '
          "bar's own, from its own step (F-34)",
    );
  });

  /// 🚨And the harder half of F-9: a call site cannot obey the rule by
  /// having its own slider. Five Material `Slider`s outlived the shared
  /// bar — two in the stage dialog, two in Preferences ▸ Audio, one on
  /// the cut piece — each with a hand-made value Text beside it, each
  /// formatting for itself, and none of them arbitrating a press against
  /// the scroll view they sit in.
  ///
  /// ⛔The list is the point: noticing the next one is not a plan.
  test('no Material Slider is left under lib/src/ui — the app has ONE bar', () {
    final offenders = <String>[];
    final rawSlider = RegExp(r'(?<![A-Za-z_])Slider\s*\(');

    for (final entry
        in Directory('lib/src/ui')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final relative = entry.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/src/ui'));
      final lines = entry.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//') || !rawSlider.hasMatch(line)) {
          continue;
        }
        offenders.add('$key:${i + 1}  ${line.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'use FieldSlider: a Material Slider does not carry its value, and '
          'inside a scrollable it does not claim its own press',
    );
  });
}
