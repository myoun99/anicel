import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/brush_group.dart';
import 'package:quick_animaker_v2/src/models/brush_group_icon.dart';
import 'package:quick_animaker_v2/src/models/brush_group_id.dart';
import 'package:quick_animaker_v2/src/models/brush_preset.dart';
import 'package:quick_animaker_v2/src/models/brush_preset_id.dart';
import 'package:quick_animaker_v2/src/models/brush_settings.dart';
import 'package:quick_animaker_v2/src/models/brush_tip_mask.dart';
import 'package:quick_animaker_v2/src/services/brush_tip_library_service.dart';
import 'package:quick_animaker_v2/src/ui/brush/brush_tip_library.dart';
import 'package:quick_animaker_v2/src/services/brush_preset_defaults.dart';
import 'package:quick_animaker_v2/src/services/brush_preset_file_service.dart';
import 'package:quick_animaker_v2/src/ui/brush/brush_import_merge.dart';
import 'package:quick_animaker_v2/src/ui/brush/brush_preset_library.dart';

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

  tearDown(() async {
    // Every verb persists fire-and-forget, so a write may still hold the
    // file when the test ends — Windows refuses the delete until it lands.
    for (var attempt = 0; ; attempt += 1) {
      try {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
        return;
      } on FileSystemException {
        if (attempt >= 20) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });

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

    test('deleting the active preset\'s group clears the highlight', () async {
      final library = await seeded();
      addTearDown(library.dispose);
      library.markActive(const BrushPresetId('i1'));

      library.deleteGroup(_ink);

      expect(library.activePresetId, isNull);
    });

    test('deleting another group keeps the highlight', () async {
      final library = await seeded();
      addTearDown(library.dispose);
      library.markActive(const BrushPresetId('i1'));

      library.deleteGroup(_paint);

      expect(library.activePresetId, const BrushPresetId('i1'));
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

    test('reorderGroups replaces the display order', () async {
      final library = await seeded();
      addTearDown(library.dispose);

      library.reorderGroups(library.groups.reversed.toList());

      expect(library.groups.map((group) => group.name), ['Paint', 'Ink']);
    });

    test('resetToDefaults restores the built-ins', () async {
      final library = await seeded();
      addTearDown(library.dispose);
      library.markActive(const BrushPresetId('i1'));

      library.resetToDefaults();

      expect(library.presets, defaultBrushPresets);
      expect(library.groups, defaultBrushGroups);
      expect(library.activePresetId, isNull);
    });
  });

  group('saveCurrent', () {
    test('lands in the given group', () async {
      final library = await seeded();
      addTearDown(library.dispose);

      library.saveCurrent(BrushSettings(size: 9), groupId: _paint);

      expect(library.presets.last.groupId, _paint);
      expect(library.activePresetId, library.presets.last.id);
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

  group('tips carried on presets', () {
    late Directory tipDirectory;
    late BrushTipLibraryService tipService;

    setUp(() async {
      tipDirectory = await Directory.systemTemp.createTemp('preset_tips');
      tipService = BrushTipLibraryService(directoryPath: tipDirectory.path);
    });

    tearDown(() async {
      for (var attempt = 0; ; attempt += 1) {
        try {
          if (await tipDirectory.exists()) {
            await tipDirectory.delete(recursive: true);
          }
          return;
        } on FileSystemException {
          if (attempt >= 20) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
    });

    test('an old library hands its inline tips to the tip library', () async {
      // The migration that matters: a preset written before tips had a home
      // still carries the image, and the next save will write only an id —
      // so the image has to be adopted or it is lost.
      final tip = BrushTipMask(
        id: 'sut-abc-tip',
        size: 4,
        alpha: Uint8List.fromList(List<int>.filled(16, 210)),
      );
      final legacy = BrushPreset(
        id: const BrushPresetId('p1'),
        name: 'Wet wash',
        settings: BrushSettings(size: 9, tipMask: tip),
      );
      await File(service.filePath).parent.create(recursive: true);
      await File(service.filePath).writeAsString(
        jsonEncode({
          'version': 4,
          'groups': const <Object>[],
          'presets': [legacy.toJson()],
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
            settings: BrushSettings(size: 9, tipMask: tip),
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
      );

      expect(merged.groups.single.name, 'Noah');
      expect(merged.groups.single.id, importedBrushGroupId('Noah'));
      expect(merged.presets.map((p) => p.id.value), ['mine', 'abr-1', 'abr-2']);
      expect(merged.presets.last.groupId, importedBrushGroupId('Noah'));
      // The user's own preset is untouched at root.
      expect(merged.presets.first.groupId, isNull);
    });

    test('re-importing REPLACES the group contents', () {
      final first = mergeImportedBrushPresets(
        library: (groups: const [], presets: const []),
        imported: [_preset('abr-1'), _preset('abr-gone')],
        sourceName: 'Noah',
      );

      final second = mergeImportedBrushPresets(
        library: first,
        imported: [_preset('abr-1'), _preset('abr-new')],
        sourceName: 'Noah',
      );

      // A brush the file no longer defines does not linger, and the group is
      // not duplicated.
      expect(second.groups.length, 1);
      expect(second.presets.map((p) => p.id.value), ['abr-1', 'abr-new']);
    });

    test('keeps the name and fold state the user gave the group', () {
      final library = mergeImportedBrushPresets(
        library: (groups: const [], presets: const []),
        imported: [_preset('abr-1')],
        sourceName: 'Noah',
      );
      final renamed = (
        groups: [library.groups.single.copyWith(name: 'Mine', collapsed: true)],
        presets: library.presets,
      );

      final merged = mergeImportedBrushPresets(
        library: renamed,
        imported: [_preset('abr-1')],
        sourceName: 'Noah',
      );

      expect(merged.groups.single.name, 'Mine');
      expect(merged.groups.single.collapsed, isTrue);
    });

    test('a member dragged out is replaced, never duplicated', () {
      // Ids key the rows: the same id may not appear twice, so a brush the
      // user moved elsewhere still loses to the incoming copy.
      final library = (
        groups: [BrushGroup(id: importedBrushGroupId('Noah'), name: 'Noah')],
        presets: [_preset('abr-1', groupId: _ink)],
      );

      final merged = mergeImportedBrushPresets(
        library: library,
        imported: [_preset('abr-1')],
        sourceName: 'Noah',
      );

      expect(merged.presets.length, 1);
      expect(merged.presets.single.groupId, importedBrushGroupId('Noah'));
    });
  });
}
