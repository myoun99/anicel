import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/dialogs/timesheet_info_dialog.dart';
import '../../helpers/boolean_dot_probe.dart';

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
  testWidgets('🚨saving does not WIPE what this window does not edit', (
    tester,
  ) async {
    // The submit built a fresh `TimesheetInfo` from the fields on screen,
    // so every field the window does not show — `staff`, `logoAssetPath` —
    // came back at its default. Opening this window and pressing save
    // deleted the production staff and the logo, and nothing said so.
    // The work's own words live in the work's settings since 09-25, which
    // leaves this window even more to not show.
    final before = const TimesheetInfo(
      title: 'T',
      episode: 'E',
      logoAssetPath: 'logo.png',
    ).withStaffName(const LayerMark(process: LayerProcess.key), '원화');
    TimesheetInfo? after;
    await _openDialog(tester, before, (r) => after = r);

    final save = find.byKey(
      const ValueKey<String>('timesheet-info-save-button'),
    );
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(after, before);
  });

  testWidgets('a header box is a boolean ROW: it reads the box, a press '
      'flips it, and the save carries it', (tester) async {
    // The boxes were FilterChips until the app's one boolean replaced them
    // (guide-sym ⑥⑧: 「진짜 불리언값 모든곳에 적용」) — and no test pressed a
    // single one.
    TimesheetInfo? result;
    await _openDialog(
      tester,
      const TimesheetInfo(hiddenFields: {TimesheetHeaderField.cut}),
      (r) => result = r,
    );
    final scene = find.byKey(
      const ValueKey<String>('timesheet-info-visible-scene'),
    );
    final cut = find.byKey(
      const ValueKey<String>('timesheet-info-visible-cut'),
    );
    await tester.ensureVisible(scene);
    await tester.pumpAndSettle();
    expect(tester.booleanDotIn(scene).value, isTrue, reason: 'shown');
    expect(tester.booleanDotIn(cut).value, isFalse, reason: 'hidden');

    await _tapSetting(tester, 'timesheet-info-visible-scene');
    await _tapSetting(tester, 'timesheet-info-visible-cut');
    expect(tester.booleanDotIn(scene).value, isFalse);
    expect(tester.booleanDotIn(cut).value, isTrue);

    await _tapSetting(tester, 'timesheet-info-save-button');
    expect(result!.hiddenFields, {TimesheetHeaderField.scene});
  });

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
