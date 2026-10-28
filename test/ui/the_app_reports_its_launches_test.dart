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
  Future<List<int>?> load() async => const [];

  @override
  Future<void> save(List<int>? activeDays) async {}
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
}
