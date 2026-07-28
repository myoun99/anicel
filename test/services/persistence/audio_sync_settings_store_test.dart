import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/audio_sync_settings_store.dart';
import 'package:anicel/src/ui/playback/audio_sync_settings.dart';

void main() {
  late Directory temp;
  late String path;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('qa_avsync_');
    path = '${temp.path}/audio_sync_settings.json';
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } on Object {
      // A locked file on Windows must not fail the suite.
    }
  });

  test('a saved offset comes back', () async {
    final store = AudioSyncSettingsStore(filePath: path);
    const settings = AudioSyncSettings(offset: -4, unit: AvOffsetUnit.frames);
    await store.save(settings);
    expect(await store.load(), settings);
  });

  test('a missing file yields null so the caller uses the defaults', () async {
    expect(
      await AudioSyncSettingsStore(filePath: '${temp.path}/nope.json').load(),
      isNull,
    );
  });

  test('a corrupt file yields null rather than throwing', () async {
    File(path).writeAsStringSync('{ this is not json');
    expect(await AudioSyncSettingsStore(filePath: path).load(), isNull);
  });

  test('a newer version is refused rather than misread', () async {
    File(path).writeAsStringSync(
      jsonEncode({'version': 99, 'avOffset': 100, 'avOffsetUnit': 'frames'}),
    );
    expect(await AudioSyncSettingsStore(filePath: path).load(), isNull);
  });

  test('a hand-edited extreme value is clamped on read', () async {
    File(path).writeAsStringSync(
      jsonEncode({
        'version': 1,
        'avOffset': 99999,
        'avOffsetUnit': 'milliseconds',
      }),
    );
    expect((await AudioSyncSettingsStore(filePath: path).load())!.offset, 500);
  });

  test('the directory is created on first save', () async {
    final nested = '${temp.path}/a/b/settings.json';
    await AudioSyncSettingsStore(
      filePath: nested,
    ).save(const AudioSyncSettings(offset: 25));
    expect(File(nested).existsSync(), isTrue);
  });

  test('the default path sits beside the other app settings', () {
    // The offset describes the RIG, not the film — it belongs with the
    // language and input settings, never in the .anicel.
    final defaultPath = AudioSyncSettingsStore.defaultFilePath();
    expect(defaultPath, contains('anicel'));
    expect(defaultPath, endsWith('audio_sync_settings.json'));
  });
}
