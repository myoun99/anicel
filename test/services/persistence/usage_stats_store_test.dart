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

  test('on, with its days, is what the next launch reads', () async {
    await store.save(const UsageStatsOn([20754, 20755]));
    expect(file(), {
      'version': 1,
      'enabled': true,
      'activeDays': [20754, 20755],
    });
    final next = await UsageStatsStore(filePath: store.filePath).load();
    expect(next, isA<UsageStatsOn>());
    expect(daysOf(next), [20754, 20755]);

    await store.save(const UsageStatsOn([]));
    expect(daysOf(await store.load()), isEmpty);
  });

  test('🎯off is an answer: written with no days, and read as a no', () async {
    await store.save(const UsageStatsOn([20755]));
    await store.save(const UsageStatsOff());
    expect(file(), {'version': 1, 'enabled': false});
    expect(await store.load(), isA<UsageStatsOff>());
  });

  test('⛔a file that says off brings back no record, whatever days it '
      'holds', () async {
    await File(store.filePath).writeAsString(
      jsonEncode({
        'version': 1,
        'enabled': false,
        'activeDays': [20755],
      }),
    );
    expect(await store.load(), isA<UsageStatsOff>());
  });

  test('a file it cannot read holds no answer — the question is asked '
      'again', () async {
    for (final text in [
      '{not json',
      jsonEncode({'version': 1, 'activeDays': [20755]}),
      jsonEncode({'version': 1, 'enabled': 'yes', 'activeDays': []}),
      jsonEncode({'version': 1, 'enabled': true, 'activeDays': ['a']}),
      jsonEncode({'version': 1, 'enabled': true}),
      jsonEncode({
        'version': UsageStatsStore.version + 1,
        'enabled': true,
        'activeDays': [20755],
      }),
    ]) {
      await File(store.filePath).writeAsString(text);
      expect(await store.load(), isNull, reason: text);
    }
  });
}
