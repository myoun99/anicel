import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

/// A picker ROW in this app is one law spelled once per value: a chip
/// keyed `<row>-<value>`, labelled from a per-value table, shown selected
/// by comparing it with the current value, and selecting it on tap. A
/// value the row refuses gets no tap at all.
///
/// This pins that law where it is USED — the key strings a hand and a test
/// reach for, the selected chip, and the refused one — so the rows can be
/// written once without any of them changing what the window offers.
void main() {
  Pill chipAt(WidgetTester tester, String key) =>
      tester.widget<Pill>(find.byKey(ValueKey<String>(key)));

  /// The chip of [row] that is drawn selected, by its key suffix.
  String selectedIn(WidgetTester tester, String row, List<String> values) {
    final on = [
      for (final value in values)
        if (chipAt(tester, '$row-$value').selected) value,
    ];
    expect(on.length, 1, reason: '$row shows exactly one selection: $on');
    return on.single;
  }

  group('the export format module', () {
    Future<void> pumpChannels(WidgetTester tester, {required bool on}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportFormatModule(
              selection: const ExportFormatSelection(
                kind: ExportMediaKind.still,
                stillFormat: ExportStillFormat.png,
              ),
              capabilities: const ExportFormatCapabilities(
                stills: ExportStillFormat.values,
              ),
              enabled: on,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the channel chips are keyed by value and follow the '
        'selection', (tester) async {
      await pumpChannels(tester, on: true);
      for (final channels in ExportChannels.values) {
        expect(
          find.byKey(
            ValueKey<String>('export-format-channels-${channels.jsonValue}'),
          ),
          findsOneWidget,
        );
      }
      expect(
        selectedIn(tester, 'export-format-channels', [
          for (final channels in ExportChannels.values) channels.jsonValue,
        ]),
        ExportChannels.rgba.jsonValue,
      );
    });

    testWidgets('a disabled module still SHOWS every channel chip; none of '
        'them answers', (tester) async {
      await pumpChannels(tester, on: false);
      for (final channels in ExportChannels.values) {
        final chip = chipAt(
          tester,
          'export-format-channels-${channels.jsonValue}',
        );
        expect(
          chip.onTap,
          isNull,
          reason:
              'a refused value keeps its place and loses its tap '
              '(⛔없다가 생기는 UI 금지)',
        );
      }
      expect(
        selectedIn(tester, 'export-format-channels', [
          for (final channels in ExportChannels.values) channels.jsonValue,
        ]),
        ExportChannels.rgba.jsonValue,
        reason: 'refusing to CHANGE is not refusing to show the answer',
      );
    });
  });
}
