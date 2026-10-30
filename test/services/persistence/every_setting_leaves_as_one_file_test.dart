import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart';
import 'package:anicel/src/services/persistence/settings_file.dart';
import 'package:anicel/src/services/persistence/settings_room_file.dart';
import 'package:anicel/src/services/persistence/versioned_settings_file.dart';

import '../../helpers/temp_dir.dart';

/// I-142 (유저 2026-10-29): every setting leaves as one file — the settings
/// room as it stands, each store's document as its store wrote it (Q5), but
/// for the four bound to this machine (Q2: 「기계에 묶인 넷은 넣지
/// 않는다」) and the two that are this device's own — the launch notice's
/// dismissal and the usage statistics (I-70) — and the fx plugins, installed
/// here as the fonts are (I-132).
void main() {
  test('what travels is the room but the recent projects, the window, the '
      'memory, the fonts, the fx plugins, the launch notice and the usage '
      'statistics', () {
    expect(settingsBoundToThisMachine, {
      'recent_projects.json',
      'window.json',
      'memory_settings.json',
      'fonts',
      'fx_plugins',
      'launch_notice.json',
      'usage_stats.json',
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
      put('brush_tips/a0.png', tip);

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
      expect(read.files.keys, [
        'brush_tips/a0.png',
        'brush_tips/t1.png',
      ], reason: 'by name: the same room reads the same on every machine');
      expect(read.files.values.first, tip);
    });

    // 🗣️I-142-Q3: 「전부 갈아끼운다」 — what its store reads as its defaults
    // goes as its defaults.
    test('holds at its defaults an entry no store has written, a document '
        'that is no JSON object and an empty folder — and nothing of one it '
        'was not asked for', () async {
      put('ui_scale.json', '{"version": 1, "sca');
      put('accent_settings.json', jsonEncode([1, 2]));
      put('window.json', jsonEncode({'version': 1}));
      put('language_settings.json', jsonEncode({'version': 1, 'code': 'ko'}));
      Directory(at('brush_tips')).createSync();

      final read = readSettingsFile(
        await settingsFileOfTheRoom([
          'ui_scale.json',
          'accent_settings.json',
          'language_settings.json',
          'onion_skin_settings.json',
          'brush_tips',
        ], at: at),
      )!;

      expect(read.documents.keys, ['language_settings.json']);
      expect(read.files, isEmpty);
      expect(read.atDefaults, {
        'ui_scale.json',
        'accent_settings.json',
        'onion_skin_settings.json',
        'brush_tips',
      });
    });

    // 🗣️I-142-Q3: 「전부 갈아끼운다」 · Q7: 「남기지 않는다」.
    test('put back in the room, a document stands as the file holds it and '
        'a folder holds the file\'s files and nothing else', () async {
      put('ui_scale.json', jsonEncode({'version': 1, 'scale': 2.0}));
      put('brush_tips/index.json', jsonEncode({'version': 1, 'tips': []}));
      put('brush_tips/old.png', tip);
      final file = readSettingsFile(
        encodeSettingsFile(
          {
            'ui_scale.json': {'version': 1, 'scale': 1.25},
            'brush_tips/index.json': {
              'version': 1,
              'tips': ['t1'],
            },
          },
          files: {'brush_tips/t1.png': tip},
        ),
      )!;

      await putSettingsIntoTheRoom(file, [
        'ui_scale.json',
        'brush_tips',
      ], at: at);

      expect(jsonDecode(File(at('ui_scale.json')).readAsStringSync()), {
        'version': 1,
        'scale': 1.25,
      });
      expect(
        jsonDecode(File(at('brush_tips/index.json')).readAsStringSync()),
        {
          'version': 1,
          'tips': ['t1'],
        },
      );
      expect(File(at('brush_tips/t1.png')).readAsBytesSync(), tip);
      expect(
        File(at('brush_tips/old.png')).existsSync(),
        isFalse,
        reason: 'what the folder held before goes with it',
      );
    });

    test('puts only the entries asked for, and inside a folder only a plain '
        'file name — none that climbs out of it or into one below', () async {
      put('accent_settings.json', jsonEncode({'version': 1, 'kept': true}));
      final file = readSettingsFile(
        encodeSettingsFile(
          {
            'accent_settings.json': {'version': 1, 'kept': false},
          },
          files: {
            'brush_tips/../escaped.png': tip,
            r'brush_tips/..\escaped.png': tip,
            'brush_tips/..': tip,
            'brush_tips/.': tip,
            'brush_tips/': tip,
            'brush_tips/deeper/t2.png': tip,
            'brush_tips/t1.png': tip,
          },
        ),
      )!;

      await putSettingsIntoTheRoom(file, ['brush_tips'], at: at);

      expect(
        jsonDecode(File(at('accent_settings.json')).readAsStringSync()),
        {'version': 1, 'kept': true},
        reason: 'the file holds it, but it was not asked for',
      );
      expect(
        [
          for (final entity in Directory(at('brush_tips')).listSync())
            entity.uri.pathSegments.last,
        ],
        ['t1.png'],
      );
      expect(File(at('escaped.png')).existsSync(), isFalse);
    });

    test('an entry held at its defaults holds nothing once put back — a '
        'document\'s file goes, after a save already on its way, and a '
        'folder\'s files go', () async {
      put('accent_settings.json', jsonEncode({'version': 1, 'a': 1}));
      put('brush_tips/old.png', tip);
      final onItsWay = saveVersionedSettings(
        filePath: at('ui_scale.json'),
        version: 1,
        json: {'scale': 1.5},
      );
      const entries = [
        'accent_settings.json',
        'brush_tips',
        'ui_scale.json',
        'onion_skin_settings.json',
      ];
      final file = readSettingsFile(
        encodeSettingsFile({}, atDefaults: entries.toSet()),
      )!;

      await putSettingsIntoTheRoom(file, entries, at: at);
      await onItsWay;

      expect(File(at('accent_settings.json')).existsSync(), isFalse);
      expect(Directory(at('brush_tips')).listSync(), isEmpty);
      expect(
        File(at('ui_scale.json')).existsSync(),
        isFalse,
        reason: 'the save on its way landed before the removal, not over it',
      );
      expect(File(at('onion_skin_settings.json')).existsSync(), isFalse);
    });

    test('leaves an entry the file does not hold as it stands', () async {
      put('brush_tips/old.png', tip);
      put('onion_skin_settings.json', jsonEncode({'version': 1, 'a': 1}));
      final file = readSettingsFile(encodeSettingsFile({}))!;

      await putSettingsIntoTheRoom(file, [
        'brush_tips',
        'onion_skin_settings.json',
      ], at: at);

      expect(File(at('brush_tips/old.png')).existsSync(), isTrue);
      expect(
        jsonDecode(File(at('onion_skin_settings.json')).readAsStringSync()),
        {'version': 1, 'a': 1},
      );
    });
  });
}
