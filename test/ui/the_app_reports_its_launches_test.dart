import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/feedback/feedback_forms.dart';
import 'package:anicel/src/services/persistence/app_language_settings_store.dart';
import 'package:anicel/src/services/persistence/usage_stats_store.dart';
import 'package:anicel/src/services/usage_stats/aptabase_client.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// Turned on, with nothing sent yet.
class _OnStore extends UsageStatsStore {
  _OnStore() : super(filePath: 'unused');

  @override
  Future<UsageStatsAnswer?> load() async => const UsageStatsOn([]);

  @override
  Future<void> save(UsageStatsAnswer answer) async {}
}

/// A saved Korean, back a moment after the usage statistics' answer.
class _Korean extends AppLanguageSettingsStore {
  _Korean() : super(filePath: 'unused');

  @override
  Future<AppLanguageSettings?> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return const AppLanguageSettings(programLanguage: AppLanguage.ko);
  }

  @override
  Future<void> save(AppLanguageSettings settings) async {}
}

/// 🗣️I-70 (유저 2026-10-29): `app_started` every launch, `day` once a UTC
/// day — reported by the app itself, at launch and on each return to it.
void main() {
  tearDown(() => AppText.settings.value = const AppLanguageSettings());

  testWidgets('🎯a launch reports itself once the answer and the language '
      'are back, and a return sends what the launch could not', (
    tester,
  ) async {
    final posts = <List<Map<String, dynamic>>>[];
    var status = 503;
    final client = AptabaseClient(
      appKey: 'A-EU-1462843916',
      post: (_, _, body) async {
        posts.add((jsonDecode(body) as List).cast<Map<String, dynamic>>());
        return status;
      },
      prepare: () {},
      describe: () => (model: 'x', os: FeedbackOs.windows, osVersion: '11'),
      build: '1081',
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.localeTestValue = const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hans',
      countryCode: 'CN',
    );
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(
          languageSettingsStore: _Korean(),
          usageStatsStore: _OnStore(),
          usageStatsClient: client,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(posts, hasLength(1));
    expect(posts.single.map((event) => event['eventName']), [
      'app_started',
      'day',
    ]);
    expect(
      (posts.single.first['systemProps'] as Map<String, dynamic>)['locale'],
      'ko',
    );
    // The device's own language on the day, as the platform names it.
    expect(
      (posts.single.last['props'] as Map<String, dynamic>)['osLocale'],
      'zh-Hans-CN',
    );

    // The service was down at launch; the app comes back to the front, and
    // what waited on the device goes — the same events, as they were.
    status = 200;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(posts, hasLength(2));
    expect(posts.last, posts.first);
  });

  testWidgets('🎯on and in front, an in_use as each 55 minutes run out — on '
      'through another window\'s focus, none while hidden, and armed again '
      'when the app is back', (tester) async {
    final posts = <List<Object?>>[];
    final client = AptabaseClient(
      appKey: 'A-EU-1462843916',
      post: (_, _, body) async {
        posts.add([
          for (final event in jsonDecode(body) as List)
            (event as Map<String, dynamic>)['eventName'],
        ]);
        return 200;
      },
      prepare: () {},
      describe: () => (model: 'x', os: FeedbackOs.windows, osVersion: '11'),
      build: '1081',
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(usageStatsStore: _OnStore(), usageStatsClient: client),
      ),
    );
    await tester.pump();
    expect(posts, [
      ['app_started', 'day'],
    ]);

    await tester.pump(const Duration(minutes: 54));
    expect(posts, hasLength(1));
    await tester.pump(const Duration(minutes: 1));
    expect(posts, hasLength(2));
    expect(posts.last, ['in_use']);

    void lifecycle(List<AppLifecycleState> states) {
      for (final state in states) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    lifecycle([AppLifecycleState.inactive]);
    await tester.pump(const Duration(hours: 1));
    expect(posts, hasLength(3));
    expect(posts.last, ['in_use']);

    // Hidden: its app_away (I-70-Q11), and no in_use.
    lifecycle([AppLifecycleState.hidden]);
    await tester.pump(const Duration(hours: 3));
    expect(posts, hasLength(4));
    expect(posts.last, ['app_away']);

    lifecycle([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await tester.pump(const Duration(minutes: 54));
    expect(posts, hasLength(4), reason: 'the day went at launch');
    await tester.pump(const Duration(minutes: 1));
    expect(posts, hasLength(5));
    expect(posts.last, ['in_use']);

    // Paused — a phone's app behind another — and detached, the way the
    // framework allows them: each only after the one before, and the three
    // one going away.
    lifecycle([
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    await tester.pump(const Duration(hours: 3));
    lifecycle([AppLifecycleState.detached]);
    await tester.pump(const Duration(hours: 3));
    expect(posts, hasLength(6));
    expect(posts.last, ['app_away']);
    lifecycle([AppLifecycleState.resumed]);
    await tester.pump(const Duration(hours: 1));
    expect(posts, hasLength(7));
    expect(posts.last, ['in_use']);
  });

  testWidgets('🎯a window that closes writes its app_away down before it goes '
      '— the next launch sends it (유저 2026-10-29, I-70-Q11: 「닫을때도 '
      '보내게」)', (tester) async {
    final store = _KeptStore();
    final client = AptabaseClient(
      appKey: 'A-EU-1462843916',
      post: (_, _, _) async => 503,
      prepare: () {},
      describe: () => (model: 'x', os: FeedbackOs.windows, osVersion: '11'),
      build: '1081',
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(usageStatsStore: store, usageStatsClient: client),
      ),
    );
    await tester.pump();
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(
      [for (final event in store.queue) event['eventName']],
      ['app_started', 'day', 'app_away'],
    );
  });
}

/// Turned on, with what it was last given kept.
class _KeptStore extends UsageStatsStore {
  _KeptStore() : super(filePath: 'unused');

  UsageStatsAnswer answer = const UsageStatsOn([]);

  List<Map<String, Object?>> get queue => switch (answer) {
    UsageStatsOn(:final queue) => queue,
    UsageStatsOff() => const [],
  };

  @override
  Future<UsageStatsAnswer?> load() async => answer;

  @override
  Future<void> save(UsageStatsAnswer answer) async => this.answer = answer;
}
