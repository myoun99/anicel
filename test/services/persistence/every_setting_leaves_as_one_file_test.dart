import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart';
import 'package:anicel/src/services/persistence/settings_file.dart';
import 'package:anicel/src/services/persistence/settings_room_file.dart';

import '../../helpers/temp_dir.dart';

/// I-142 (유저 2026-10-29): every setting leaves as one file — the settings
/// room as it stands, each store's document as its store wrote it (Q5), but
/// for the four bound to this machine (Q2: 「기계에 묶인 넷은 넣지
/// 않는다」).
void main() {
  test('what travels is the room but the recent projects, the window, the '
      'memory and the fonts', () {
    expect(settingsBoundToThisMachine, {
      'recent_projects.json',
      'window.json',
      'memory_settings.json',
      'fonts',
    });
    expect(travellingSettingsEntries, [
      for (final entry in appSettingsEntries)
        if (!settingsBoundToThisMachine.contains(entry)) entry,
    ]);
    expect(travellingSettingsEntries, hasLength(19));
    expect(
      appSettingsEntries.toSet().containsAll(settingsBoundToThisMachine),
      isTrue,
      reason: '⛔전제: each one kept back is a room entry',
    );
  });

  test('under a test the room is a sandbox, never the developer\'s own', () {
    for (final entry in travellingSettingsEntries) {
      expect(settingsRoomPath(entry), isNot(appSettingsFilePath(entry)));
      expect(settingsRoomPath(entry), startsWith(testContainerFolder()));
      expect(settingsRoomPath(entry), endsWith('/Settings/$entry'));
    }
  });

  group('the file of the room', () {
    late Directory room;

    setUp(() => room = Directory.systemTemp.createTempSync('qa_room_'));
    tearDown(() => deleteTempQuietly(room));

    String at(String entry) => '${room.path}/$entry';
    void put(String entry, Object contents) {
      final file = File(at(entry))..parent.createSync(recursive: true);
      switch (contents) {
        case final Uint8List bytes:
          file.writeAsBytesSync(bytes);
        case final String text:
          file.writeAsStringSync(text);
      }
    }

    final tip = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);

    test('holds each entry\'s document as it stands, and a folder\'s files '
        'by their names under it', () async {
      put('ui_scale.json', jsonEncode({'version': 1, 'scale': 1.25}));
      put('brush_tips/index.json', jsonEncode({'version': 1, 'tips': []}));
      put('brush_tips/t1.png', tip);

      final read = readSettingsFile(
        await settingsFileOfTheRoom([
          'ui_scale.json',
          'brush_tips',
        ], at: at),
      )!;

      expect(read.documents, {
        'ui_scale.json': {'version': 1, 'scale': 1.25},
        'brush_tips/index.json': {'version': 1, 'tips': <Object?>[]},
      });
      expect(read.files.keys, ['brush_tips/t1.png']);
      expect(read.files.values.single, tip);
    });

    test('leaves out an entry no store has written, one it was not asked '
        'for, and a document that is no JSON object', () async {
      put('ui_scale.json', '{"version": 1, "sca');
      put('accent_settings.json', jsonEncode([1, 2]));
      put('window.json', jsonEncode({'version': 1}));
      put('language_settings.json', jsonEncode({'version': 1, 'code': 'ko'}));

      final read = readSettingsFile(
        await settingsFileOfTheRoom([
          'ui_scale.json',
          'accent_settings.json',
          'language_settings.json',
          'onion_skin_settings.json',
        ], at: at),
      )!;

      expect(read.documents.keys, ['language_settings.json']);
      expect(read.files, isEmpty);
    });
  });
}
