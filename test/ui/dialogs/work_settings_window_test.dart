import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/dialogs/work_settings_window.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 작품 설정 (유저 09-25, project-settings-window): the work's title and
/// episode, and its staff by the colour labels — two folds, the staff
/// folded until opened.
void main() {
  Future<void> openWindow(
    WidgetTester tester,
    TimesheetInfo initial,
    void Function(TimesheetInfo? result) onResult,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                onResult(
                  await showDialog<TimesheetInfo>(
                    context: context,
                    builder: (_) => WorkSettingsWindow(
                      initialInfo: initial,
                      projectName: 'Untitled 3',
                    ),
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

  Finder rowOf(LayerMark mark) =>
      find.byKey(ValueKey<String>('work-settings-staff-${mark.keySlug}'));

  /// Taps the header of the fold keyed [key].
  Future<void> toggle(WidgetTester tester, String key) async {
    final header = find
        .descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(InkWell),
        )
        .first;
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.byKey(
      const ValueKey<String>('work-settings-save-button'),
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('it opens on the work, the staff folded — 「기본값은 스태프설정만 '
      '접기」', (tester) async {
    await openWindow(tester, TimesheetInfo.empty, (_) {});

    expect(
      find.byKey(const ValueKey<String>('work-settings-title-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('work-settings-episode-field')),
      findsOneWidget,
    );
    expect(
      rowOf(const LayerMark(process: LayerProcess.key)),
      findsNothing,
      reason: 'the staff is folded until opened',
    );
    expect(
      find.text(AppText.strings.workSettingsStaff),
      findsOneWidget,
      reason: 'a fold holding no names yet says only its name',
    );
  });

  testWidgets('the staff is the colour labels\': every process a fold of its '
      'worker and the corrections it references', (tester) async {
    await openWindow(tester, TimesheetInfo.empty, (_) {});
    await toggle(tester, 'work-settings-staff');

    for (final mark in everyLayerMark()) {
      if (mark.isNone) {
        continue;
      }
      expect(rowOf(mark), findsOneWidget, reason: mark.keySlug);
    }
    expect(
      rowOf(
        const LayerMark(
          process: LayerProcess.paper,
          revise: LayerRevise.direction,
        ),
      ),
      findsNothing,
      reason: '用紙 references no correction (revisesFor)',
    );
  });

  testWidgets('a process folds on its own', (tester) async {
    await openWindow(tester, TimesheetInfo.empty, (_) {});
    await toggle(tester, 'work-settings-staff');

    await toggle(tester, 'work-settings-process-key');

    expect(rowOf(const LayerMark(process: LayerProcess.key)), findsNothing);
    expect(
      rowOf(const LayerMark(process: LayerProcess.inbetween)),
      findsOneWidget,
      reason: 'only the one folded',
    );
  });

  testWidgets('what is typed is saved under the labels, a stage and its '
      'correction apart; a row left blank writes nothing', (tester) async {
    const key = LayerMark(process: LayerProcess.key);
    const keyDirection = LayerMark(
      process: LayerProcess.key,
      revise: LayerRevise.direction,
    );
    TimesheetInfo? saved;
    await openWindow(tester, TimesheetInfo.empty, (r) => saved = r);
    await tester.enterText(
      find.byKey(const ValueKey<String>('work-settings-title-field')),
      'YOASOBI',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('work-settings-episode-field')),
      '#3',
    );
    await toggle(tester, 'work-settings-staff');
    await tester.ensureVisible(rowOf(key));
    await tester.enterText(rowOf(key), '大川');
    await tester.ensureVisible(rowOf(keyDirection));
    await tester.enterText(rowOf(keyDirection), '清');

    await save(tester);

    expect(saved!.title, 'YOASOBI');
    expect(saved!.episode, '#3');
    expect(saved!.staff, {key.keySlug: '大川', keyDirection.keySlug: '清'});
  });

  testWidgets('the empty title shows the project\'s name — what the paper '
      'prints for it', (tester) async {
    await openWindow(tester, TimesheetInfo.empty, (_) {});

    final title = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('work-settings-title-field')),
    );
    expect(title.decoration?.hintText, 'Untitled 3');
  });

  testWidgets('🚨saving does not reset what this window does not show', (
    tester,
  ) async {
    final before = const TimesheetInfo(
      title: 'T',
      hiddenFields: {TimesheetHeaderField.scene},
      exposureBarThreshold: 4,
      seEmptyFill: false,
      logoAssetPath: 'logo.png',
      coverImagePath: 'cover.png',
      envelopeFormId: CutEnvelopePresets.digitalId,
    ).withStaffName(const LayerMark(process: LayerProcess.conte), '콘티');
    TimesheetInfo? after;
    await openWindow(tester, before, (r) => after = r);

    await save(tester);

    expect(after, before);
  });
}
