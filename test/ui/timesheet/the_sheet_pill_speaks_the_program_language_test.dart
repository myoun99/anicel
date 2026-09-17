import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

/// 🚨F-124 / F-37 (유저 2026-08-28: 「로컬라이즈 잔여」): the sheet's pill
/// spoke English to everyone. Its three toggles carried six hardcoded
/// tooltips — block/allow ink, notation/data sheet, page/continuous view —
/// while the button right beside them already read the table.
///
/// 🧪**THE TEST DOES NOT NAME THE TRANSLATIONS.** It asks whether the words
/// come from the table at all: the same toggle, in two languages, must say
/// two different things, and neither may be the English that used to be
/// nailed to the widget. Naming them would mean editing this file every time
/// a word is reworded — and the wording is not the contract. `AppStrings`
/// owning the words is.
///
/// ⛔BOTH ARMS OF EVERY TOGGLE. A ternary hides half its strings from any
/// scan and from any test that only looks at the state it happens to mount
/// in; the sheet-ink button's two arms lived one line apart and only one of
/// them is ever on screen.
void main() {
  /// What each toggle says, in [language], with the sheet in the state its
  /// arguments describe.
  Future<Map<String, String>> tooltips(
    WidgetTester tester, {
    required AppLanguage language,
    required bool inkEnabled,
    required bool dataSheet,
    required bool continuous,
  }) async {
    AppText.settings.value = AppLanguageSettings(programLanguage: language);
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    final ink = TimesheetInkController();
    addTearDown(ink.dispose);
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(brushTool.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimesheetTabHost(
            // 🚨A FRESH ELEMENT PER LANGUAGE, and the first run of this file
            // is why. `AppText.settings` is read at BUILD time and nothing
            // listens to it, so pumping the same tree again reuses the
            // element and the pill keeps the words it was built with — the
            // Korean pass came back holding 用紙の手書きを禁止 and the test
            // called it a product bug.
            key: ValueKey<AppLanguage>(language),
            session: session,
            continuous: continuous,
            onContinuousChanged: (_) {},
            viewport: CanvasViewport(),
            onViewportChanged: (_) {},
            inkController: ink,
            brushToolState: brushTool,
            inkEnabled: inkEnabled,
            onInkEnabledChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The key lands on the FACE, which is the box the user presses and the
    // thing that carries the tooltip.
    String of(String keyValue) => tester
        .widget<AppIconButtonFace>(find.byKey(ValueKey<String>(keyValue)))
        .tooltip;

    // The data toggle starts on the notation sheet and is flipped by a tap,
    // so the mode arm is chosen here rather than passed in.
    if (dataSheet) {
      await tester.tap(
        find.byKey(
          const ValueKey<String>('timesheet-data-mode-toggle-button'),
        ),
      );
      await tester.pumpAndSettle();
    }

    return <String, String>{
      'ink': of('timesheet-ink-toggle-button'),
      'mode': of('timesheet-data-mode-toggle-button'),
      'view': of('timesheet-page-mode-toggle-button'),
    };
  }

  /// The words that were nailed to the widget, by the arm they stood on.
  const wasEnglish = <String, List<String>>{
    'ink': ['Block Sheet Ink', 'Allow Sheet Ink'],
    'mode': ['Notation Sheet (repeat/hold words)', 'Data Sheet (as exported)'],
    'view': ['Page View', 'Continuous View'],
  };

  setUp(() {
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
  });

  testWidgets('the sheet pill reads its tooltips from the table — every '
      'toggle, in the arm it shows first', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ja = await tooltips(
      tester,
      language: AppLanguage.ja,
      inkEnabled: true,
      dataSheet: false,
      continuous: false,
    );
    final ko = await tooltips(
      tester,
      language: AppLanguage.ko,
      inkEnabled: true,
      dataSheet: false,
      continuous: false,
    );

    for (final toggle in wasEnglish.keys) {
      expect(
        ja[toggle],
        isNot(ko[toggle]),
        reason: '$toggle says the same thing in Japanese and Korean',
      );
      for (final language in <String, Map<String, String>>{
        'ja': ja,
        'ko': ko,
      }.entries) {
        expect(
          wasEnglish[toggle],
          isNot(contains(language.value[toggle])),
          reason:
              '$toggle still says its English literal in ${language.key}',
        );
      }
    }
  });

  testWidgets('and in the OTHER arm of every one of them — a ternary hides '
      'half its words', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ja = await tooltips(
      tester,
      language: AppLanguage.ja,
      inkEnabled: false,
      dataSheet: true,
      continuous: true,
    );
    final ko = await tooltips(
      tester,
      language: AppLanguage.ko,
      inkEnabled: false,
      dataSheet: true,
      continuous: true,
    );

    for (final toggle in wasEnglish.keys) {
      expect(
        ja[toggle],
        isNot(ko[toggle]),
        reason: '$toggle says the same thing in Japanese and Korean',
      );
      for (final language in <String, Map<String, String>>{
        'ja': ja,
        'ko': ko,
      }.entries) {
        expect(
          wasEnglish[toggle],
          isNot(contains(language.value[toggle])),
          reason:
              '$toggle still says its English literal in ${language.key}',
        );
      }
    }
  });
}
