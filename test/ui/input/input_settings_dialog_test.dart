import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/boolean_dot_probe.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/dialogs/input_settings_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/models/app_input_settings.dart';

/// PEN-2: the Input Settings dialog's tablet-service switch (Windows
/// only — the CSP-style dual backend).
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Future<EditorSessionManager> pumpDialog(WidgetTester tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    // The section itself, as the Preferences dialog mounts it (SAVE-1).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InputSettingsSection(session: session),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('Windows shows the tablet-service pair and Wintab applies', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pumpDialog(tester);

    expect(
      find.byKey(const ValueKey<String>('settings-tablet-standard')),
      findsOneWidget,
    );
    final wintab = find.byKey(const ValueKey<String>('settings-tablet-wintab'));
    expect(wintab, findsOneWidget);

    // The dialog scrolls now (PEN-7a grew it) — bring the row into view.
    await tester.ensureVisible(wintab);
    await tester.pumpAndSettle();
    await tester.tap(wintab);
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.tabletService, TabletService.wintab);

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-tablet-standard')),
    );
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.tabletService, TabletService.standard);

    // A press SELECTS — pressing the one that is on leaves it on: there is
    // always a service, and the radio this pair used to be never let go of
    // one either.
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-tablet-standard')),
    );
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.tabletService, TabletService.standard);
    // 유저 named this pair as the pick-one group (guide-sym ⑥⑧), so the
    // idle one steps back.
    expect(tester.booleanDotIn(wintab).inPickOneGroup, isTrue);

    // Foundation debug vars must be back BEFORE the binding's invariant
    // check (which runs ahead of tearDown).
    debugDefaultTargetPlatformOverride = null;
  });

  // 🗣️I-27 (유저 2026-09-13): 「설정 줌 스냅 근처에 최대 줌 제한기능」;
  // I-27-Q1: one line under the zoom snaps — a switch and a number, and
  // 「끄면 칸은 회색으로 자리만」.
  group('the lock on zooming in', () {
    final lockSwitch = find.byKey(
      const ValueKey<String>('settings-zoom-ceiling'),
    );
    final lockNumber = find.byKey(
      const ValueKey<String>('settings-zoom-ceiling-percent'),
    );

    Future<void> type(WidgetTester tester, String text) async {
      await tester.ensureVisible(lockNumber);
      await tester.pumpAndSettle();
      await tester.enterText(lockNumber, text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    testWidgets('stands right under the zoom snaps', (tester) async {
      await pumpDialog(tester);
      final snaps = tester.getRect(
        find.byKey(const ValueKey<String>('settings-snap-zoom')),
      );
      final brushSizes = tester.getRect(
        find.byKey(const ValueKey<String>('settings-snap-size')),
      );
      final number = tester.getRect(lockNumber);
      expect(number.top, greaterThan(snaps.bottom - 1));
      expect(number.bottom, lessThan(brushSizes.top + 1));
      expect(number.left, snaps.left, reason: 'in the column of the fields');
    });

    testWidgets('⛔its number does not come and go with the switch: off, the '
        'field is there, dimmed, holding its value', (tester) async {
      await pumpDialog(tester);

      expect(tester.booleanDotIn(lockSwitch).value, isFalse);
      expect(lockNumber, findsOneWidget);
      expect(tester.widget<TextField>(lockNumber).enabled, isFalse);
      expect(tester.widget<TextField>(lockNumber).controller!.text, '100');
    });

    testWidgets('🚨the switch locks at the number the row holds, and a typed '
        'number is the lock', (tester) async {
      await pumpDialog(tester);
      await tester.ensureVisible(lockSwitch);
      await tester.pumpAndSettle();

      await tester.tap(lockSwitch);
      await tester.pumpAndSettle();
      expect(AppInput.settings.value.zoomCeiling, 100);
      expect(tester.widget<TextField>(lockNumber).enabled, isTrue);

      await type(tester, '250');
      expect(AppInput.settings.value.zoomCeiling, 250);

      await tester.tap(lockSwitch);
      await tester.pumpAndSettle();
      expect(AppInput.settings.value.zoomCeiling, isNull);
      expect(tester.widget<TextField>(lockNumber).controller!.text, '250');
    });

    testWidgets('a number a view cannot stand on becomes the nearest it '
        'can, and words are not a number', (tester) async {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        zoomCeilingOn: true,
      );
      await pumpDialog(tester);

      await type(tester, '5');
      expect(AppInput.settings.value.zoomCeilingPercent, 10);
      await type(tester, '9000');
      expect(AppInput.settings.value.zoomCeilingPercent, 1600);
      await type(tester, 'a lot');
      expect(AppInput.settings.value.zoomCeilingPercent, 1600);
      await type(tester, '33.3');
      expect(AppInput.settings.value.zoomCeilingPercent, 33.3);
      expect(
        tester.widget<TextField>(lockNumber).controller!.text,
        '33.3',
        reason: 'the field shows every digit it holds',
      );
    });
  });

  testWidgets('non-Windows hides the tablet-service section', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpDialog(tester);

    expect(
      find.byKey(const ValueKey<String>('settings-tablet-wintab')),
      findsNothing,
    );
    // A row that is NOT platform-conditional stays, or this case would
    // also pass on a dialog that rendered nothing at all.
    expect(
      find.byKey(const ValueKey<String>('settings-extra-finger')),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
  });
}
