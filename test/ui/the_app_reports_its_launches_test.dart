import 'dart:convert';

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
      'are back, and a return sends the day still owed', (tester) async {
    final posts = <List<Map<String, dynamic>>>[];
    var status = 503;
    final client = AptabaseClient(
      appKey: 'A-EU-1462843916',
      post: (_, _, body) async {
        posts.add((jsonDecode(body) as List).cast<Map<String, dynamic>>());
        return status;
      },
      describe: () => (model: 'x', os: FeedbackOs.windows, osVersion: '11'),
      build: '1081',
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    // The service was down at launch; the app comes back to the front.
    status = 200;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(posts, hasLength(2));
    expect(posts.last.map((event) => event['eventName']), ['day']);
  });

  testWidgets('🎯on and in front, an in_use once an hour — on through '
      'another window\'s focus, none while hidden, and the hour starts again '
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

    await tester.pump(const Duration(minutes: 59));
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

    lifecycle([AppLifecycleState.hidden]);
    await tester.pump(const Duration(hours: 3));
    expect(posts, hasLength(3));

    lifecycle([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await tester.pump(const Duration(minutes: 59));
    expect(posts, hasLength(3), reason: 'the day went at launch');
    await tester.pump(const Duration(minutes: 1));
    expect(posts, hasLength(4));
    expect(posts.last, ['in_use']);
  });
}
