import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/launch_notice.dart';
import 'package:anicel/src/services/persistence/app_language_settings_store.dart';
import 'package:anicel/src/services/persistence/launch_notice_store.dart';
import 'package:anicel/src/ui/dialogs/usage_stats_switch_row.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../helpers/boolean_dot_probe.dart';
import '../helpers/settle_async.dart';

/// A dismissal kept in memory, read by every launch of a test.
class _MemoryStore extends LaunchNoticeStore {
  _MemoryStore() : super(filePath: 'unused');

  String? dismissed;

  @override
  Future<String?> load() async => dismissed;

  @override
  Future<void> save(String dismissedKey) async => dismissed = dismissedKey;
}

/// A saved Korean that comes back only when the test says so.
class _LateKorean extends AppLanguageSettingsStore {
  _LateKorean() : super(filePath: 'unused');

  final gate = Completer<void>();

  @override
  Future<AppLanguageSettings?> load() async {
    await gate.future;
    return const AppLanguageSettings(programLanguage: AppLanguage.ko);
  }

  @override
  Future<void> save(AppLanguageSettings settings) async {}
}

final _content = LaunchNoticeContent(
  (language, section) => '## ${section.name} ${language.name}',
);

final _window = find.byKey(const ValueKey<String>('launch-notice'));

/// 🗣️유저 2026-10-28: 「앱 실행시 앱 설명 넣고싶어」 — the app's first
/// frame opens the notice ([HomePage.launchNotice]), and a test that hands
/// none in sees nothing (`_unlessTesting`).
void main() {
  tearDown(() => AppText.settings.value = const AppLanguageSettings());

  /// A launch of the app on [notice] (and [language]), its first frame and
  /// what the frame after it shows.
  Future<void> launch(
    WidgetTester tester,
    LaunchNotice notice, {
    AppLanguageSettingsStore? language,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(
          key: UniqueKey(),
          launchNotice: notice,
          languageSettingsStore: language,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('🎯the app opens the notice at launch, and not the launch '
      'after it was dismissed', (tester) async {
    final store = _MemoryStore();
    await launch(
      tester,
      LaunchNotice(store: store, content: () async => _content),
    );
    expect(_window, findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('launch-notice-dont-show-again')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_window, findsNothing);
    expect(store.dismissed, _content.key);

    await launch(
      tester,
      LaunchNotice(store: store, content: () async => _content),
    );
    expect(_window, findsNothing);
  });

  testWidgets('🎯its usage statistics switch is the app\'s — off at first, '
      'and what Preferences ▸ System then shows (I-70-Q3)', (tester) async {
    await launch(
      tester,
      LaunchNotice(store: _MemoryStore(), content: () async => _content),
    );
    final inNotice = find.descendant(
      of: _window,
      matching: find.byKey(UsageStatsSwitchRow.tileKey),
    );
    expect(tester.booleanDotIn(inNotice).value, isFalse);
    await tester.pressRingIn(inNotice);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('launch-notice-close')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.byKey(const ValueKey<String>('top-strip-settings-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-edit-preferences')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('preferences-section-system')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .booleanDotIn(
            find.descendant(
              of: find.byKey(const ValueKey<String>('preferences-dialog')),
              matching: find.byKey(UsageStatsSwitchRow.tileKey),
            ),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('a test that hands none in sees no notice', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    // Real time as well as pumped: a notice the app built for itself would
    // read its settings file, and a pumped clock finishes no real read.
    await lendBothClocks(
      tester,
      rounds: 10,
      beat: const Duration(milliseconds: 50),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(_window, findsNothing);
  });

  testWidgets('it waits for the saved language and opens in it', (
    tester,
  ) async {
    final language = _LateKorean();
    await launch(
      tester,
      LaunchNotice(store: _MemoryStore(), content: () async => _content),
      language: language,
    );
    expect(_window, findsNothing);

    language.gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_window, findsOneWidget);
    expect(find.text('안내 · dev'), findsOneWidget);
    expect(find.text('notice ko'), findsOneWidget);
  });
}
