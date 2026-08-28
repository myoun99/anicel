import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// 🚨★★★AN OPACITY BAR IS WHOLE PER CENT (F-34).
///
/// 유저 2026-08-29: 「슬라이더에서 데이터적으로 소수점이 필요없는것들 정수화.
/// **레이어나 브러시 불투명도가 소수점? 자연수가 아닐 이유가 없다고생각.
/// 조절시 자연수이도록.** 물론 변형툴의 확대율같은 예외는 있음」.
///
/// ⛔ROUNDING THE LABEL IS NOT THE SAME THING, and that is what the app had.
/// `sliderValueText` rounded to one decimal for display, so a bar reading
/// `50%` could be holding 0.4963 — and whatever read that number next (a
/// composite, an export, the file) got 0.4963.
void main() {
  Future<List<double>> dragAcross(WidgetTester tester, Widget bar) async {
    final seen = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 200, child: bar)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(FieldSlider));
    final gesture = await tester.startGesture(box.centerLeft);
    // Deliberately awkward offsets — a drag that landed on round numbers by
    // luck would prove nothing.
    for (final dx in [37.3, 61.7, 113.9, 178.1]) {
      await gesture.moveTo(Offset(box.left + dx, box.center.dy));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    return seen;
  }

  testWidgets('every value a drag emits is a whole per cent', (tester) async {
    final seen = <double>[];
    await dragAcross(
      tester,
      FieldSlider.opacity(value: 0.5, valueText: '50%', onChanged: seen.add),
    );
    expect(seen, isNotEmpty, reason: 'the drag has to move the bar at all');
    for (final value in seen) {
      final percent = value * 100;
      expect(
        percent,
        closeTo(percent.roundToDouble(), 1e-9),
        reason:
            '$value is $percent% — a drag must not leave a fraction of a '
            'per cent behind for the composite to read',
      );
    }
  });

  testWidgets('and it still reaches both ends', (tester) async {
    // ⛔THE CONTROL. Snapping that clamped the range — or divisions that
    // quietly moved the endpoints — would pass the test above while making
    // the bar unable to say "off" or "full".
    final seen = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: FieldSlider.opacity(
                value: 0.5,
                valueText: '50%',
                onChanged: seen.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(FieldSlider));
    await tester.tapAt(box.centerLeft + const Offset(0.5, 0));
    await tester.pump();
    await tester.tapAt(box.centerRight - const Offset(0.5, 0));
    await tester.pump();
    expect(seen.first, 0.0, reason: 'the left end is 「off」');
    expect(seen.last, 1.0, reason: 'the right end is 「full」');
  });

  test('no opacity bar re-types the range — the constructor owns it', () {
    // 🚨THE SIX. Every one of them typed `min: 0, max: 1` with the same
    // `value * 100` builder, and every one of them had forgotten the
    // divisions. Six places to remember is why none did.
    //
    // ⛔SCANNED rather than counted: a seventh bar added tomorrow is the
    // case this exists for, and it will not be in any list a test wrote
    // down today.
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final path = file.path.replaceAll(r'\', '/');
      final relative = path.substring(path.indexOf('lib/'));
      if (relative.endsWith('widgets/field_slider.dart')) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!RegExp(r'(^|[^A-Za-z_])FieldSlider\(').hasMatch(lines[i])) {
          continue;
        }
        final window = lines
            .sublist(i, (i + 14).clamp(0, lines.length))
            .join(' ');
        // An opacity bar is recognisable by what it does with the number:
        // a 0..1 model value shown as a percentage.
        if (RegExp(r'min:\s*0\b').hasMatch(window) &&
            RegExp(r'max:\s*1\b').hasMatch(window) &&
            window.contains("unit: '%'")) {
          offenders.add('$relative:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'use FieldSlider.opacity — it fixes the range, the per-cent '
          'format and the whole-number stepping in one place',
    );
  });
}
