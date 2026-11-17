import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/brush/tool_setting_rows.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// 🗣️tool-settings-segments-overlap-at-the-narrowest-Q1 (유저 2026-11-17):
/// the least row ([ToolSettingColumns.rowFor]) is the name column's law
/// read backwards — laid out at it, a row leaves its control column the
/// width asked for, and a pixel less leaves it less. Asked where the name
/// stands at its floor, at its share and at its ceiling.
void main() {
  const control = ValueKey<String>('control');

  Future<double> controlAt(
    WidgetTester tester,
    double width,
    double end,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ToolSettingEnd(
                width: end,
                child: const ToolSettingRow(
                  label: 'Name',
                  child: SizedBox(key: control, height: 10),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byKey(control)).width;
  }

  for (final (asked, end) in [(20.0, 44.0), (150.0, 44.0), (300.0, 66.0)]) {
    testWidgets('a row at its least leaves its control $asked across beside '
        'an end of $end', (tester) async {
      final least = ToolSettingColumns.rowFor(control: asked, end: end);
      expect(await controlAt(tester, least, end), moreOrLessEquals(asked));
      expect(await controlAt(tester, least - 1, end), lessThan(asked));
    });
  }

  test('the three ask the name at its floor, its share and its ceiling', () {
    final names = [
      for (final (asked, end) in [(20.0, 44.0), (150.0, 44.0), (300.0, 66.0)])
        ToolSettingColumns.nameIn(
          ToolSettingColumns.rowFor(control: asked, end: end),
        ),
    ];
    final floor = ToolSettingColumns.nameIn(0);
    final ceiling = ToolSettingColumns.nameIn(double.maxFinite);
    expect(names.first, floor, reason: 'the floor');
    expect(
      names[1],
      allOf(greaterThan(floor), lessThan(ceiling)),
      reason: 'the share',
    );
    expect(names.last, ceiling, reason: 'the ceiling');
  });
}
