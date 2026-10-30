import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/services/persistence/app_accent_settings_store.dart';
import 'package:anicel/src/services/persistence/settings_file.dart';
import 'package:anicel/src/services/persistence/settings_room_file.dart';
import 'package:anicel/src/ui/brush/brush_hand_settings_store.dart';
import 'package:anicel/src/ui/import/settings_rows.dart';

/// I-142 (유저 2026-10-29): a settings file comes in as the import window's
/// rows (Q6) — 「설정마다 한 줄 (브러시 셋만 한 줄)」 (Q9) — and the rows
/// are the room's travelling entries, one list.
void main() {
  SettingsFile holding(
    Map<String, Map<String, dynamic>> documents, {
    Map<String, Uint8List> files = const {},
    Set<String> atDefaults = const {},
  }) => (documents: documents, files: files, atDefaults: atDefaults);

  SettingsRow row(String id) => settingsRows.singleWhere((row) => row.id == id);

  test('every travelling entry is put in place by exactly one row', () {
    final entries = [for (final row in settingsRows) ...row.entries];
    expect(entries.toSet(), travellingSettingsEntries.toSet());
    expect(entries, hasLength(travellingSettingsEntries.length));
    expect({for (final row in settingsRows) row.id}, hasLength(16 + 1));
  });

  test('a row a setting — but the brushes\' three, which name each other, '
      'one row', () {
    for (final row in settingsRows) {
      expect(
        row.entries,
        row.id == 'brushes'
            ? ['brush_presets.json', 'brush_tips', 'brush_hand_settings.json']
            : [row.id],
        reason: row.id,
      );
    }
  });

  test('each row is read again by whoever reads it at the start', () {
    expect(
      {
        for (final row in settingsRows)
          if (row.reader != SettingsReader.appSettings) row.id: row.reader,
      },
      {
        'ui_scale.json': SettingsReader.uiScale,
        'export_settings.json': SettingsReader.exportWindow,
        'workspace_layout.json': SettingsReader.layout,
        'color_palette.json': SettingsReader.palette,
        'shortcut_overrides.json': SettingsReader.shortcuts,
        'brushes': SettingsReader.brushes,
      },
    );
  });

  test('a row is held by its document, or by a file under its folder', () {
    final tips = holding({}, files: {'brush_tips/t1.png': Uint8List(3)});
    expect(row('brushes').heldBy(tips), isTrue);
    expect(row('accent_settings.json').heldBy(tips), isFalse);
    expect(
      row('accent_settings.json').heldBy(
        holding({
          'accent_settings.json': {'version': 1},
        }),
      ),
      isTrue,
    );
  });

  // 🗣️I-142-Q3: 「전부 갈아끼운다」 — a setting at its defaults comes too.
  test('a row is held by an entry the file holds at its defaults', () {
    final atDefaults = holding({}, atDefaults: {'accent_settings.json'});
    expect(row('accent_settings.json').heldBy(atDefaults), isTrue);
    expect(row('ui_scale.json').heldBy(atDefaults), isFalse);
    expect(
      row('brushes').heldBy(holding({}, atDefaults: {'brush_tips'})),
      isTrue,
    );
  });

  test('a row reads a document no newer than its store — and nothing in its '
      'way where the file holds none of it', () {
    const version = AppAccentSettingsStore.version;
    bool reads(Object? written) => row('accent_settings.json').readsIn(
      holding({
        'accent_settings.json': {'version': written},
      }),
    );
    expect(reads(version), isTrue);
    expect(reads(0), isTrue, reason: 'an older one its store brings forward');
    expect(reads(version + 1), isFalse);
    expect(reads('one'), isFalse);
    expect(row('accent_settings.json').readsIn(holding({})), isTrue);
  });

  test('the brushes read only the library\'s own version — any other the '
      'library replaces with its built-ins', () {
    bool reads(Map<String, Map<String, dynamic>> documents) =>
        row('brushes').readsIn(holding(documents));
    const library = BrushPresetFileService.libraryVersion;
    expect(
      reads({
        'brush_presets.json': {'version': library},
      }),
      isTrue,
    );
    expect(
      reads({
        'brush_presets.json': {'version': library - 1},
      }),
      isFalse,
    );
    expect(
      reads({
        'brush_tips/index.json': {
          'version': BrushTipLibraryService.indexVersion + 1,
        },
      }),
      isFalse,
    );
    expect(
      reads({
        'brush_hand_settings.json': {'version': 'one'},
      }),
      isFalse,
    );
    expect(
      reads({
        'brush_hand_settings.json': {'version': BrushHandSettingsStore.version},
      }),
      isTrue,
      reason: 'a file of the hand settings alone holds no library in the way',
    );
  });
}
