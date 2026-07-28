import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/dialogs/timesheet_info_dialog.dart';

Future<void> _openDialog(
  WidgetTester tester,
  TimesheetInfo initial,
  void Function(TimesheetInfo? result) onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              onResult(
                await showDialog<TimesheetInfo>(
                  context: context,
                  builder: (_) => TimesheetInfoDialog(initialInfo: initial),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The notation switches sit low in the scrolling dialog body — scroll
/// them into view before tapping.
Future<void> _tapSetting(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the notation settings commit through the dialog: exposure '
      'bar on with N, SE empty fill off', (tester) async {
    TimesheetInfo? result;
    await _openDialog(tester, TimesheetInfo.empty, (r) => result = r);

    // Defaults: bar off (no N field yet), SE fill on.
    expect(
      find.byKey(
        const ValueKey<String>('timesheet-info-exposure-bar-threshold'),
      ),
      findsNothing,
    );

    await _tapSetting(tester, 'timesheet-info-exposure-bar');
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('timesheet-info-exposure-bar-threshold'),
      ),
      '4',
    );
    await _tapSetting(tester, 'timesheet-info-se-empty-fill');
    await tester.tap(
      find.byKey(const ValueKey<String>('timesheet-info-save-button')),
    );
    await tester.pumpAndSettle();

    expect(result!.exposureBarThreshold, 4);
    expect(result!.seEmptyFill, isFalse);
  });

  testWidgets('toggling the bar off clears the threshold; garbage N falls '
      'back to the industry default', (tester) async {
    TimesheetInfo? result;
    await _openDialog(
      tester,
      const TimesheetInfo(exposureBarThreshold: 4, seEmptyFill: false),
      (r) => result = r,
    );

    // Pre-filled from the initial info.
    expect(
      find.byKey(
        const ValueKey<String>('timesheet-info-exposure-bar-threshold'),
      ),
      findsOneWidget,
    );
    await _tapSetting(tester, 'timesheet-info-exposure-bar');
    await tester.tap(
      find.byKey(const ValueKey<String>('timesheet-info-save-button')),
    );
    await tester.pumpAndSettle();
    expect(result!.exposureBarThreshold, isNull);
    expect(result!.seEmptyFill, isFalse);

    // Garbage N → default 3.
    TimesheetInfo? second;
    await _openDialog(tester, TimesheetInfo.empty, (r) => second = r);
    await _tapSetting(tester, 'timesheet-info-exposure-bar');
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('timesheet-info-exposure-bar-threshold'),
      ),
      'abc',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('timesheet-info-save-button')),
    );
    await tester.pumpAndSettle();
    expect(
      second!.exposureBarThreshold,
      TimesheetInfo.defaultExposureBarThreshold,
    );
  });
}
