import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart'
    show appSettingsFilePath;
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/settings_file.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_file_import.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_dialog.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_store.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/settle_async.dart';
import '../../helpers/temp_dir.dart';

/// I-142 (유저 2026-10-29): 「키보드 단축키 내보내기 등 … 임포트도 물론」,
/// by the preset (I-142-Q4: 「프리셋 하나」) from its own row (I-142-Q1:
/// 「주인 자리에서 내보내고, 읽기는 「파일 열기」 하나」). What comes back in
/// is a new preset of the user's, which comes into use — I-107-Q1's
/// 「가져올땐 새 프리셋으로서 등록」, as a program's files are.
void main() {
  late EditorShortcutBindings bindings;
  late EditorShortcutBindings elsewhere;

  setUp(() {
    bindings = EditorShortcutBindings();
    elsewhere = EditorShortcutBindings();
  });
  tearDown(() {
    bindings.dispose();
    elsewhere.dispose();
  });

  const f9 = SingleActivator(LogicalKeyboardKey.f9);
  const f2 = SingleActivator(LogicalKeyboardKey.f2);

  /// [actionId]'s live keys as the window writes them on a PC.
  List<String> keysOf(String actionId, EditorShortcutBindings held) => [
    for (final key in held.activatorsFor(actionId))
      singleActivatorLabel(key, TargetPlatform.windows),
  ];

  /// [preset] of [bindings] as its row writes it, under [name].
  String fileOf(ShortcutLayout preset, String name) =>
      shortcutPresetSettingsFile(bindings.asOwn(preset, name));

  Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

  group('the file', () {
    test('⛔fixture premise: what the TVPaint preset holds', () {
      bindings.setPreset(ShortcutPreset.tvpaint);
      expect(keysOf(EditorActionIds.undo, bindings), ['Ctrl+Z', 'U']);
      expect(keysOf(EditorActionIds.cutNew, bindings), isNot(['F9']));
      expect(keysOf(EditorActionIds.cutNew, elsewhere), isNot(['F9']));
    });

    test('a preset the app ships leaves as the user has it — what was '
        'recorded over it along — and comes back a new preset of the '
        'user\'s, in use', () {
      bindings
        ..setPreset(ShortcutPreset.tvpaint)
        ..setActivators(EditorActionIds.cutNew, const [f9])
        ..setPreset(ShortcutPreset.anicel);

      final brought = elsewhere.presetsBroughtFrom(
        fileOf(ShortcutPreset.tvpaint, 'TVPaint'),
      )!;

      expect(elsewhere.userPresets, brought);
      expect(elsewhere.preset, brought.single);
      expect((brought.single.name, brought.single.base), (
        'TVPaint',
        ShortcutPreset.tvpaint,
      ));
      expect(keysOf(EditorActionIds.cutNew, elsewhere), ['F9']);
      expect(keysOf(EditorActionIds.undo, elsewhere), ['Ctrl+Z', 'U']);
      expect(
        elsewhere.isOverridden(EditorActionIds.cutNew),
        isFalse,
        reason: 'F9 is a key it was made with',
      );
    });

    test('a preset of the user\'s leaves whole — what it was made with and '
        'what was recorded under it', () {
      bindings
        ..setPreset(ShortcutPreset.tvpaint)
        ..setActivators(EditorActionIds.cutNew, const [f9]);
      final mine = bindings.duplicatePreset(bindings.preset, 'Mine');
      bindings.setActivators(EditorActionIds.undo, const [f2]);

      elsewhere.presetsBroughtFrom(fileOf(mine, 'Mine'));

      expect(elsewhere.preset.base, ShortcutPreset.tvpaint);
      expect(keysOf(EditorActionIds.cutNew, elsewhere), ['F9']);
      expect(keysOf(EditorActionIds.undo, elsewhere), ['F2']);
    });

    test('brought in twice, it is two presets — never the id of one still '
        'on the list', () {
      final mine = bindings.duplicatePreset(ShortcutPreset.tvpaint, 'Mine');
      final file = fileOf(mine, 'Mine');

      elsewhere
        ..presetsBroughtFrom(file)
        ..presetsBroughtFrom(file);
      bindings.presetsBroughtFrom(file);

      expect([for (final preset in elsewhere.userPresets) preset.name], [
        'Mine',
        'Mine',
      ]);
      for (final held in [elsewhere, bindings]) {
        expect({for (final preset in held.userPresets) preset.id}, hasLength(2));
      }
    });

    test('it is the shortcut store\'s own document, under the name of the '
        'store\'s file', () {
      expect(
        appSettingsFilePath(ShortcutSettingsStore.fileName),
        ShortcutSettingsStore.defaultShortcutSettingsFilePath(),
      );
      final documents = decodeSettingsFile(
        fileOf(ShortcutPreset.anicel, 'Anicel'),
      )!;
      expect(documents.keys, [ShortcutSettingsStore.fileName]);
      expect(documents.values.single['version'], ShortcutSettingsStore.version);
    });

    test('an action this build does not know is left out, as the store '
        'leaves it out of its own file', () {
      final file = encodeSettingsFile({
        ShortcutSettingsStore.fileName: {
          'version': ShortcutSettingsStore.version,
          'presets': [
            {
              'id': 'user-9',
              'name': 'From later',
              'base': ShortcutPreset.tvpaint.name,
              'keys': {
                'anActionNotYetShipped': [singleActivatorToJson(f9)],
                EditorActionIds.cutNew: [singleActivatorToJson(f2)],
              },
            },
          ],
        },
      });

      final brought = elsewhere.presetsBroughtFrom(file)!.single;

      expect(brought.ownKeys.keys, [EditorActionIds.cutNew]);
      expect(keysOf(EditorActionIds.cutNew, elsewhere), ['F2']);
    });
  });

  group('「파일 열기」', () {
    test('says a line for each preset it brought', () {
      final mine = bindings.duplicatePreset(ShortcutPreset.tvpaint, 'Mine');

      expect(
        importShortcutFiles(elsewhere, [
          (
            name: 'Mine.$anicelShortcutExtension',
            bytes: bytesOf(fileOf(mine, 'Mine')),
          ),
        ]),
        [AppText.strings.shortcutPresetBrought('Mine')],
      );
      expect(elsewhere.preset, elsewhere.userPresets.single);
    });

    test('a file of ours that holds no preset is named, and nothing comes '
        'in', () {
      final written = decodeSettingsFile(
        fileOf(ShortcutPreset.anicel, 'Anicel'),
      )!.values.single;
      String withDocument(Map<String, dynamic> document) =>
          encodeSettingsFile({ShortcutSettingsStore.fileName: document});
      const name = 'Broken.$anicelShortcutExtension';

      for (final bytes in [
        bytesOf('not json'),
        Uint8List.fromList([0xFF, 0xFE, 0x00]),
        bytesOf(encodeSettingsFile({})),
        bytesOf(
          withDocument({
            ...written,
            'version': ShortcutSettingsStore.version + 1,
          }),
        ),
        bytesOf(withDocument({...written, 'presets': []})),
        bytesOf(withDocument({...written, 'presets': 'x'})),
      ]) {
        expect(importShortcutFiles(elsewhere, [(name: name, bytes: bytes)]), [
          AppText.strings.shortcutFileUnreadable(name),
        ]);
      }
      expect(elsewhere.userPresets, isEmpty);
      expect(
        importShortcutFiles(elsewhere, [
          (name: name, bytes: bytesOf(withDocument(written))),
        ]),
        [AppText.strings.shortcutPresetBrought('Anicel')],
        reason: '⛔전제: the document as it was written is read',
      );
    });
  });

  group('a row\'s export', () {
    late Directory folder;

    setUp(() => folder = Directory.systemTemp.createTempSync('qa_preset_'));
    tearDown(() {
      FolderPicker.debugOperatingSystem = null;
      FolderPicker.debugSaveDestinationPicker = null;
      deleteTempQuietly(folder);
    });

    Finder byKey(String key) => find.byKey(ValueKey<String>(key));

    testWidgets('asks where under the row\'s name, writes the file 「파일 '
        '열기」 reads back, and says so — the row\'s preset, not the one in '
        'use', (tester) async {
      FolderPicker.debugOperatingSystem = 'windows';
      final asked = <String>[];
      FolderPicker.debugSaveDestinationPicker = ({
        required String suggestedName,
        String? initialDirectory,
      }) async {
        asked.add(suggestedName);
        return FolderGrant.granted(
          path: '${folder.path}/$suggestedName',
          kind: GrantKind.file,
        );
      };
      bindings
        ..setPreset(ShortcutPreset.tvpaint)
        ..setActivators(EditorActionIds.cutNew, const [f9])
        ..setPreset(ShortcutPreset.anicel);
      final shown = AppText.strings.shortcutPresetName(
        ShortcutPreset.tvpaint.name,
        ShortcutPreset.tvpaint.label,
      );
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShortcutSettingsDialog(bindings: bindings)),
        ),
      );
      await tester.pump();

      await tester.tap(byKey('shortcut-preset'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('shortcut-preset-tvpaint-export'));
      final notice = find.byType(AppConfirmDialog);
      await settleAsync(
        tester,
        () => notice.evaluate().isNotEmpty,
        everyFrame: tester.pump,
      );

      expect(asked, ['$shown.$anicelShortcutExtension']);
      final brought = elsewhere.presetsBroughtFrom(
        File('${folder.path}/${asked.single}').readAsStringSync(),
      )!;
      expect(brought.single.name, shown);
      expect(keysOf(EditorActionIds.cutNew, elsewhere), ['F9']);
      expect(bindings.preset, ShortcutPreset.anicel);
      expect(
        tester.widget<AppConfirmDialog>(notice).message,
        AppText.strings.settingsExported(shown),
      );
    });
  });
}
