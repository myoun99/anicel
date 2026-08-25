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
void main() {
  group('the formatter', () {
    test('one decimal, and a whole number stays whole', () {
      expect(sliderValueText(1.2, unit: ' px'), '1.2 px');
      expect(sliderValueText(2, unit: ' px'), '2 px');
      expect(sliderValueText(2.0, unit: ' px'), '2 px');
      expect(sliderValueText(50, unit: '%'), '50%');
    });

    test('it rounds to the tenth rather than truncating', () {
      expect(sliderValueText(1.24), '1.2');
      expect(sliderValueText(1.25), '1.3');
      expect(sliderValueText(1.96), '2');
    });

    test('an integer value renders with no decimal at all — which is why '
        'every caller can use it and none has to decide', () {
      expect(sliderValueText(128), '128');
      expect(sliderValueText(0, unit: ' px'), '0 px');
      expect(sliderValueText(-3, unit: ' px'), '-3 px');
    });
  });

  /// ⚠️The formatter being right proves nothing about the panels: the bug was
  /// that each of them formatted for itself.
  test('no slider rounds its own value text', () {
    final offenders = <String>[];
    // `valueText:` / `valueTextBuilder:` lines that still call `.round()` or
    // interpolate a raw value. Multi-line values are caught by scanning the
    // three lines that follow the field name.
    final rounding = RegExp(r'\.round\(\)|\.toStringAsFixed\(0\)');

    for (final entry in Directory('lib/src/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final relative = entry.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/src/ui'));
      if (key == 'lib/src/ui/widgets/field_slider.dart' ||
          key == 'lib/src/ui/color/color_rgb_panel.dart') {
        // The formatter itself, and the ONE deliberate exception: an RGB
        // channel is a whole number of steps by decision, said so at the
        // slider ("a channel is a whole number of steps, so the bar snaps to
        // them instead of handing 137.4 to a byte").
        continue;
      }
      final lines = entry.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        if (!lines[i].contains('valueText:') &&
            !lines[i].contains('valueTextBuilder:')) {
          continue;
        }
        // The argument's own text: this line from the field name onward,
        // plus continuation lines until the NEXT named argument starts.
        // Without that stop, a neighbouring `onChanged: value.round()` —
        // which is the model's business, not the label's — reads as a hit.
        final buffer = StringBuffer(
          lines[i].substring(lines[i].indexOf('valueText')),
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
      reason: 'use sliderValueText — an integer value renders identically '
          'through it, so there is no reason for a call site to round',
    );
  });
}
