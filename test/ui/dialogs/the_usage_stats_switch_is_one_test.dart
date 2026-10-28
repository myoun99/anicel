import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/launch_notice.dart';
import 'package:anicel/src/services/persistence/launch_notice_store.dart';
import 'package:anicel/src/ui/dialogs/launch_notice_window.dart';
import 'package:anicel/src/ui/dialogs/preferences_dialog.dart';
import 'package:anicel/src/ui/dialogs/usage_stats_switch_row.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

import '../../helpers/boolean_dot_probe.dart';

/// Nothing dismissed, ever: every launch of the test shows the notice.
class _NeverDismissed extends LaunchNoticeStore {
  _NeverDismissed() : super(filePath: 'unused');

  @override
  Future<String?> load() async => null;

  @override
  Future<void> save(String dismissedKey) async {}
}

final _notice = find.byKey(const ValueKey<String>('launch-notice'));
final _preferences = find.byKey(const ValueKey<String>('preferences-dialog'));

Finder _switchIn(Finder window) => find.descendant(
  of: window,
  matching: find.byKey(UsageStatsSwitchRow.tileKey),
);

/// 🗣️I-70-Q3 (유저 2026-10-29): 「안내 창에서 묻고 기본 꺼짐」, and on or off
/// any time in 환경설정 — ONE switch, asked in the one window and kept in
/// the other.
void main() {
  testWidgets('🎯the launch notice asks with the switch Preferences ▸ System '
      'keeps — off until pressed, one value in both', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final usageStats = session.appSettings.usageStats;
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
                  onPressed: () => showLaunchNoticeIfDue(
                    context,
                    LaunchNotice(
                      store: _NeverDismissed(),
                      content: () async => LaunchNoticeContent(
                        (language, section) => '## ${section.name}',
                      ),
                    ),
                    usageStats: usageStats,
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

    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();
    expect(_switchIn(_notice), findsOneWidget);
    expect(tester.booleanDotIn(_switchIn(_notice)).value, isFalse);
    expect(usageStats.enabled.value, isFalse);
    expect(
      find.descendant(of: _notice, matching: find.text('Send usage statistics')),
      findsOneWidget,
    );
    // What it sends is the tooltip — no caption under the control.
    expect(find.text(AppText.strings.usageStatsHelp), findsNothing);
    expect(
      find.descendant(
        of: _notice,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AppTooltip &&
              widget.message == AppText.strings.usageStatsHelp,
        ),
      ),
      findsOneWidget,
    );

    await tester.pressRingIn(_switchIn(_notice));
    await tester.pumpAndSettle();
    expect(usageStats.enabled.value, isTrue);
    expect(tester.booleanDotIn(_switchIn(_notice)).value, isTrue);
    await tester.tap(
      find.byKey(const ValueKey<String>('launch-notice-close')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('preferences'));
    await tester.pumpAndSettle();
    expect(tester.booleanDotIn(_switchIn(_preferences)).value, isTrue);
    await tester.pressRingIn(_switchIn(_preferences));
    await tester.pumpAndSettle();
    expect(usageStats.enabled.value, isFalse);
    await tester.tap(find.byKey(const ValueKey<String>('preferences-close')));
    await tester.pumpAndSettle();

    // And the next launch's notice asks again from what Preferences left.
    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();
    expect(tester.booleanDotIn(_switchIn(_notice)).value, isFalse);
  });
}
