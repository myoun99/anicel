import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_group.dart';
import 'package:anicel/src/models/brush_group_id.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_defaults.dart';
import '../helpers/temp_dir.dart';

/// What the tip library answers for the generated tips — production always
/// has those loaded, so a test that saves a built-in preset needs them too.
BrushTipMask? resolveBuiltInTip(String id) {
  for (final entry in defaultBrushTipEntries) {
    if (entry.id == id) {
      return entry.mask;
    }
  }
  return null;
}

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'brush_preset_file_service_test',
    );
  });

  tearDown(() => deleteTempQuietly(tempDirectory));

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

    test('save makes the folder it writes into, and stamps the version', () async {
      final path = pathIn('made/up/deep/presets.json');
      final service = BrushPresetFileService(filePath: path);

      await service.save((groups: const [], presets: const []));

      final written =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      expect(written.keys.first, 'version');
      expect(written['version'], BrushPresetFileService.libraryVersion);
      expect(written['groups'], isEmpty);
      expect(written['presets'], isEmpty);
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

    test('⛔a library from ANY other version is REPLACED, not migrated', () {
      // 유저 2026-09-09: 「기존 프리셋 그냥 마이그레이션 관련 코드 깔끔하게
      // 없애도되. 필요없어. 아무도 작업안했고」. Five versions of
      // carry-forward went with it, so a bump now resets — which is what
      // makes a roster change reach the person running the app.
      // 🔜The release that reaches someone who has drawn with their own
      // brushes must put carry-forward back BEFORE it bumps the version.
      Future<void> replaced(int version) async {
        final path = pathIn('v$version.json');
        await File(path).writeAsString(
          jsonEncode({
            'version': version,
            'groups': <dynamic>[],
            'presets': [
              BrushPreset(
                id: const BrushPresetId('user-1'),
                name: 'Mine',
                settings: BrushSettings(size: 3),
              ).toJson(),
            ],
          }),
        );

        final loaded = await BrushPresetFileService(
          filePath: path,
        ).loadOrDefaults();

        expect(loaded.presets, defaultBrushPresets, reason: 'version $version');
        expect(loaded.groups, defaultBrushGroups, reason: 'version $version');
      }

      // Older, newer, and absent alike: only an exact match is carried.
      return Future.wait([
        replaced(1),
        replaced(BrushPresetFileService.libraryVersion - 1),
        replaced(BrushPresetFileService.libraryVersion + 1),
      ]);
    });

    test('a file with no version at all is replaced too', () async {
      final path = pathIn('no_version.json');
      await File(path).writeAsString(
        jsonEncode({'groups': <dynamic>[], 'presets': <dynamic>[]}),
      );

      final loaded = await BrushPresetFileService(
        filePath: path,
      ).loadOrDefaults();

      // ⚠️NOT an empty library. An empty save is a valid user choice only at
      // the CURRENT version, where `version` says the file meant it.
      expect(loaded.presets, defaultBrushPresets);
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

        final loaded = await service.loadOrDefaults(
          resolveTip: resolveBuiltInTip,
        );

        expect(loaded.presets, [defaultBrushPresets.last]);
        expect(loaded.groups, defaultBrushGroups);
      },
    );

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

    test('default path points into the per-user app-data directory, in the '
        'settings room', () {
      final path = BrushPresetFileService.defaultBrushPresetFilePath();
      expect(path, endsWith('anicel/Settings/brush_presets.json'));
    });
  });

  group('tip references', () {
    BrushTipMask mask(String id) => BrushTipMask(
      id: id,
      size: 4,
      alpha: Uint8List.fromList(List<int>.filled(16, 180)),
    );

    BrushPreset sampled({String id = 'p1'}) => BrushPreset(
      id: BrushPresetId(id),
      name: 'Sampled',
      settings: BrushSettings(
        size: 12,
        tipMask: mask('tip-a'),
        dualMask: mask('tip-b'),
        textureMaskSource: mask('tip-c'),
      ),
    );

    test('the file stores ids, not the images', () async {
      final path = pathIn('v5.json');
      final service = BrushPresetFileService(filePath: path);

      await service.save((groups: const [], presets: [sampled()]));

      final written =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final settings =
          ((written['presets'] as List<dynamic>).single
              as Map<String, dynamic>)['settings'];
      expect(settings, isA<Map<String, dynamic>>());
      final map = settings as Map<String, dynamic>;
      expect(map['tipMaskId'], 'tip-a');
      expect(map['dualMaskId'], 'tip-b');
      expect(map['textureMaskSourceId'], 'tip-c');
      // The point of the exercise: the bytes are gone from the preset.
      expect(map.containsKey('tipMask'), isFalse);
      expect(map.containsKey('dualMask'), isFalse);
      expect(map.containsKey('textureMaskSource'), isFalse);
    });

    test('ids resolve back to masks on load', () async {
      final path = pathIn('v5_resolve.json');
      final service = BrushPresetFileService(filePath: path);
      await service.save((groups: const [], presets: [sampled()]));

      final loaded = await service.loadOrDefaults(resolveTip: mask);

      final settings = loaded.presets.single.settings;
      expect(settings.tipMask, mask('tip-a'));
      expect(settings.dualMask, mask('tip-b'));
      expect(settings.textureMask, mask('tip-c'));
    });

    test('an id the library cannot answer degrades to the round tip', () async {
      final path = pathIn('v5_missing.json');
      final service = BrushPresetFileService(filePath: path);
      await service.save((groups: const [], presets: [sampled()]));

      final loaded = await service.loadOrDefaults(resolveTip: (_) => null);

      // The brush loses its texture, not its existence.
      expect(loaded.presets.single.settings.tipMask, isNull);
      expect(loaded.presets.single.settings.size, 12);
    });
  });

  group('brushTipMasksIn', () {
    test('lists each mask once, with the preset that carries it', () {
      final tip = BrushTipMask(
        id: 'shared',
        size: 2,
        alpha: Uint8List.fromList([1, 2, 3, 4]),
      );
      final presets = [
        BrushPreset(
          id: const BrushPresetId('a'),
          name: 'First',
          settings: BrushSettings(size: 4, tipMask: tip),
        ),
        BrushPreset(
          id: const BrushPresetId('b'),
          name: 'Second',
          settings: BrushSettings(size: 4, dualMask: tip),
        ),
      ];

      final found = brushTipMasksIn(presets);

      // One entry even though two presets use it — that de-duplication is
      // the whole reason tips moved out of presets.
      expect(found.length, 1);
      expect(found.single.mask, tip);
      expect(found.single.name, 'First');
    });

    test('finds nothing in parametric presets', () {
      expect(brushTipMasksIn(defaultBrushPresets.take(1)), isEmpty);
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
