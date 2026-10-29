import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/feedback/feedback_forms.dart';
import 'package:anicel/src/services/persistence/usage_stats_store.dart';
import 'package:anicel/src/services/usage_stats/aptabase_client.dart';
import 'package:anicel/src/services/usage_stats/usage_stats.dart';
import 'package:anicel/src/ui/dialogs/usage_stats_question.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// The answer kept in memory, as the settings file keeps it across
/// launches.
class _MemoryStore extends UsageStatsStore {
  _MemoryStore() : super(filePath: 'unused');

  /// What the file holds: null is no file.
  UsageStatsAnswer? answer;

  @override
  Future<UsageStatsAnswer?> load() async => answer;

  @override
  Future<void> save(UsageStatsAnswer answer) async => this.answer = answer;
}

final _window = find.byKey(usageStatsQuestionKeys.window);
final _send = find.byKey(usageStatsQuestionKeys.accept);
final _dontSend = find.byKey(usageStatsQuestionKeys.decline);

/// 🗣️유저 2026-10-29 08:1x: 「따로 묻는 작은 창」 — asked once, 「보내지
/// 않기」 or 「보내기」, the answer remembered on the device; 08:2x: what is
/// sent and what never is, said plainly.
///
/// A LAUNCH is what the app does after its notice: [askUsageStatsIfUnanswered]
/// on a fresh [UsageStats] — the next launch is another on the SAME store.
void main() {
  late List<List<Object?>> posts;

  setUp(() => posts = []);
  tearDown(() => AppText.settings.value = const AppLanguageSettings());

  /// A run of the app on [store]: its usage statistics, restored.
  UsageStats run(_MemoryStore store) {
    final stats = UsageStats(
      store: store,
      client: AptabaseClient(
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
      ),
      locale: () => 'en',
      osLocale: () => 'en-US',
      settings: () => const {},
    );
    addTearDown(stats.dispose);
    unawaited(stats.restore());
    return stats;
  }

  /// One launch of the app on [store], as far as its question.
  Future<UsageStats> launch(WidgetTester tester, _MemoryStore store) async {
    final stats = run(store);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => askUsageStatsIfUnanswered(context, stats),
              child: const Text('launch'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();
    return stats;
  }

  testWidgets('🎯never answered, it asks: the ask, what is sent and what '
      'never is, and where it changes — 「보내지 않기」 and 「보내기」', (
    tester,
  ) async {
    for (final language in [AppLanguage.ko, AppLanguage.en]) {
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
      await launch(tester, _MemoryStore());
      final strings = AppText.strings;
      expect(_window, findsOneWidget, reason: language.name);
      expect(
        find.descendant(
          of: _window,
          matching: find.text(strings.usageStatsTitle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _window,
          matching: find.text(
            '${strings.usageStatsAsk}\n\n${strings.usageStatsHelp}\n\n'
            '${strings.usageStatsChangeLater}',
          ),
        ),
        findsOneWidget,
        reason: language.name,
      );
      expect(
        find.descendant(
          of: _send,
          matching: find.text(strings.usageStatsDoSend),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _dontSend,
          matching: find.text(strings.usageStatsDontSend),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('보내기'), findsNothing, reason: 'English by now');
    expect(posts, isEmpty, reason: 'nothing before 「보내기」');
  });

  testWidgets('in Korean, the words chosen for it: 「사용 통계」, the ask '
      'first and where it changes last, 「보내지 않기」 and 「보내기」', (
    tester,
  ) async {
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ko,
    );
    await launch(tester, _MemoryStore());
    expect(
      find.descendant(of: _window, matching: find.text('사용 통계')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _window,
        matching: find.textContaining(
          RegExp(
            r'^사용 통계를 보내시겠습니까\? 켜 주시면 Anicel 개발에 도움이 '
            r'됩니다\.\n\n[^\n]+\n\n환경설정 ▸ 시스템에서 언제든 바꿀 수 '
            r'있습니다\.$',
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _send, matching: find.text('보내기')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _dontSend, matching: find.text('보내지 않기')),
      findsOneWidget,
    );
  });

  testWidgets('🎯「보내기」 turns it on and sends — and the next launch does not '
      'ask', (tester) async {
    final store = _MemoryStore();
    final stats = await launch(tester, store);
    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(_window, findsNothing);
    expect(stats.enabled.value, isTrue);
    expect(store.answer, isA<UsageStatsOn>());
    expect(posts, [
      ['app_started', 'day'],
    ]);

    final next = await launch(tester, store);
    expect(_window, findsNothing);
    expect(next.enabled.value, isTrue);
  });

  testWidgets('🎯「보내지 않기」 sends nothing — and the next launch does not '
      'ask', (tester) async {
    final store = _MemoryStore();
    final stats = await launch(tester, store);
    await tester.tap(_dontSend);
    await tester.pumpAndSettle();
    expect(_window, findsNothing);
    expect(stats.enabled.value, isFalse);
    expect(store.answer, isA<UsageStatsOff>());

    final next = await launch(tester, store);
    expect(_window, findsNothing);
    expect(next.enabled.value, isFalse);
    expect(posts, isEmpty);
  });

  // 🗣️I-70-Q6 (유저 2026-10-29): 「포커스 없음」 — consent is a press.
  testWidgets('⛔Enter answers nothing — the window opens on neither '
      'button, and only a press of one answers', (tester) async {
    final store = _MemoryStore();
    final stats = await launch(tester, store);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_window, findsOneWidget);
    expect(store.answer, isNull);
    expect(stats.enabled.value, isFalse);
    expect(posts, isEmpty);

    await tester.tap(_dontSend);
    await tester.pumpAndSettle();
    expect(_window, findsNothing);
    expect(store.answer, isA<UsageStatsOff>());
  });

  testWidgets('⛔closed with neither — escape, or a tap beside it — is no '
      'answer: off, nothing sent, and the next launch asks again', (
    tester,
  ) async {
    final store = _MemoryStore();
    final stats = await launch(tester, store);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_window, findsNothing);
    expect(stats.enabled.value, isFalse);
    expect(store.answer, isNull);

    await launch(tester, store);
    expect(_window, findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(_window, findsNothing);
    expect(store.answer, isNull);

    await launch(tester, store);
    expect(_window, findsOneWidget);
    expect(posts, isEmpty);
  });
}
