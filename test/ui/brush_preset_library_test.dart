import 'dart:async';
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
import 'package:anicel/src/ui/brush/brush_import_merge.dart';
import 'package:anicel/src/ui/brush/brush_preset_library.dart';

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
        settings: BrushSettings(size: 9, tipMask: tip),
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

  group('brush export', _exportRoundTripTests);

  group('🚨the library writes ONE AT A TIME, in call order', () {
    test('a second edit does not start a second write', () async {
      // Eleven mutators persist, and they used to fire each save unawaited
      // with nothing serializing them. Two edits a frame apart raced, and
      // "last write wins" meant last to FINISH, not last called — a rename
      // could land after the delete that followed it and bring the preset
      // back on the next load.
      final writer = _RecordingFileService(
        '${tempDirectory.path}/serialized.json',
      );
      final library = BrushPresetLibrary(fileService: writer);

      library.saveCurrent(BrushSettings(size: 5));
      library.saveCurrent(BrushSettings(size: 6));
      library.saveCurrent(BrushSettings(size: 7));

      expect(
        writer.maximumOverlap,
        1,
        reason: 'two saves must never be in flight together',
      );

      await writer.settle();

      // ...and the newest state is what the file ends up holding.
      expect(writer.applied.last, library.presets.length);
      library.dispose();
    });

    test('the states BETWEEN two edits may be skipped, the last may not', () async {
      final writer = _RecordingFileService(
        '${tempDirectory.path}/coalesced.json',
      );
      final library = BrushPresetLibrary(fileService: writer);

      for (var i = 0; i < 6; i += 1) {
        library.saveCurrent(BrushSettings(size: 5));
      }
      await writer.settle();

      expect(
        writer.applied.length,
        lessThan(6),
        reason: 'the in-between states of a burst are not worth a write each',
      );
      expect(writer.applied.last, 6);
      library.dispose();
    });
  });
}

/// A file service that records what it was asked to write and how many
/// writes were in flight at once.
///
/// ⛔NO TIMER FINISHES A WRITE HERE — the TEST does, one at a time. A fake
/// that landed its completion on a `Future.delayed` would be betting on how
/// busy the machine is, which is the race
/// `tests_do_not_race_the_code_test` exists to refuse.
class _RecordingFileService extends BrushPresetFileService {
  _RecordingFileService(String path) : super(filePath: path);

  /// Preset counts, in the order the library ASKED for them.
  final List<int> applied = [];

  final List<Completer<void>> _open = [];

  /// The most writes this service was ever holding at once.
  int maximumOverlap = 0;

  @override
  Future<void> save(BrushPresetLibraryData library) {
    applied.add(library.presets.length);
    final completer = Completer<void>();
    _open.add(completer);
    if (_open.length > maximumOverlap) {
      maximumOverlap = _open.length;
    }
    return completer.future;
  }

  /// Finishes the write the library is waiting on and gives it the turn it
  /// needs to queue whatever is next. False means nothing was in flight —
  /// positive evidence that the queue is empty, not an observed silence.
  Future<bool> _finishOne() async {
    if (_open.isEmpty) {
      return false;
    }
    _open.removeAt(0).complete();
    await Future<void>.delayed(Duration.zero);
    return true;
  }

  /// Runs the queue to exhaustion, one write per turn.
  Future<void> settle() async {
    while (await _finishOne()) {}
  }
}

/// 🚨유저 (`brush-export-format-Q1` 답 1 + `H25-Q1` 답 both-by-selection):
/// export a brush or the group it sits in, in our own format, losing nothing
/// — 「불투명도든 뭐든 손설정이든 정한거 싹 다 내보낼때 나르도록 하고싶음」.
void _exportRoundTripTests() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('brush_export_test');
  });

  tearDown(() async {
    // Same retry as the suite's own tearDown: a fire-and-forget persist may
    // still hold the file, and Windows refuses the delete until it lands.
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
    bank[saved.id.value] = (size: 40.0, opacity: 0.25, blendMode: null);

    final path = '${tempDirectory.path}/one.anibrush';
    final message = await source.exportPresets(
      [saved],
      pickDestination: (_) async => path,
      write: (destination, contents) =>
          File(destination).writeAsString(contents),
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
      landed[arrived.id.value]?.size,
      40.0,
      reason: 'the hand settings followed the brush onto its NEW id',
    );
    expect(landed[arrived.id.value]?.opacity, 0.25);
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
        handSettings: const {'ghost': (size: 99.0, opacity: null, blendMode: null)},
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
        pickDestination: (_) async {
          picked = true;
          return null;
        },
        write: (_, _) async {},
      ),
      isNull,
    );
    expect(picked, isFalse);
  });
}
