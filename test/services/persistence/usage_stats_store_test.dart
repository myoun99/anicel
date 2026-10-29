import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/persistence/usage_stats_store.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️I-70-Q3 (유저 2026-10-29): 「기본 꺼짐」 — and the record of days lives
/// on the device only while the switch is on. 🗣️08:1x: asked ONCE, so the
/// file tells a person never asked from one who said no.
void main() {
  late Directory directory;
  late UsageStatsStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('usage_stats_store');
    store = UsageStatsStore(filePath: '${directory.path}/usage_stats.json');
  });

  tearDown(() => deleteTempQuietly(directory));

  Map<String, dynamic> file() =>
      jsonDecode(File(store.filePath).readAsStringSync())
          as Map<String, dynamic>;

  List<int>? daysOf(UsageStatsAnswer? answer) => switch (answer) {
    UsageStatsOn(:final activeDays) => activeDays,
    _ => null,
  };

  test('🎯no file is NO ANSWER yet — not an error, and not a no', () async {
    expect(await store.load(), isNull);
  });

  test('on, with its days and the events still to send, is what the next '
      'launch reads', () async {
    const waiting = <Map<String, Object?>>[
      {
        'timestamp': '2026-10-29T06:20:00.000Z',
        'sessionId': '176171880012345678',
        'eventName': 'day',
        'systemProps': {'locale': 'ko', 'isDebug': false},
        'props': {'days': '1-2', 'osLocale': 'ko-KR'},
      },
    ];
    await store.save(const UsageStatsOn([20754, 20755], waiting));
    expect(file(), {
      'version': 1,
      'enabled': true,
      'activeDays': [20754, 20755],
      'queue': waiting,
    });
    final next = await UsageStatsStore(filePath: store.filePath).load();
    expect(next, isA<UsageStatsOn>());
    expect(daysOf(next), [20754, 20755]);
    expect((next! as UsageStatsOn).queue, waiting);

    await store.save(const UsageStatsOn([]));
    expect(daysOf(await store.load()), isEmpty);
    expect((await store.load() as UsageStatsOn?)?.queue, isEmpty);
  });

  test('🎯on keeps the session and when it began, for the next run to go on '
      'in (유저 2026-10-29, I-70-Q10 · Q13) — and a file with none, or one it '
      'cannot read, has none to go on in', () async {
    final startedAt = DateTime.utc(2026, 10, 29, 11, 50);
    await store.save(
      UsageStatsOn(const [20755], const [], (
        id: '176171880012345678',
        startedAt: startedAt,
      )),
    );
    expect(file()['session'], {
      'id': '176171880012345678',
      'startedAt': '2026-10-29T11:50:00.000Z',
    });
    final kept = ((await store.load())! as UsageStatsOn).session;
    expect(kept, (id: '176171880012345678', startedAt: startedAt));

    await store.save(const UsageStatsOn([20755]));
    expect(file().containsKey('session'), isFalse);
    expect(((await store.load())! as UsageStatsOn).session, isNull);

    await File(store.filePath).writeAsString(
      jsonEncode({
        'version': 1,
        'enabled': true,
        'activeDays': [20755],
        'queue': <Object>[],
        'session': {'id': '1', 'startedAt': 'yesterday'},
      }),
    );
    final unread = await store.load();
    expect(unread, isA<UsageStatsOn>(), reason: 'the answer stays a yes');
    expect((unread! as UsageStatsOn).session, isNull);
  });

  test('🎯off is an answer: written with no days, and read as a no', () async {
    await store.save(const UsageStatsOn([20755]));
    await store.save(const UsageStatsOff());
    expect(file(), {'version': 1, 'enabled': false});
    expect(await store.load(), isA<UsageStatsOff>());
  });

  test('⛔a file that says off brings back no record and nothing to send, '
      'whatever it holds', () async {
    await File(store.filePath).writeAsString(
      jsonEncode({
        'version': 1,
        'enabled': false,
        'activeDays': [20755],
        'queue': [
          {'eventName': 'day'},
        ],
      }),
    );
    expect(await store.load(), isA<UsageStatsOff>());
  });

  test('a file it cannot read holds no answer — the question is asked '
      'again', () async {
    for (final text in [
      '{not json',
      jsonEncode({'version': 1, 'activeDays': [20755], 'queue': []}),
      jsonEncode({
        'version': 1,
        'enabled': 'yes',
        'activeDays': [],
        'queue': [],
      }),
      jsonEncode({
        'version': 1,
        'enabled': true,
        'activeDays': ['a'],
        'queue': [],
      }),
      jsonEncode({'version': 1, 'enabled': true, 'queue': []}),
      jsonEncode({'version': 1, 'enabled': true, 'activeDays': []}),
      jsonEncode({
        'version': 1,
        'enabled': true,
        'activeDays': [],
        'queue': ['day'],
      }),
      jsonEncode({
        'version': UsageStatsStore.version + 1,
        'enabled': true,
        'activeDays': [20755],
        'queue': [],
      }),
    ]) {
      await File(store.filePath).writeAsString(text);
      expect(await store.load(), isNull, reason: text);
    }
  });
}
