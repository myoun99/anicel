import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/launch_notice.dart';
import 'package:anicel/src/services/persistence/app_language_settings_store.dart';
import 'package:anicel/src/services/persistence/launch_notice_store.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

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

  testWidgets('a test that hands none in sees no notice — and reads no '
      'settings file for one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pump();
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
    expect(find.text('안내'), findsOneWidget);
    expect(find.text('notice ko'), findsOneWidget);
  });
}
