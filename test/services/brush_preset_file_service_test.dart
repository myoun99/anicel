import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/brush_group.dart';
import 'package:quick_animaker_v2/src/models/brush_group_id.dart';
import 'package:quick_animaker_v2/src/models/brush_preset.dart';
import 'package:quick_animaker_v2/src/models/brush_preset_id.dart';
import 'package:quick_animaker_v2/src/models/brush_pressure_curve.dart';
import 'package:quick_animaker_v2/src/models/brush_settings.dart';
import 'package:quick_animaker_v2/src/services/brush_preset_defaults.dart';
import 'package:quick_animaker_v2/src/services/brush_preset_file_service.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'brush_preset_file_service_test',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  String pathIn(String fileName) => '${tempDirectory.path}/$fileName';

  group('BrushPresetFileService', () {
    test('missing file yields the built-in defaults', () async {
      final service = BrushPresetFileService(filePath: pathIn('missing.json'));

      final library = await service.loadOrDefaults();

      expect(library.presets, defaultBrushPresets);
      expect(library.groups, defaultBrushGroups);
      // Loading must not create the file; defaults are only persisted when
      // the user actually saves.
      expect(File(pathIn('missing.json')).existsSync(), isFalse);
    });

    test('save then load round-trips groups and members', () async {
      final service = BrushPresetFileService(
        filePath: pathIn('nested/dir/presets.json'),
      );
      final groups = [
        const BrushGroup(id: BrushGroupId('imported-불투명 수채'), name: '불투명 수채'),
        const BrushGroup(
          id: BrushGroupId('user-group-1'),
          name: 'Mine',
          collapsed: true,
        ),
        // The built-in below belongs to one of these, and a preset whose
        // group is missing would be sent back to the root section.
        ...defaultBrushGroups,
      ];
      final presets = [
        BrushPreset(
          id: const BrushPresetId('user-1'),
          name: 'My Pen',
          groupId: const BrushGroupId('imported-불투명 수채'),
          settings: BrushSettings(
            size: 7,
            hardness: 0.9,
            roundness: 0.4,
            angleDegrees: 45,
            sizePressureCurve: BrushPressureCurve.identity(),
          ),
        ),
        defaultBrushPresets.first,
      ];

      await service.save((groups: groups, presets: presets));
      final loaded = await service.loadOrDefaults();

      expect(loaded.presets, presets);
      // Group order and the fold state come back exactly as saved.
      expect(loaded.groups, groups);
    });

    test('an explicitly saved empty library stays empty on load', () async {
      final service = BrushPresetFileService(filePath: pathIn('empty.json'));

      await service.save((groups: const [], presets: const []));
      final loaded = await service.loadOrDefaults();

      expect(loaded.presets, isEmpty);
      expect(loaded.groups, isEmpty);
    });

    test('corrupt file falls back to the built-in defaults', () async {
      final path = pathIn('corrupt.json');
      await File(path).writeAsString('{not json');
      final service = BrushPresetFileService(filePath: path);

      expect((await service.loadOrDefaults()).presets, defaultBrushPresets);
    });

    test('valid json with wrong shape falls back to the defaults', () async {
      final path = pathIn('wrong_shape.json');
      await File(path).writeAsString(jsonEncode({'presets': 'nope'}));
      final service = BrushPresetFileService(filePath: path);

      expect((await service.loadOrDefaults()).presets, defaultBrushPresets);
    });

    test('older library versions gain newly added built-ins on load', () async {
      final path = pathIn('v1.json');
      // A version-1 library saved before the sampled-tip built-ins existed:
      // it holds one user preset and one (kept) old built-in.
      final userPreset = BrushPreset(
        id: const BrushPresetId('user-1'),
        name: 'Mine',
        settings: BrushSettings(size: 3),
      );
      await File(path).writeAsString(
        jsonEncode({
          'version': 1,
          'presets': [userPreset.toJson(), defaultBrushPresets.first.toJson()],
        }),
      );
      final service = BrushPresetFileService(filePath: path);

      final loaded = await service.loadOrDefaults();

      // Existing entries stay first and unduplicated; the built-ins the old
      // file lacks (e.g. Chalk/Splatter) are appended.
      expect(loaded.presets.first, userPreset);
      expect(
        loaded.presets.where((p) => p.id == defaultBrushPresets.first.id),
        [defaultBrushPresets.first],
      );
      final loadedIds = loaded.presets.map((p) => p.id).toSet();
      for (final builtin in defaultBrushPresets) {
        expect(loadedIds, contains(builtin.id));
      }
      // Built-in GROUPS ride the same version gate.
      final loadedGroupIds = loaded.groups.map((g) => g.id).toSet();
      for (final builtin in defaultBrushGroups) {
        expect(loadedGroupIds, contains(builtin.id));
      }
    });

    test(
      'current-version libraries do not resurrect deleted built-ins',
      () async {
        final path = pathIn('v_current.json');
        final service = BrushPresetFileService(filePath: path);
        // Save a library missing most built-ins at the CURRENT version: the
        // user deleted them, so loading must not bring them back.
        await service.save((
          groups: defaultBrushGroups,
          presets: [defaultBrushPresets.last],
        ));

        final loaded = await service.loadOrDefaults();

        expect(loaded.presets, [defaultBrushPresets.last]);
        expect(loaded.groups, defaultBrushGroups);
      },
    );

    test('crossing a version line files built-ins left at the root', () async {
      // A library saved before the built-ins had groups: the ones the user
      // never filed get their shipped home, everything else stays put.
      final path = pathIn('rehome.json');
      final builtin = defaultBrushPresets.first;
      final movedByUser = defaultBrushPresets[1].copyWith(
        groupId: const BrushGroupId('mine'),
      );
      final ownPreset = BrushPreset(
        id: const BrushPresetId('user-1'),
        name: 'Mine',
        settings: BrushSettings(size: 3),
      );
      await File(path).writeAsString(
        jsonEncode({
          'version': BrushPresetFileService.libraryVersion - 1,
          'groups': [
            const BrushGroup(id: BrushGroupId('mine'), name: 'Mine').toJson(),
          ],
          'presets': [
            builtin.copyWith(groupId: null).toJson(),
            movedByUser.toJson(),
            ownPreset.toJson(),
          ],
        }),
      );

      final loaded = await BrushPresetFileService(
        filePath: path,
      ).loadOrDefaults();

      final byId = {for (final preset in loaded.presets) preset.id: preset};
      expect(byId[builtin.id]!.groupId, builtin.groupId);
      // The user's own filing wins over the shipped home.
      expect(byId[movedByUser.id]!.groupId, const BrushGroupId('mine'));
      // A preset that is not a built-in is never re-homed.
      expect(byId[ownPreset.id]!.groupId, isNull);
    });

    test(
      'duplicate preset ids in a saved library are healed on load',
      () async {
        // The pre-fix ABR importer could persist duplicate ids when several
        // brushes shared one tip; duplicate ids crash the preset rows.
        final path = pathIn('duplicates.json');
        final duplicated = BrushPreset(
          id: const BrushPresetId('abr-shared'),
          name: 'Variant A',
          settings: BrushSettings(size: 5),
        );
        await File(path).writeAsString(
          jsonEncode({
            'version': BrushPresetFileService.libraryVersion,
            'groups': const <Object>[],
            'presets': [
              duplicated.toJson(),
              duplicated.copyWith(name: 'Variant B').toJson(),
              duplicated.copyWith(name: 'Variant C').toJson(),
            ],
          }),
        );
        final service = BrushPresetFileService(filePath: path);

        final loaded = await service.loadOrDefaults();

        expect(loaded.presets.map((p) => p.id.value), [
          'abr-shared',
          'abr-shared-2',
          'abr-shared-3',
        ]);
        expect(loaded.presets.map((p) => p.name), [
          'Variant A',
          'Variant B',
          'Variant C',
        ]);
      },
    );

    test('a repeated group id collapses instead of splitting', () async {
      // Suffixing a duplicate GROUP id the way preset ids are healed would
      // orphan every member of the later copy, so the first one wins.
      final path = pathIn('duplicate_groups.json');
      const group = BrushGroup(id: BrushGroupId('ink'), name: 'Ink');
      final member = BrushPreset(
        id: const BrushPresetId('p1'),
        name: 'G-Pen',
        groupId: const BrushGroupId('ink'),
        settings: BrushSettings(size: 5),
      );
      await File(path).writeAsString(
        jsonEncode({
          'version': BrushPresetFileService.libraryVersion,
          'groups': [group.toJson(), group.copyWith(name: 'Ink 2').toJson()],
          'presets': [member.toJson()],
        }),
      );

      final loaded = await BrushPresetFileService(
        filePath: path,
      ).loadOrDefaults();

      expect(loaded.groups, [group]);
      expect(loaded.presets.single.groupId, const BrushGroupId('ink'));
    });

    test('a preset pointing at no existing group falls back to root', () async {
      final path = pathIn('orphan.json');
      final orphan = BrushPreset(
        id: const BrushPresetId('p1'),
        name: 'Lost',
        groupId: const BrushGroupId('deleted-group'),
        settings: BrushSettings(size: 5),
      );
      await File(path).writeAsString(
        jsonEncode({
          'version': BrushPresetFileService.libraryVersion,
          'groups': const <Object>[],
          'presets': [orphan.toJson()],
        }),
      );

      final loaded = await BrushPresetFileService(
        filePath: path,
      ).loadOrDefaults();

      // Nothing is lost — it just shows in the headerless root section.
      expect(loaded.presets.single.groupId, isNull);
      expect(loaded.presets.single.name, 'Lost');
    });

    test('default path points into the per-user app-data directory', () {
      final path = BrushPresetFileService.defaultBrushPresetFilePath();
      expect(path, endsWith('quick_animaker_v2/brush_presets.json'));
    });
  });

  group('version 2 -> 3 migration', () {
    /// A version-2 entry: the group was a NAME repeated on every member.
    Map<String, dynamic> legacyPreset(String id, {String? group}) => {
      'id': {'value': id},
      'name': id,
      'settings': BrushSettings(size: 5).toJson(),
      'group': ?group,
    };

    test('rebuilds group entities in first-appearance order', () async {
      final path = pathIn('v2.json');
      await File(path).writeAsString(
        jsonEncode({
          'version': 2,
          'presets': [
            legacyPreset('loose'),
            legacyPreset('w1', group: '불투명 수채'),
            legacyPreset('n1', group: 'Noah'),
            legacyPreset('w2', group: '불투명 수채'),
          ],
        }),
      );

      final loaded = await BrushPresetFileService(
        filePath: path,
      ).loadOrDefaults();

      // The rebuilt groups come first, in the order their members appeared;
      // crossing the version line also appends the built-in groups.
      expect(loaded.groups.take(2).map((group) => group.name), [
        '불투명 수채',
        'Noah',
      ]);
      expect(
        loaded.groups.map((group) => group.id),
        containsAll(defaultBrushGroups.map((group) => group.id)),
      );
      // The id is the one the importer derives from the file name, so
      // re-importing that same pack still lands in this migrated group.
      expect(loaded.groups.first.id, importedBrushGroupId('불투명 수채'));
      expect(loaded.groups.every((group) => !group.collapsed), isTrue);
    });

    test('members keep their group, ungrouped presets stay at root', () async {
      final path = pathIn('v2_members.json');
      await File(path).writeAsString(
        jsonEncode({
          'version': 2,
          'presets': [
            legacyPreset('loose'),
            legacyPreset('w1', group: '불투명 수채'),
            legacyPreset('w2', group: '불투명 수채'),
          ],
        }),
      );

      final loaded = await BrushPresetFileService(
        filePath: path,
      ).loadOrDefaults();

      final byId = {
        for (final preset in loaded.presets) preset.id.value: preset,
      };
      expect(byId['loose']!.groupId, isNull);
      expect(byId['w1']!.groupId, importedBrushGroupId('불투명 수채'));
      expect(byId['w2']!.groupId, byId['w1']!.groupId);
    });

    test('a migrated library saves back in the new shape', () async {
      final path = pathIn('v2_resave.json');
      await File(path).writeAsString(
        jsonEncode({
          'version': 2,
          'presets': [legacyPreset('w1', group: 'Noah')],
        }),
      );
      final service = BrushPresetFileService(filePath: path);

      final loaded = await service.loadOrDefaults();
      await service.save(loaded);

      final written =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      expect(written['version'], BrushPresetFileService.libraryVersion);
      // Crossing the version line also merges in the built-ins the old file
      // predates, so the migrated preset is looked up rather than assumed
      // to be alone.
      expect(
        (written['groups'] as List<dynamic>).where(
          (group) => (group as Map)['name'] == 'Noah',
        ),
        hasLength(1),
      );
      final preset =
          (written['presets'] as List<dynamic>).firstWhere(
                (preset) => (preset as Map)['name'] == 'w1',
              )
              as Map;
      // The old per-preset name is gone; membership is a reference now.
      expect(preset.containsKey('group'), isFalse);
      expect(preset['groupId'], {'value': importedBrushGroupId('Noah').value});
    });
  });

  group('defaultBrushPresets', () {
    test('are non-empty with unique ids and names', () {
      expect(defaultBrushPresets, isNotEmpty);
      final ids = defaultBrushPresets.map((preset) => preset.id).toSet();
      final names = defaultBrushPresets.map((preset) => preset.name).toSet();
      expect(ids.length, defaultBrushPresets.length);
      expect(names.length, defaultBrushPresets.length);
    });

    test('every default round-trips through json', () {
      for (final preset in defaultBrushPresets) {
        expect(BrushPreset.fromJson(preset.toJson()), preset);
      }
    });

    test('include sampled-tip presets carrying their masks', () {
      final chalk = defaultBrushPresets.firstWhere(
        (preset) => preset.name == 'Chalk',
      );
      final splatter = defaultBrushPresets.firstWhere(
        (preset) => preset.name == 'Splatter',
      );
      expect(chalk.settings.tipMask, isNotNull);
      expect(chalk.settings.tipMask!.id, 'builtin-chalk');
      expect(splatter.settings.tipMask, isNotNull);
      expect(splatter.settings.tipMask!.id, 'builtin-splatter');
    });
  });

  group('defaultBrushGroups', () {
    test('have unique ids', () {
      final ids = defaultBrushGroups.map((group) => group.id).toSet();
      expect(ids.length, defaultBrushGroups.length);
    });

    test('every built-in preset points at a group that exists', () {
      final ids = {for (final group in defaultBrushGroups) group.id};
      for (final preset in defaultBrushPresets) {
        if (preset.groupId != null) {
          expect(
            ids,
            contains(preset.groupId),
            reason: '${preset.name} references a missing group',
          );
        }
      }
    });
  });
}
