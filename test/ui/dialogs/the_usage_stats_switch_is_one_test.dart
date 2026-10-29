import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/dialogs/preferences_dialog.dart';
import 'package:anicel/src/ui/dialogs/usage_stats_question.dart';
import 'package:anicel/src/ui/dialogs/usage_stats_switch_row.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/editor_app_settings.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

import '../../helpers/boolean_dot_probe.dart';

final _question = find.byKey(usageStatsQuestionKeys.window);
final _preferences = find.byKey(const ValueKey<String>('preferences-dialog'));
final _switch = find.descendant(
  of: _preferences,
  matching: find.byKey(UsageStatsSwitchRow.tileKey),
);

/// 🗣️I-70-Q3 (유저 2026-10-29): on or off any time in 환경설정 — ONE switch,
/// which the question at launch (유저 08:1x, 「따로 묻는 작은 창」) answers
/// and which answers the question in turn.
void main() {
  /// A screen with the app's two ways in: the question as a launch asks it,
  /// and Preferences ▸ System.
  Future<EditorSessionManager> pumpHost(WidgetTester tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => askUsageStatsIfUnanswered(
                    context,
                    session.appSettings.usageStats,
                  ),
                  child: const Text('launch'),
                ),
                TextButton(
                  onPressed: () => showPreferencesDialog(
                    context,
                    session: session,
                    openSessions: [session],
                    initialSection: PreferencesSection.system,
                  ),
                  child: const Text('preferences'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return session;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> closePreferences(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('preferences-close')));
    await tester.pumpAndSettle();
  }

  testWidgets('🎯the question\'s 「보내기」 is the switch Preferences ▸ System '
      'shows — and what it sends is the switch\'s tooltip, no caption', (
    tester,
  ) async {
    final session = await pumpHost(tester);
    final usageStats = session.appSettings.usageStats;

    await tapText(tester, 'launch');
    await tester.tap(find.byKey(usageStatsQuestionKeys.accept));
    await tester.pumpAndSettle();
    expect(usageStats.enabled.value, isTrue);

    await tapText(tester, 'preferences');
    expect(tester.booleanDotIn(_switch).value, isTrue);
    expect(
      find.descendant(
        of: _switch,
        matching: find.text('Send usage statistics'),
      ),
      findsOneWidget,
    );
    expect(find.text(AppText.strings.usageStatsHelp), findsNothing);
    expect(
      find.descendant(
        of: _preferences,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AppTooltip &&
              widget.message == AppText.strings.usageStatsHelp,
        ),
      ),
      findsOneWidget,
    );
    await tester.pressRingIn(_switch);
    await tester.pumpAndSettle();
    expect(usageStats.enabled.value, isFalse);
    await closePreferences(tester);

    // Answered: the next launch's question is not asked.
    await tapText(tester, 'launch');
    expect(_question, findsNothing);
  });

  testWidgets('🎯the switch pressed before the question is asked is an '
      'answer too — the question does not come', (tester) async {
    final session = await pumpHost(tester);
    await tapText(tester, 'preferences');
    expect(tester.booleanDotIn(_switch).value, isFalse);
    await tester.pressRingIn(_switch);
    await tester.pumpAndSettle();
    expect(session.appSettings.usageStats.enabled.value, isTrue);
    await closePreferences(tester);

    await tapText(tester, 'launch');
    expect(_question, findsNothing);
  });

  test('the switch goes with the app\'s settings', () {
    final settings = EditorAppSettings();
    settings.dispose();
    expect(
      () => settings.usageStats.enabled.addListener(() {}),
      throwsFlutterError,
    );
  });
}
