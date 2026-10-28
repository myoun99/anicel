import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/persistence/usage_stats_store.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️I-70-Q3 (유저 2026-10-29): 「기본 꺼짐」 — and the record of days lives
/// on the device only while the switch is on.
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

  test('🎯no file is OFF — a missing file is not an error', () async {
    expect(await store.load(), isNull);
  });

  test('on, with its days, is what the next launch reads', () async {
    await store.save([20754, 20755]);
    expect(file(), {
      'version': 1,
      'enabled': true,
      'activeDays': [20754, 20755],
    });
    expect(
      await UsageStatsStore(filePath: store.filePath).load(),
      [20754, 20755],
    );

    await store.save(const []);
    expect(await store.load(), isEmpty);
  });

  test('🎯off is written with no days, and read as off', () async {
    await store.save([20755]);
    await store.save(null);
    expect(file(), {'version': 1, 'enabled': false, 'activeDays': []});
    expect(await store.load(), isNull);
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
    expect(await store.load(), isNull);

    await File(store.filePath).writeAsString(
      jsonEncode({'version': 1, 'activeDays': [20755]}),
    );
    expect(await store.load(), isNull, reason: 'no answer is off');
  });

  test('a file it cannot read is off', () async {
    for (final text in [
      '{not json',
      jsonEncode({'version': 1, 'enabled': 'yes', 'activeDays': []}),
      jsonEncode({'version': 1, 'enabled': true, 'activeDays': ['a']}),
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
