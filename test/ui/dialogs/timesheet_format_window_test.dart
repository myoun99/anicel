import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/dialogs/timesheet_format_window.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

const _bar = ValueKey<String>('timesheet-format-exposure-bar');
const _threshold = ValueKey<String>('timesheet-format-exposure-bar-threshold');
const _seFill = ValueKey<String>('timesheet-format-se-empty-fill');
const _save = ValueKey<String>('timesheet-format-save-button');

Future<void> _openWindow(
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
                  builder: (_) => TimesheetFormatWindow(initialInfo: initial),
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

Future<void> _press(WidgetTester tester, ValueKey<String> key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

ExportPill _pill(WidgetTester tester, ValueKey<String> key) =>
    tester.widget<ExportPill>(find.byKey(key));

ValueKey<String> _box(TimesheetHeaderField field) =>
    ValueKey<String>('timesheet-format-visible-${field.name}');

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
    await _openWindow(tester, before, (r) => after = r);

    await _press(tester, _save);

    expect(after, before);
  });

  testWidgets('the header boxes are ONE strip of the export window\'s pills, '
      'several on at once: a pill reads its box, a press flips only that '
      'box, and the save carries them', (tester) async {
    // 유저 09-25: 「화수나 신 컷 이런건 여러개 동시적용가능한것들이니까」.
    TimesheetInfo? result;
    await _openWindow(
      tester,
      const TimesheetInfo(hiddenFields: {TimesheetHeaderField.cut}),
      (r) => result = r,
    );
    for (final field in TimesheetHeaderField.values) {
      expect(
        _pill(tester, _box(field)).selected,
        field != TimesheetHeaderField.cut,
        reason: '${field.name} is lit exactly while it is shown',
      );
    }

    await _press(tester, _box(TimesheetHeaderField.scene));
    await _press(tester, _box(TimesheetHeaderField.cut));
    expect(_pill(tester, _box(TimesheetHeaderField.scene)).selected, isFalse);
    expect(_pill(tester, _box(TimesheetHeaderField.cut)).selected, isTrue);
    expect(
      _pill(tester, _box(TimesheetHeaderField.episode)).selected,
      isTrue,
      reason: 'a press flips its own box and leaves the others lit',
    );

    await _press(tester, _save);
    expect(result!.hiddenFields, {TimesheetHeaderField.scene});
  });

  testWidgets('each yes/no is one pill that says its state: the hold bar '
      'and the SE wash flip, and the save carries N and the wash', (
    tester,
  ) async {
    final strings = AppText.strings;
    TimesheetInfo? result;
    await _openWindow(tester, TimesheetInfo.empty, (r) => result = r);

    // Defaults: bar off, SE wash on.
    expect(_pill(tester, _bar).selected, isFalse);
    expect(_pill(tester, _bar).label, strings.sheetBarNotDrawn);
    expect(_pill(tester, _seFill).selected, isTrue);
    expect(_pill(tester, _seFill).label, strings.sheetFillOn);

    await _press(tester, _bar);
    expect(_pill(tester, _bar).selected, isTrue);
    expect(_pill(tester, _bar).label, strings.sheetBarDrawn);
    await tester.enterText(find.byKey(_threshold), '4');
    await _press(tester, _seFill);
    expect(_pill(tester, _seFill).selected, isFalse);
    expect(_pill(tester, _seFill).label, strings.sheetFillOff);

    await _press(tester, _save);
    expect(result!.exposureBarThreshold, 4);
    expect(result!.seEmptyFill, isFalse);
  });

  testWidgets('N keeps its place while the bar is off — it refuses typing '
      'instead of leaving, and takes it again once the bar is on', (
    tester,
  ) async {
    // 「없다가 생기는 UI 금지」: the field used to appear only with the bar.
    await _openWindow(tester, TimesheetInfo.empty, (_) {});
    final spot = tester.getRect(find.byKey(_threshold));
    expect(tester.widget<TextField>(find.byKey(_threshold)).enabled, isFalse);

    await _press(tester, _bar);
    expect(tester.widget<TextField>(find.byKey(_threshold)).enabled, isTrue);
    expect(
      tester.getRect(find.byKey(_threshold)),
      spot,
      reason: 'the bar\'s pill changed its word without moving N',
    );
  });

  testWidgets('switching the bar off clears the threshold; garbage N falls '
      'back to the industry default', (tester) async {
    TimesheetInfo? result;
    await _openWindow(
      tester,
      const TimesheetInfo(exposureBarThreshold: 4, seEmptyFill: false),
      (r) => result = r,
    );

    // Pre-filled from the initial info.
    expect(_pill(tester, _bar).selected, isTrue);
    expect(
      tester.widget<TextField>(find.byKey(_threshold)).controller!.text,
      '4',
    );
    await _press(tester, _bar);
    await _press(tester, _save);
    expect(result!.exposureBarThreshold, isNull);
    expect(result!.seEmptyFill, isFalse);

    // Garbage N → default 3.
    TimesheetInfo? second;
    await _openWindow(tester, TimesheetInfo.empty, (r) => second = r);
    await _press(tester, _bar);
    await tester.enterText(find.byKey(_threshold), 'abc');
    await _press(tester, _save);
    expect(
      second!.exposureBarThreshold,
      TimesheetInfo.defaultExposureBarThreshold,
    );
  });
}
