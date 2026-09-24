import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    const before = TimesheetInfo(
      title: 'T',
      staff: {'key': ProductionStaff(name: '원화 담당')},
      logoAssetPath: 'logo.png',
    );
    TimesheetInfo? after;
    await _openDialog(tester, before, (r) => after = r);

    final save = find.byKey(
      const ValueKey<String>('timesheet-info-save-button'),
    );
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(
      after!.logoAssetPath,
      'logo.png',
      reason: 'the logo is not this window\'s to delete',
    );
    expect(
      after!.staffFor('key').name,
      '원화 담당',
      reason: 'nor the staff — the window never showed this role at all',
    );
  });

  testWidgets('every 공정 has a name row, and typing one keeps it', (
    tester,
  ) async {
    TimesheetInfo? saved;
    await _openDialog(tester, TimesheetInfo.empty, (r) => saved = r);

    // ⛔EVERY process, including 用紙. Leaving one out would be a rule
    // nobody asked for, and the cut envelope binds `{staff.<role>.name}`
    // by this same key — so what the form can fill and what a form can
    // print have to be one list.
    for (final process in LayerProcess.values) {
      expect(
        find.byKey(
          ValueKey<String>('timesheet-info-staff-${process.jsonValue}'),
        ),
        findsOneWidget,
        reason: '${process.jsonValue} has no row',
      );
    }

    final keyRow = find.byKey(
      ValueKey<String>('timesheet-info-staff-${LayerProcess.key.jsonValue}'),
    );
    await tester.ensureVisible(keyRow);
    await tester.pumpAndSettle();
    await tester.enterText(keyRow, '김원화');

    final save = find.byKey(
      const ValueKey<String>('timesheet-info-save-button'),
    );
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved!.staffFor(LayerProcess.key.jsonValue).name, '김원화');
    expect(
      saved!.staff.containsKey(LayerProcess.paper.jsonValue),
      isFalse,
      reason:
          'a row left blank writes nothing — the map holds the roles that '
          'were filled, not one entry per row',
    );
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

  testWidgets('🚨every process row reserves a STAMP slot, set or not', (
    tester,
  ) async {
    // 「담당자 = 이름 + 도장 이미지 한 세트」 (cut-envelope 정본 §7). The
    // model and the envelope binding were both already there; the app had
    // nowhere to CHOOSE one.
    //
    // ⛔The slot is reserved on every row, including the empty ones — a cell
    // that appeared only once a file was chosen would be UI popping into
    // existence and the row would jump the first time anyone used it.
    await _openDialog(tester, TimesheetInfo.empty, (_) {});
    for (final process in LayerProcess.values) {
      final cell = find.byKey(
        ValueKey<String>('timesheet-stamp-${process.jsonValue}'),
      );
      await tester.ensureVisible(cell);
      expect(
        cell,
        findsOneWidget,
        reason: '${process.jsonValue} has nowhere to put its stamp',
      );
    }
  });

  testWidgets('the stamp menu can REMOVE one, and the name survives it', (
    tester,
  ) async {
    // Picking opens the OS file picker, which a widget test cannot drive.
    // Removing is the half that is entirely ours, and it is also the half a
    // "cancelled picker clears the stamp" bug would show up in.
    const role = 'key';
    TimesheetInfo? saved;
    await _openDialog(
      tester,
      const TimesheetInfo(
        staff: {
          role: ProductionStaff(name: '아무개', stampAssetPath: 'C:/a/seal.png'),
        },
      ),
      (result) => saved = result,
    );

    await _tapSetting(tester, 'timesheet-stamp-$role');
    await _tapSetting(tester, 'timesheet-stamp-clear-$role');
    await _tapSetting(tester, 'timesheet-info-save-button');

    expect(saved, isNotNull, reason: 'the window has to have saved');
    expect(
      saved!.staffFor(role).stampAssetPath,
      isNull,
      reason: 'Remove has to actually remove it',
    );
    expect(
      saved!.staffFor(role).name,
      '아무개',
      reason:
          'and take only the stamp with it — the two halves of a staff row '
          'are edited independently',
    );
  });

  testWidgets('⛔a role with ONLY a stamp is still a role', (tester) async {
    // The submit used to keep a role when its NAME was non-empty, with the
    // stamp riding along from the old value. Once the stamp is editable
    // here, a stamp with no name is an answer the user typed and dropping
    // it would lose it silently.
    const role = 'inbetween';
    TimesheetInfo? saved;
    await _openDialog(
      tester,
      const TimesheetInfo(
        staff: {role: ProductionStaff(stampAssetPath: 'C:/a/seal.png')},
      ),
      (result) => saved = result,
    );
    await _tapSetting(tester, 'timesheet-info-save-button');

    expect(
      saved!.staffFor(role).stampAssetPath,
      'C:/a/seal.png',
      reason: 'a nameless stamp is not an empty row',
    );
  });
}
