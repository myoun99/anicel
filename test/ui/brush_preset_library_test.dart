import 'package:anicel/src/models/brush_hand_settings.dart';
import 'package:anicel/src/ui/brush/picked_file.dart';
import 'package:anicel/src/services/brush_pack_file.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_group.dart';
import 'package:anicel/src/models/brush_group_icon.dart';
import 'package:anicel/src/models/brush_group_id.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/ui/brush/brush_tip_library.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/persistence/versioned_settings_file.dart';
import 'package:anicel/src/ui/brush/brush_import_merge.dart';
import 'package:anicel/src/ui/brush/brush_preset_library.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import '../helpers/temp_dir.dart';
import '../services/abr_test_builder.dart';

const _ink = BrushGroupId('ink');
const _paint = BrushGroupId('paint');

BrushPreset _preset(String id, {BrushGroupId? groupId}) => BrushPreset(
  id: BrushPresetId(id),
  name: id,
  groupId: groupId,
  settings: BrushSettings(size: 5),
);

void main() {
  late Directory tempDirectory;
  late BrushPresetFileService service;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'brush_preset_library_test',
    );
    service = BrushPresetFileService(
      filePath: '${tempDirectory.path}/presets.json',
    );
  });

  tearDown(() => deleteTempQuietly(tempDirectory));

  /// A library loaded from a seeded file.
  Future<BrushPresetLibrary> seeded({
    List<BrushGroup> groups = const [
      BrushGroup(id: _ink, name: 'Ink'),
      BrushGroup(id: _paint, name: 'Paint'),
    ],
    List<BrushPreset>? presets,
  }) async {
    await service.save((
      groups: groups,
      presets:
          presets ??
          [
            _preset('i1', groupId: _ink),
            _preset('i2', groupId: _ink),
            _preset('p1', groupId: _paint),
            _preset('loose'),
          ],
    ));
    final library = BrushPresetLibrary(fileService: service);
    await library.load();
    return library;
  }

  // The pick phase is the one the tip library runs too
  // (brush_tip_library_test pins the same answers).
  group('importFromFile', () {
    test('a picker that throws answers with the error, not a crash', () async {
      final library = BrushPresetLibrary(
        fileService: service,
        filePicker: () async => throw StateError('no dialog'),
      );
      addTearDown(library.dispose);

      expect(
        await library.importFromFile(),
        'Could not open the file: Bad state: no dialog',
      );
    });

    test('it answers in the program language — a picker that throws, and a '
        'file that reads as no brush file', () async {
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      final ko = AppStrings.of(AppLanguage.ko);
      final throwing = BrushPresetLibrary(
        fileService: service,
        filePicker: () async => throw StateError('no dialog'),
      );
      addTearDown(throwing.dispose);
      // Not UTF-8 at all, under the app's own brush extension.
      final garbled = BrushPresetLibrary(
        fileService: service,
        filePicker: () async =>
            (name: 'x.anibrush', bytes: Uint8List.fromList([0xFF, 0xFE])),
      );
      addTearDown(garbled.dispose);

      expect(
        await throwing.importFromFile(),
        ko.brImportPickFailed('Bad state: no dialog'),
      );
      expect(await garbled.importFromFile(), ko.brImportUnreadable);
    });

    test('🎯each reader\'s refusal is said in the program language — the '
        'Anicel brush file, Photoshop\'s and CLIP STUDIO\'s (F-273)', () async {
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      const untabled = ' ';
      final ko = AppStrings.of(AppLanguage.ko);
      Future<String?> refusalOf(String name, List<int> bytes) async {
        final library = BrushPresetLibrary(
          fileService: service,
          filePicker: () async =>
              (name: name, bytes: Uint8List.fromList(bytes)),
        );
        addTearDown(library.dispose);
        return library.importFromFile();
      }

      expect(
        await refusalOf('x.anibrush', utf8.encode('{"presets":[]}')),
        ko.importWarning('brushPackNotOurs', untabled),
      );
      expect(
        await refusalOf('x.abr', const [0, 6]),
        ko.importWarning('abrTooShort', untabled),
      );
      // An empty file is an empty database to SQLite: no tables at all.
      expect(
        await refusalOf('x.sut', const []),
        ko.importWarning('sutNoBrushData', untabled),
      );
    });

    test('a file that lands with warnings says so in the program language — '
        'its brushes counted, and how many said something', () async {
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      final ko = AppStrings.of(AppLanguage.ko);
      // Two tips: one at 8 bits, and one at 16 the decoder skips with a
      // warning.
      final samp = AbrBytes();
      writeSampEntry(
        samp,
        uuid: 'deep-tip',
        width: 2,
        height: 2,
        pixels: List<int>.filled(8, 1),
        depth: 16,
      );
      writeSampEntry(
        samp,
        uuid: 'ok-tip',
        width: 2,
        height: 2,
        pixels: List<int>.filled(4, 9),
      );
      final file = AbrBytes()
        ..i16(6)
        ..i16(2);
      write8bimSection(file, 'samp', samp.bytes);
      final library = BrushPresetLibrary(
        fileService: service,
        filePicker: () async => (name: 'pack.abr', bytes: file.bytes),
      );
      addTearDown(library.dispose);

      expect(
        await library.importFromFile(),
        ko.brImportWarnings(ko.brImported(1, 'pack.abr'), 1),
      );
    });

    test('a cancelled pick is nothing, not an error', () async {
      final library = BrushPresetLibrary(
        fileService: service,
        filePicker: () async => null,
      );
      addTearDown(library.dispose);

      expect(await library.importFromFile(), isNull);
    });

    test('a file outside the brush kinds is refused BY NAME, before any '
        'decoder sees the bytes (유저 2026-08-29)', () async {
      final library = BrushPresetLibrary(
        fileService: service,
        filePicker: () async =>
            (name: 'photo.jpg', bytes: Uint8List.fromList([0xFF, 0xD8])),
      );
      addTearDown(library.dispose);

      final message = await library.importFromFile();
      expect(message, isNotNull);
      expect(message, contains('.abr'));
      expect(message, isNot(contains('{kinds}')));
      expect(library.presets, isEmpty);
    });
  });

  group('groups', () {
    test('load reads groups and presets', () async {
      final library = await seeded();

      expect(library.groups.map((group) => group.name), ['Ink', 'Paint']);
      expect(library.presets.length, 4);
      addTearDown(library.dispose);
    });

    test('createGroup appends an EMPTY group', () async {
      final library = await seeded();
      addTearDown(library.dispose);

      library.createGroup('Sketch');

      expect(library.groups.last.name, 'Sketch');
      expect(
        library.presets.where((p) => p.groupId == library.groups.last.id),
        isEmpty,
      );
    });

    test('editGroup leaves membership untouched', () async {
      final library = await seeded();
      addTearDown(library.dispose);

      library.editGroup(_ink, 'Inking', BrushGroupIcon.pen);

      expect(library.groups.first.name, 'Inking');
      expect(library.groups.first.icon, BrushGroupIcon.pen);
      expect(
        library.presets.where((p) => p.groupId == _ink).map((p) => p.id.value),
        ['i1', 'i2'],
      );
    });

    test('editGroup can take a group back to no icon', () async {
      // Null has to be WRITABLE, not just absent: clearing is how a group
      // goes back to wearing its first brush.
      final library = await seeded();
      addTearDown(library.dispose);

      library.editGroup(_ink, 'Inking', BrushGroupIcon.pen);
      library.editGroup(_ink, 'Inking', null);

      expect(library.groups.first.icon, isNull);
    });

    test('deleteGroup drops the group AND its members', () async {
      final library = await seeded();
      addTearDown(library.dispose);

      library.deleteGroup(_ink);

      expect(library.groups.map((group) => group.id), [_paint]);
      expect(library.presets.map((p) => p.id.value), ['p1', 'loose']);
    });

    test('setGroupCollapsed folds one group only', () async {
      final library = await seeded();
      addTearDown(library.dispose);

      library.setGroupCollapsed(_paint, true);

      expect(library.groups.first.collapsed, isFalse);
      expect(library.groups.last.collapsed, isTrue);
    });

    test('the fold state survives a reload', () async {
      final library = await seeded();
      library.setGroupCollapsed(_paint, true);
      // Fold state is persisted with the library, unlike the row view
      // toggles which are panel-local session state.
      await service.save((groups: library.groups, presets: library.presets));
      library.dispose();

      final reloaded = BrushPresetLibrary(fileService: service);
      addTearDown(reloaded.dispose);
      await reloaded.load();

      expect(reloaded.groups.last.collapsed, isTrue);
    });

    test('arrange takes a new group order and a preset into another group',
        () async {
      final library = await seeded();
      addTearDown(library.dispose);

      library.arrange(
        brushLibraryArrangementOf([
          for (final preset in library.presets)
            if (preset.id.value == 'loose')
              preset.copyWith(groupId: _paint)
            else
              preset,
        ], library.groups.reversed.toList()),
      );

      expect(library.groups.map((group) => group.name), ['Paint', 'Ink']);
      expect(
        library.presetsInGroup(_paint).map((preset) => preset.id.value),
        ['p1', 'loose'],
      );
    });

    // F-250 (유저 2026-10-01): 「브러시 그룹을 바꿀때 … 해당 그룹의 마지막으로
    // 선택했던걸 기억해서 그거 자동선택되도록」.
    test('entering a tab takes the remembered brush while it still shows '
        'there, the tab\'s first otherwise, nothing in an empty tab', () async {
      final library = await seeded();
      addTearDown(library.dispose);
      const i2 = BrushPresetId('i2');

      expect(library.presetEntering(_ink, remembered: i2), i2);
      expect(
        library.presetEntering(_ink)?.value,
        'i1',
        reason: 'nothing remembered: the first',
      );
      expect(
        library.presetEntering(_ink, remembered: const BrushPresetId('p1'))
            ?.value,
        'i1',
        reason: 'remembered somewhere else: the first',
      );
      expect(
        library.presetEntering(null)?.value,
        'loose',
        reason: 'the root section is a tab like any other',
      );

      library.arrange(
        brushLibraryArrangementOf([
          for (final preset in library.presets)
            if (preset.id == i2) preset.copyWith(groupId: _paint) else preset,
        ], library.groups),
      );
      expect(
        library.presetEntering(_ink, remembered: i2)?.value,
        'i1',
        reason: 'it moved out of the tab since',
      );

      library.createGroup('Empty');
      expect(library.presetEntering(library.groups.last.id), isNull);
    });

    // F-250: a move is undone by laying the old arrangement back, and the
    // library may have changed in ways that are not on the stack since.
    test('🚨an old arrangement laid back keeps a delete and an import made '
        'since', () async {
      final library = await seeded();
      addTearDown(library.dispose);
      final old = library.arrangement;
      library.arrange(
        brushLibraryArrangementOf(
          library.presets.reversed.toList(),
          library.groups,
        ),
      );
      library.delete(const BrushPresetId('i2'));
      final imported = library.saveCurrent(BrushSettings(size: 7));

      library.arrange(old);

      expect(library.presets.map((preset) => preset.id.value), [
        'i1',
        'p1',
        'loose',
        imported.id.value,
      ]);
    });

    test('a preset whose group is gone shows in the root tab', () async {
      final library = await seeded(
        presets: [
          _preset('i1', groupId: _ink),
          _preset('stale', groupId: const BrushGroupId('gone')),
          _preset('loose'),
        ],
      );
      addTearDown(library.dispose);

      expect(
        library.presetsInGroup(null).map((preset) => preset.id.value),
        ['stale', 'loose'],
      );
    });

    test('resetToDefaults restores the built-ins', () async {
      final library = await seeded();
      addTearDown(library.dispose);
      library.resetToDefaults();

      expect(library.presets, defaultBrushPresets);
      expect(library.groups, defaultBrushGroups);
    });
  });

  group('saveCurrent', () {
    test('lands in the given group', () async {
      final library = await seeded();
      addTearDown(library.dispose);

      final saved = library.saveCurrent(
        BrushSettings(size: 9),
        groupId: _paint,
      );

      expect(library.presets.last.groupId, _paint);
      expect(
        saved.id,
        library.presets.last.id,
        reason: 'the caller is handed the new preset — holding it is the '
            'tool state, not the library (H25-again)',
      );
    });

    test('falls back to root when the group is gone', () async {
      final library = await seeded();
      addTearDown(library.dispose);

      library.saveCurrent(
        BrushSettings(size: 9),
        groupId: const BrushGroupId('deleted'),
      );

      expect(library.presets.last.groupId, isNull);
    });
  });

  group('rename', () {
    // 🚨A MUTANT SURVIVED HERE (2026-09-16). Flipping `preset.id == id` to
    // `!=` in `BrushPresetLibrary.rename` left every test in this file
    // green: the library's own rename was called by NOTHING. `editGroup`
    // and `setGroupCollapsed` were both pinned, and the preset-level verb
    // beside them was not.
    test('renames the one asked for and leaves the rest alone', () async {
      final library = await seeded();
      addTearDown(library.dispose);
      final before = library.presets.map((p) => p.name).toList();

      library.rename(const BrushPresetId('i2'), 'Fine liner');

      final byId = {for (final p in library.presets) p.id.value: p.name};
      expect(byId['i2'], 'Fine liner');
      expect(
        library.presets.where((p) => p.name == 'Fine liner').length,
        1,
        reason: 'the name lands on ONE preset — a walk that renamed the '
            'complement would also put the name in the list',
      );
      expect(
        [
          for (final p in library.presets)
            if (p.id.value != 'i2') p.name,
        ],
        [
          for (var i = 0; i < before.length; i += 1)
            if (library.presets[i].id.value != 'i2') before[i],
        ],
        reason: 'every other preset keeps the name it had',
      );
    });

    test('an id no preset carries changes nothing', () async {
      final library = await seeded();
      addTearDown(library.dispose);
      final before = library.presets.map((p) => p.name).toList();

      library.rename(const BrushPresetId('not-here'), 'Fine liner');

      expect(library.presets.map((p) => p.name), before);
    });
  });

  group('what an edit writes', () {
    // 🚨A MUTANT SURVIVED HERE (2026-09-30): the library could stop writing
    // altogether and every test in this file stayed green, once the pins
    // that watched its writes moved to the writer's own test with the
    // order law (`a_settings_file_holds_the_last_save_test`).
    test('the file is handed the library as it stands', () async {
      final library = await seeded();
      addTearDown(library.dispose);
      final written = <String>[];
      debugSettingsFileWrite = (_, text) async => written.add(text);
      addTearDown(() => debugSettingsFileWrite = null);

      library.rename(const BrushPresetId('i2'), 'Fine liner');

      final presets = (jsonDecode(written.single) as Map)['presets'] as List;
      expect(
        [for (final preset in presets) (preset as Map)['name']],
        ['i1', 'Fine liner', 'p1', 'loose'],
      );
    });
  });

  group('tips carried on presets', () {
    late Directory tipDirectory;
    late BrushTipLibraryService tipService;

    setUp(() async {
      tipDirectory = await Directory.systemTemp.createTemp('preset_tips');
      tipService = BrushTipLibraryService(directoryPath: tipDirectory.path);
    });

    tearDown(() => deleteTempQuietly(tipDirectory));

    test('a preset carrying its tip INLINE hands it to the tip library', () async {
      // ⚠️This used to stage a version-4 file and call itself "the migration
      // that matters". Migration is gone (유저 2026-09-09), and an old file is
      // replaced by the defaults now — so the case had stopped being about
      // adoption and started being about a loader that no longer runs.
      //
      // The LIVE case is the same shape and still real: an IMPORT builds a
      // preset with the mask inline, `brushTipMasksIn` finds it, and the tip
      // library adopts it — or the next save writes an id pointing at nothing.
      final tip = BrushTipMask(
        id: 'sut-abc-tip',
        size: 4,
        alpha: Uint8List.fromList(List<int>.filled(16, 210)),
      );
      final imported = BrushPreset(
        id: const BrushPresetId('p1'),
        name: 'Wet wash',
        settings: BrushSettings(size: 9, tips: [tip]),
      );
      await File(service.filePath).parent.create(recursive: true);
      await File(service.filePath).writeAsString(
        jsonEncode({
          'version': BrushPresetFileService.libraryVersion,
          'groups': const <Object>[],
          'presets': [imported.toJson()],
        }),
      );

      final tipLibrary = BrushTipLibrary(service: tipService);
      addTearDown(tipLibrary.dispose);
      await tipLibrary.load();
      final presetLibrary = BrushPresetLibrary(
        fileService: service,
        tipLibrary: tipLibrary,
      );
      addTearDown(presetLibrary.dispose);

      await presetLibrary.load();

      // Adopted: it is a library tip now, with a file of its own, named
      // after the brush that brought it.
      expect(tipLibrary.maskFor('sut-abc-tip'), tip);
      expect(
        tipLibrary.tips.firstWhere((entry) => entry.id == 'sut-abc-tip').name,
        'Wet wash',
      );
      expect(File(tipService.imagePathFor('sut-abc-tip')).existsSync(), isTrue);

      // And the round trip closes: saving now writes an id, and a fresh
      // load resolves it back to the same mask.
      await service.save((
        groups: presetLibrary.groups,
        presets: presetLibrary.presets,
      ));
      final reloaded = await service.loadOrDefaults(
        resolveTip: tipLibrary.maskFor,
      );
      final restored = reloaded.presets.firstWhere(
        (preset) => preset.id == const BrushPresetId('p1'),
      );
      expect(restored.settings.tipMask, tip);
    });

    test('adoption is idempotent — a second load adds nothing', () async {
      final tip = BrushTipMask(
        id: 'sut-abc-tip',
        size: 4,
        alpha: Uint8List.fromList(List<int>.filled(16, 210)),
      );
      await service.save((
        groups: const [],
        presets: [
          BrushPreset(
            id: const BrushPresetId('p1'),
            name: 'Wet wash',
            settings: BrushSettings(size: 9, tips: [tip]),
          ),
        ],
      ));
      final tipLibrary = BrushTipLibrary(service: tipService);
      addTearDown(tipLibrary.dispose);
      await tipLibrary.register(tip, name: 'Wet wash');
      final before = tipLibrary.tips.length;

      final presetLibrary = BrushPresetLibrary(
        fileService: service,
        tipLibrary: tipLibrary,
      );
      addTearDown(presetLibrary.dispose);
      await presetLibrary.load();

      expect(tipLibrary.tips.length, before);
    });
  });

  group('mergeImportedBrushPresets', () {
    test('puts the import in a group named after the file', () {
      final merged = mergeImportedBrushPresets(
        library: (groups: const [], presets: [_preset('mine')]),
        imported: [_preset('abr-1'), _preset('abr-2')],
        sourceName: 'Noah',
      ).library;

      expect(merged.groups.single.name, 'Noah');
      expect(merged.groups.single.id, importedBrushGroupId('Noah'));
      expect(merged.presets.map((p) => p.id.value), ['mine', 'abr-1', 'abr-2']);
      expect(merged.presets.last.groupId, importedBrushGroupId('Noah'));
      // The user's own preset is untouched at root.
      expect(merged.presets.first.groupId, isNull);
    });

    test('🚨importing a file again keeps what its group holds, and lands the '
        'new copies beside it (F-433)', () {
      final first = mergeImportedBrushPresets(
        library: (groups: const [], presets: const []),
        imported: [_preset('abr-1'), _preset('abr-gone')],
        sourceName: 'Noah',
      ).library;

      final second = mergeImportedBrushPresets(
        library: first,
        imported: [_preset('abr-1'), _preset('abr-new')],
        sourceName: 'Noah',
      ).library;

      // A brush the file no longer defines stays — an import only adds —
      // and the group is not duplicated.
      expect(second.groups.length, 1);
      expect(second.presets.map((p) => p.id.value), [
        'abr-1',
        'abr-gone',
        'abr-1-2',
        'abr-new',
      ]);
      expect(
        second.presets.map((p) => p.groupId).toSet(),
        {importedBrushGroupId('Noah')},
      );
    });

    test('keeps the name and fold state the user gave the group', () {
      final library = mergeImportedBrushPresets(
        library: (groups: const [], presets: const []),
        imported: [_preset('abr-1')],
        sourceName: 'Noah',
      ).library;
      final renamed = (
        groups: [library.groups.single.copyWith(name: 'Mine', collapsed: true)],
        presets: library.presets,
      );

      final merged = mergeImportedBrushPresets(
        library: renamed,
        imported: [_preset('abr-1')],
        sourceName: 'Noah',
      ).library;

      expect(merged.groups.single.name, 'Mine');
      expect(merged.groups.single.collapsed, isTrue);
    });

    test('🚨an id the library already holds is minted afresh — the brush '
        'already there stays as and where it was (F-433)', () {
      // 유저: 「기존 같은 이름? 브러시인지 다른 브러시인지 삭제되는데, 그러지
      // 않도록」 — their sharp, exported from the edited built-in, carried
      // the built-in's id and took the built-in out on the way in.
      final builtIn = BrushPreset(
        id: const BrushPresetId('builtin-mechanical-pencil'),
        name: 'Mechanical Pencil',
        groupId: _ink,
        settings: BrushSettings(size: 3),
      );
      final edited = BrushPreset(
        id: const BrushPresetId('builtin-mechanical-pencil'),
        name: 'Mechanical Pencil',
        settings: BrushSettings(size: 2),
      );

      final landing = mergeImportedBrushPresets(
        library: (
          groups: const [BrushGroup(id: _ink, name: 'Ink')],
          presets: [builtIn],
        ),
        imported: [edited],
        sourceName: 'Sharp',
      );

      final presets = landing.library.presets;
      expect(presets, hasLength(2));
      expect(identical(presets.first, builtIn), isTrue);
      expect(presets.last.id.value, 'builtin-mechanical-pencil-2');
      expect(presets.last.name, 'Mechanical Pencil', reason: 'same name, both');
      expect(presets.last.settings.size, 2);
      expect(presets.last.groupId, importedBrushGroupId('Sharp'));
      expect(landing.landedAs, {
        'builtin-mechanical-pencil': presets.last.id,
      });
    });

    test('a file that gives two brushes one id lands both, and says the '
        'first is the one its id names', () {
      final landing = mergeImportedBrushPresets(
        library: (groups: const [], presets: const []),
        imported: [_preset('twin'), _preset('twin')],
        sourceName: 'Noah',
      );

      expect(landing.library.presets.map((p) => p.id.value), [
        'twin',
        'twin-2',
      ]);
      expect(landing.landedAs, {'twin': const BrushPresetId('twin')});
    });
  });

  group('brush export', _exportRoundTripTests);
}

/// 🚨유저 (`brush-export-format-Q1` 답 1 + `H25-Q1` 답 both-by-selection):
/// export a brush or the group it sits in, in our own format, losing nothing
/// — 「불투명도든 뭐든 손설정이든 정한거 싹 다 내보낼때 나르도록 하고싶음」.
void _exportRoundTripTests() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('brush_export_test');
  });

  tearDown(() => deleteTempQuietly(tempDirectory));

  BrushPresetLibrary libraryOf({
    required BrushPresetFileService service,
    Map<String, BrushHandSettings>? bank,
    PickedFile? picked,
  }) {
    final held = bank ?? <String, BrushHandSettings>{};
    return BrushPresetLibrary(
      fileService: service,
      filePicker: picked == null ? () async => null : () async => picked,
      handSettingsPort: (
        read: () => held,
        write: held.addAll,
      ),
    );
  }

  test('🚨a brush exported and imported back keeps its settings AND what the '
      'hand had set on it', () async {
    final service = BrushPresetFileService(
      filePath: '${tempDirectory.path}/library.json',
    );
    final bank = <String, BrushHandSettings>{};
    final source = libraryOf(service: service, bank: bank);
    addTearDown(source.dispose);
    source.saveCurrent(BrushSettings(size: 7, hardness: 0.3));
    final saved = source.presets.single;
    // The bank is keyed by the id the library minted, so key onto it.
    bank[saved.id.value] = {'size': 40.0, 'opacity': 0.25};

    final path = '${tempDirectory.path}/one.anibrush';
    final message = await source.exportPresets(
      [saved],
      hand: (_, write) async => await write(path) ? path : null,
    );

    expect(message, contains('Exported'));
    expect(await File(path).exists(), isTrue);

    // A FRESH library, with its own empty bank, reads the file back.
    final freshService = BrushPresetFileService(
      filePath: '${tempDirectory.path}/other.json',
    );
    final landed = <String, BrushHandSettings>{};
    final receiver = libraryOf(
      service: freshService,
      bank: landed,
      picked: (
        name: 'one.anibrush',
        bytes: await File(path).readAsBytes(),
      ),
    );
    addTearDown(receiver.dispose);
    await receiver.load();

    expect(await receiver.importFromFile(), contains('Imported'));
    final arrived = receiver.presets.firstWhere(
      (preset) => preset.name == saved.name,
    );
    expect(arrived.settings.size, 7);
    expect(arrived.settings.hardness, 0.3);
    expect(
      landed[arrived.id.value]?['size'],
      40.0,
      reason: 'the hand settings followed the brush onto its NEW id',
    );
    expect(landed[arrived.id.value]?['opacity'], 0.25);
  });

  test('⛔a hand entry naming a brush the file does not carry is DROPPED',
      () async {
    // Otherwise it sits in the bank waiting for whatever preset takes that
    // id next, and hands that brush a size its owner never set.
    final service = BrushPresetFileService(
      filePath: '${tempDirectory.path}/library.json',
    );
    final stowaway = encodeBrushPack(
      BrushPack(
        presets: [
          BrushPreset(
            id: const BrushPresetId('real'),
            name: 'Real',
            settings: BrushSettings(size: 9),
          ),
        ],
        handSettings: const {
          'ghost': {'size': 99.0},
        },
      ),
    );
    final landed = <String, BrushHandSettings>{};
    final receiver = libraryOf(
      service: service,
      bank: landed,
      picked: (
        name: 'pack.anibrush',
        bytes: Uint8List.fromList(utf8.encode(stowaway)),
      ),
    );
    addTearDown(receiver.dispose);
    await receiver.load();

    expect(await receiver.importFromFile(), contains('Imported'));
    expect(landed.containsKey('real'), isFalse, reason: 'it set none');
    expect(
      landed.containsKey('ghost'),
      isFalse,
      reason: 'and the entry for a brush that never arrived is gone',
    );
  });

  test('🚨a pack of an edited built-in lands BESIDE the built-in, and its '
      'hand settings follow it to the id it was given (F-433)', () async {
    // The user's sharp: exported from the built-in they had edited, so it
    // carries the built-in's id. It used to replace the built-in.
    final service = BrushPresetFileService(
      filePath: '${tempDirectory.path}/library.json',
    );
    final pack = encodeBrushPack(
      BrushPack(
        presets: [
          BrushPreset(
            id: const BrushPresetId('builtin-mechanical-pencil'),
            name: 'Sharp',
            settings: BrushSettings(size: 2, hardness: 0.9),
          ),
        ],
        handSettings: const {
          'builtin-mechanical-pencil': {'size': 33.0},
        },
      ),
    );
    final bank = <String, BrushHandSettings>{
      'builtin-mechanical-pencil': {'size': 5.0},
    };
    final receiver = libraryOf(
      service: service,
      bank: bank,
      picked: (
        name: 'Sharp.anibrush',
        bytes: Uint8List.fromList(utf8.encode(pack)),
      ),
    );
    addTearDown(receiver.dispose);
    await receiver.load();
    final builtIn = receiver.presets.firstWhere(
      (preset) => preset.id.value == 'builtin-mechanical-pencil',
    );
    final before = receiver.presets.length;

    expect(await receiver.importFromFile(), contains('Imported'));

    expect(receiver.presets, hasLength(before + 1));
    expect(
      receiver.presets.where((p) => p.id == builtIn.id).single,
      same(builtIn),
      reason: 'the built-in is still there, untouched',
    );
    final arrived = receiver.presets.last;
    expect(arrived.id.value, 'builtin-mechanical-pencil-2');
    expect(arrived.name, 'Sharp');
    expect(arrived.settings.size, 2);
    expect(bank[arrived.id.value]?['size'], 33.0);
    expect(
      bank['builtin-mechanical-pencil']?['size'],
      5.0,
      reason: 'the built-in keeps what the hand had set on it',
    );
  });

  test('⛔a file that is not ours is refused with a sentence, not a crash',
      () async {
    final service = BrushPresetFileService(
      filePath: '${tempDirectory.path}/library.json',
    );
    final receiver = libraryOf(
      service: service,
      picked: (
        name: 'broken.anibrush',
        bytes: Uint8List.fromList('not a pack'.codeUnits),
      ),
    );
    addTearDown(receiver.dispose);
    await receiver.load();

    final before = receiver.presets.length;
    final message = await receiver.importFromFile();
    expect(message, isNotNull);
    expect(message, contains('Anicel brush'));
    expect(receiver.presets.length, before, reason: 'nothing was merged');
  });

  test('exporting an empty selection writes nothing and says nothing', () async {
    final service = BrushPresetFileService(
      filePath: '${tempDirectory.path}/library.json',
    );
    final library = libraryOf(service: service);
    addTearDown(library.dispose);

    var picked = false;
    expect(
      await library.exportPresets(
        const [],
        hand: (_, _) async {
          picked = true;
          return null;
        },
      ),
      isNull,
    );
    expect(picked, isFalse);
  });

  group('🚨the export hands its file to the door — it asks for no path '
      'itself (brush-export-has-no-road-where-no-save-window-answers-a-path)',
      () {
    BrushPresetLibrary exporting() {
      final library = libraryOf(
        service: BrushPresetFileService(
          filePath: '${tempDirectory.path}/library.json',
        ),
      );
      addTearDown(library.dispose);
      library.saveCurrent(BrushSettings(size: 7));
      return library;
    }

    test('🎯where no save window answers with a path, the door writes in '
        'the app first and places it — the brush arrives whole', () async {
      final library = exporting();
      final staged = '${tempDirectory.path}/staged.anibrush';
      final placed = '${tempDirectory.path}/placed.anibrush';
      String? named;

      final message = await library.exportPresets(
        library.presets,
        hand: (name, write) async {
          named = name;
          if (!await write(staged)) return null;
          File(staged).renameSync(placed);
          return placed;
        },
      );

      expect(named, '${library.presets.single.name}.anibrush');
      expect(message, contains('Exported'));
      expect(
        decodeBrushPack(File(placed).readAsStringSync()).presets.single.name,
        library.presets.single.name,
      );
    });

    test('a person who backs out is told nothing', () async {
      final library = exporting();

      expect(
        await library.exportPresets(
          library.presets,
          hand: (_, _) async => null,
        ),
        isNull,
      );
    });

    test('a write that fails says so, why included', () async {
      final library = exporting();

      final message = await library.exportPresets(
        library.presets,
        hand: (_, write) async =>
            await write('${tempDirectory.path}/no/such/folder/a.anibrush')
            ? 'landed'
            : null,
      );

      expect(message, startsWith('Could not write the brush file: '));
    });

    test('a door that fails says so', () async {
      final library = exporting();

      final message = await library.exportPresets(
        library.presets,
        hand: (_, _) async => throw StateError('no window'),
      );

      expect(message, 'Could not choose where to save: Bad state: no window');
    });

    test('it says so in the program language — the write that fails and '
        'the one that lands', () async {
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      final ko = AppStrings.of(AppLanguage.ko);
      final library = exporting();

      final failed = await library.exportPresets(
        library.presets,
        hand: (_, write) async =>
            await write('${tempDirectory.path}/no/such/folder/a.anibrush')
            ? 'landed'
            : null,
      );
      final landed = await library.exportPresets(
        library.presets,
        hand: (name, write) async {
          final path = '${tempDirectory.path}/$name';
          return await write(path) ? path : null;
        },
      );

      expect(failed, startsWith(ko.brExportNotWritten('')));
      expect(landed, ko.brExportedOne(library.presets.single.name));
      expect(
        await library.exportPresets(
          library.presets,
          hand: (_, _) async => throw StateError('no window'),
        ),
        ko.brExportPlaceUnchosen('Bad state: no window'),
      );

      // Brushes of no one group are named in the program language too —
      // loose ones, and ones whose group this library does not hold.
      String? named;
      String? placed;
      Future<String?> export(List<BrushPreset> presets) =>
          library.exportPresets(
            presets,
            hand: (name, write) async {
              named = name;
              final path = '${tempDirectory.path}/$name';
              if (!await write(path)) return null;
              return placed = path;
            },
          );
      library.saveCurrent(BrushSettings(size: 9));
      expect(await export(library.presets), ko.brExportedMany(2));
      expect(named, '${ko.brExportFallbackName}.anibrush');
      final loose = (name: named!, bytes: File(placed!).readAsBytesSync());
      named = null;
      await export([
        _preset('a', groupId: _ink),
        _preset('b', groupId: _ink),
      ]);
      expect(named, '${ko.brExportFallbackName}.anibrush');

      // And what comes back in says so in it.
      final receiver = libraryOf(
        service: BrushPresetFileService(
          filePath: '${tempDirectory.path}/receiver.json',
        ),
        picked: loose,
      );
      addTearDown(receiver.dispose);
      expect(await receiver.importFromFile(), ko.brImported(2, loose.name));
    });
  });
}
