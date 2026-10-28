import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/persistence/launch_notice_store.dart';
import '../../helpers/temp_dir.dart';

void main() {
  late Directory directory;
  late LaunchNoticeStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('launch_notice_store');
    store = LaunchNoticeStore(filePath: '${directory.path}/launch_notice.json');
  });

  tearDown(() => deleteTempQuietly(directory));

  test('nothing dismissed yet is no key — a missing file is not an '
      'error', () async {
    expect(await store.load(), isNull);
  });

  test('the key dismissed is the key the next launch reads', () async {
    await store.save('0badf00d');
    expect(await store.load(), '0badf00d');
    // The newer dismissal is the one kept.
    await store.save('1234abcd');
    expect(
      await LaunchNoticeStore(filePath: store.filePath).load(),
      '1234abcd',
    );
  });

  test('a file it cannot read is nothing dismissed', () async {
    await File(store.filePath).writeAsString('{not json');
    expect(await store.load(), isNull);

    await File(store.filePath).writeAsString(
      jsonEncode({'version': 1, 'dismissed': 7}),
    );
    expect(await store.load(), isNull);

    await File(store.filePath).writeAsString(
      jsonEncode({
        'version': LaunchNoticeStore.version + 1,
        'dismissed': '0badf00d',
      }),
    );
    expect(await store.load(), isNull);
  });
}
