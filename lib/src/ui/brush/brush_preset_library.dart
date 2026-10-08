import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/mapped_or_same.dart';
import '../../models/brush_group.dart';
import '../../models/brush_group_icon.dart';
import '../../models/brush_group_id.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import '../../models/brush_settings.dart';
import '../../services/abr/abr_decoder.dart';
import '../../services/brush_preset_defaults.dart';
import '../../services/brush_preset_file_service.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/sut/sut_decoder.dart';
import 'brush_import_merge.dart';
import 'brush_tip_library.dart';
import 'picked_file.dart';
import '../../models/brush_hand_settings.dart';
import '../../services/brush_pack_file.dart';
import '../text/app_strings.dart';

/// The brush preset library: the groups, the preset list and every
/// mutation on them — save/rename/reorder/
/// delete for both presets and groups, plus ABR/SUT file import — with
/// fire-and-forget persistence to the app-level preset file. Pure data
/// controller; user messaging stays with the UI (mutations that want a
/// snackbar return the message text).
/// Which preset the library should open SHOWING, or null to leave the
/// selection alone.
///
/// 🚨★★★A BRUSH IN HAND THAT THE LIBRARY CANNOT NAME (유저, F-63):
/// 「브러시 라이브러리에서 **초기값이 아무것도 선택안된 UI**인데, 브러시는
/// 그려지는거 보니 **초기 브러시자체는 정해져있는거같음.** 그게 ui에도
/// 연동되있도록」.
///
/// ⛔The app opened with TWO facts: the paint tool carried baked-in settings
/// while the active-preset map was EMPTY, so it drew with a brush the panel
/// could not point at.
///
/// ⚠️A function rather than three lines inside the workspace, so the rule can
/// be read and tested without standing up an editor.
BrushPreset? openingPresetFor({
  required List<BrushPreset> presets,
  required bool toolPaints,
  required bool alreadyChosen,
}) {
  // ⛔Never overrule a choice: a load that lands after the user has picked
  // must leave their brush alone.
  if (alreadyChosen) {
    return null;
  }
  // ⛔And never move the hand. From a non-painting tool, applying a preset
  // arms the brush — at startup that would change the tool the app opens
  // with, which nobody asked for.
  if (!toolPaints || presets.isEmpty) {
    return null;
  }
  return presets.first;
}

/// Where every brush stands in the library: each preset's place and group,
/// and the groups' order — what a move in the panel changes, and what its
/// undo puts back (F-250).
///
/// ⚠️IDS, NOT PRESETS. A move undone after a delete or an import — neither
/// of which is on the undo stack — must not bring the deleted brush back or
/// push the imported one out, so a step remembers only where things stood
/// and is laid over what the library holds then
/// ([BrushPresetLibrary.arrange]).
typedef BrushLibraryArrangement = ({
  List<(BrushPresetId, BrushGroupId?)> presets,
  List<BrushGroupId> groups,
});

BrushLibraryArrangement brushLibraryArrangementOf(
  List<BrushPreset> presets,
  List<BrushGroup> groups,
) => (
  presets: [for (final preset in presets) (preset.id, preset.groupId)],
  groups: [for (final group in groups) group.id],
);

bool sameBrushLibraryArrangement(
  BrushLibraryArrangement a,
  BrushLibraryArrangement b,
) => listEquals(a.presets, b.presets) && listEquals(a.groups, b.groups);

class BrushPresetLibrary extends ChangeNotifier {
  BrushPresetLibrary({
    BrushPresetFileService? fileService,
    FilePicker? filePicker,
    BrushTipLibrary? tipLibrary,
    this.handSettingsPort,
  }) : _fileService = fileService ?? BrushPresetFileService(),
       _filePicker = filePicker ?? pickAnyFile,
       _tipLibrary = tipLibrary;

  final BrushPresetFileService _fileService;
  final FilePicker _filePicker;

  /// How an exported file gets the hand settings, and how an imported one
  /// gives them back.
  ///
  /// 🚨유저 (`Q-brush-store`): 「앱 안에서는 앱 저장소에 두되 내보낼 때는
  /// 브러시 파일에 쓴다」, and 2026-09-08: 「불투명도든 뭐든 손설정이든 정한거
  /// 싹 다 내보낼때 나르도록 하고싶음」.
  ///
  /// ⚠️A PORT, not a store: the bank lives in the workspace beside the tool
  /// state that writes it, and pulling the whole store in here would give
  /// one value two owners. Null in tests that do not care.
  final BrushHandSettingsPort? handSettingsPort;

  /// Where the sampled tips live. Presets reference them by id on disk, so
  /// loading resolves through here — and any tip that arrives INSIDE a
  /// preset (an old library, a freshly imported pack) is handed over so it
  /// gets a home of its own.
  final BrushTipLibrary? _tipLibrary;

  List<BrushGroup> _groups = const <BrushGroup>[];
  List<BrushPreset> _presets = const <BrushPreset>[];
  bool _disposed = false;

  /// Library groups in display order (the root section is not one of them —
  /// it is simply every preset without a group).
  List<BrushGroup> get groups => _groups;

  List<BrushPreset> get presets => _presets;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// The built-ins' namer: the program language's word for each, read the
  /// moment the defaults are made (brush-preset-names-language-Q1).
  static String _nameInProgramLanguage(String id, String english) =>
      AppText.strings.builtinBrushName(id, english);

  Future<void> load() async {
    final library = await _fileService.loadOrDefaults(
      resolveTip: _tipLibrary?.maskFor,
      nameBuiltIn: _nameInProgramLanguage,
    );
    _groups = library.groups;
    _presets = library.presets;
    _notify();
    await _adoptCarriedTips();
  }

  /// Moves any tip that came in ON a preset into the tip library.
  ///
  /// Two cases land here and neither can be skipped: a library saved before
  /// tips had a home still stores the image inline, and an imported pack
  /// arrives with its tips attached. Either way the next save writes an id,
  /// so a tip that was never adopted would be a reference to nothing.
  Future<void> _adoptCarriedTips() async {
    final tipLibrary = _tipLibrary;
    if (tipLibrary == null) {
      return;
    }
    for (final carried in brushTipMasksIn(_presets)) {
      if (_disposed) {
        return;
      }
      if (tipLibrary.maskFor(carried.mask.id) == null) {
        await tipLibrary.register(carried.mask, name: carried.name);
      }
    }
  }

  /// Saves the given settings as a new preset and returns it. It lands in
  /// [groupId] — the caller passes the held preset's group, so saving a
  /// variant of a brush keeps it next to the brush it came from.
  ///
  /// ⛔Which preset is HELD is not the library's to say: that is the tool
  /// state's `presetId` (H25-again), and the caller moves the hand onto the
  /// preset this returns. The library kept an active id of its own that no
  /// screen read — a third copy of one fact.
  BrushPreset saveCurrent(BrushSettings settings, {BrushGroupId? groupId}) {
    final preset = BrushPreset(
      id: BrushPresetId('user-${DateTime.now().millisecondsSinceEpoch}'),
      name: _nextPresetName(),
      groupId: _groups.any((group) => group.id == groupId) ? groupId : null,
      settings: settings,
    );
    _presets = [..._presets, preset];
    _notify();
    _persist();
    return preset;
  }

  void rename(BrushPresetId id, String name) {
    _presets = mappedOrSame(
      _presets,
      (preset) => preset.id == id ? preset.copyWith(name: name) : preset,
    );
    _notify();
    _persist();
  }

  BrushLibraryArrangement get arrangement =>
      brushLibraryArrangementOf(_presets, _groups);

  /// Lays [target] over the library as it stands: the presets and groups it
  /// names take its order, and each named preset its group; anything it does
  /// not name — a brush imported since — keeps its own order after them, and
  /// anything gone since stays gone.
  void arrange(BrushLibraryArrangement target) {
    final presetsById = {for (final preset in _presets) preset.id: preset};
    final namedPresets = {for (final (id, _) in target.presets) id};
    final groupsById = {for (final group in _groups) group.id: group};
    final namedGroups = target.groups.toSet();
    _presets = [
      for (final (id, groupId) in target.presets)
        if (presetsById[id] case final preset?)
          if (preset.groupId == groupId)
            preset
          else
            preset.copyWith(groupId: groupId),
      for (final preset in _presets)
        if (!namedPresets.contains(preset.id)) preset,
    ];
    _groups = [
      for (final id in target.groups) ?groupsById[id],
      for (final group in _groups)
        if (!namedGroups.contains(group.id)) group,
    ];
    _notify();
    _persist();
  }

  void delete(BrushPresetId id) {
    _presets = [
      for (final preset in _presets)
        if (preset.id != id) preset,
    ];
    _notify();
    _persist();
  }

  /// Adds an empty group at the end of the list; the user fills it by
  /// dragging presets in (an empty group is legal, which is the whole point
  /// of groups being entities).
  void createGroup(String name) {
    _groups = [
      ..._groups,
      BrushGroup(
        id: BrushGroupId('user-group-${DateTime.now().millisecondsSinceEpoch}'),
        name: name,
      ),
    ];
    _notify();
    _persist();
  }

  /// Saves a group's name and face together — they are edited in one
  /// dialog, so they land in one write rather than two notifies.
  void editGroup(BrushGroupId id, String name, BrushGroupIcon? icon) {
    _groups = mappedOrSame(
      _groups,
      // A null icon means "no icon chosen", which has to be writable — that
      // is how a group goes back to wearing its first brush.
      (group) => group.id == id
          ? group.copyWith(name: name, icon: icon, clearIcon: icon == null)
          : group,
    );
    _notify();
    _persist();
  }

  /// Deletes a group AND the presets inside it — the one-click way to drop
  /// an imported pack. Presets that were dragged out of the group earlier
  /// live elsewhere and are untouched.
  void deleteGroup(BrushGroupId id) {
    _groups = [
      for (final group in _groups)
        if (group.id != id) group,
    ];
    _presets = [
      for (final preset in _presets)
        if (preset.groupId != id) preset,
    ];
    _notify();
    _persist();
  }

  void setGroupCollapsed(BrushGroupId id, bool collapsed) {
    _groups = mappedOrSame(
      _groups,
      (group) => group.id == id ? group.copyWith(collapsed: collapsed) : group,
    );
    _notify();
    _persist();
  }

  /// Throws the whole library away and re-seeds the built-ins.
  void resetToDefaults() {
    _groups = namedDefaultBrushGroups(_nameInProgramLanguage);
    _presets = namedDefaultBrushPresets(_nameInProgramLanguage);
    _notify();
    _persist();
  }

  /// Runs the pick→decode→merge import flow. Returns the user-facing result
  /// message, or `null` when the picker was cancelled.
  Future<String?> importFromFile() => importPickedFile(
    pick: _filePicker,
    disposed: () => _disposed,
    import: _importBrushFile,
  );

  /// Writes [presets] — and the groups they belong to — as one `.anibrush`.
  ///
  /// 🚨유저 확정 (`brush-export-format-Q1`, 답 1): our own format, nothing
  /// lost. The two entry points are the user's own split (`H25-Q1`, 답
  /// both-by-selection): one brush, or the group it sits in.
  ///
  /// [hand] puts a file called its first argument in the person's hands:
  /// it asks where, has its second write the file at a path — there, or in
  /// the app first where no save window answers with a path — and answers
  /// where it landed, null when the person would not have it.
  /// 🚨brush-export-has-no-road-where-no-save-window-answers-a-path
  /// (2026-10-08): it asked the save window for a path itself, and on the
  /// iPad and Android, which have no such window, every export ended in an
  /// error.
  ///
  /// Returns the user-facing message, or null when the save was cancelled.
  Future<String?> exportPresets(
    List<BrushPreset> presets, {
    required Future<String?> Function(
      String suggestedName,
      Future<bool> Function(String path) write,
    )
    hand,
  }) async {
    if (presets.isEmpty) {
      return null;
    }
    final ids = {for (final preset in presets) preset.id};
    final groupIds = {
      for (final preset in presets)
        if (preset.groupId != null) preset.groupId,
    };
    final bank = handSettingsPort?.read() ?? const {};
    final pack = BrushPack(
      presets: presets,
      handSettings: {
        for (final id in ids)
          if (bank[id.value] != null) id.value: bank[id.value]!,
      },
    );
    final suggested =
        '${presets.length == 1 ? presets.single.name : _groupNameFor(groupIds)}'
        '.$anicelBrushExtension';
    Object? writeFailed;
    Future<bool> write(String path) async {
      try {
        await File(path).writeAsString(encodeBrushPack(pack), flush: true);
        return true;
      } on Object catch (error) {
        writeFailed = error;
        return false;
      }
    }

    final String? landed;
    try {
      landed = await hand(suggested, write);
    } on Object catch (error) {
      return 'Could not choose where to save: $error';
    }
    if (writeFailed != null) {
      return 'Could not write the brush file: $writeFailed';
    }
    if (landed == null || _disposed) {
      return null;
    }
    return presets.length == 1
        ? 'Exported "${presets.single.name}".'
        : 'Exported ${presets.length} brushes.';
  }

  /// The presets in [groupId], in library order — the second entry point.
  /// A null id means the ROOT section, which is every preset without a
  /// group rather than a group of its own — and every preset whose group is
  /// gone, the brushes that tab shows ([BrushPreset.groupShownAmong]).
  List<BrushPreset> presetsInGroup(BrushGroupId? groupId) => [
    for (final preset in _presets)
      if (preset.groupShownAmong(_groups) == groupId) preset,
  ];

  /// The preset a hand entering [groupId]'s tab takes up: [remembered] — the
  /// one it last held there — while it still shows in that tab, otherwise
  /// the tab's first, or null for an empty tab.
  ///
  /// 🗣️F-250 (유저 2026-10-01): 「브러시 그룹을 바꿀때(선택하던 뭐던), 해당
  /// 그룹의 마지막으로 선택했던걸 기억해서 그거 자동선택되도록」 — the tool
  /// rail's `railEntry` law for brush groups: from outside, back to where it
  /// was left; the first time, the group's own first.
  BrushPresetId? presetEntering(
    BrushGroupId? groupId, {
    BrushPresetId? remembered,
  }) {
    final tab = presetsInGroup(groupId);
    if (remembered != null && tab.any((each) => each.id == remembered)) {
      return remembered;
    }
    return tab.firstOrNull?.id;
  }

  /// The preset beside [id] in the tab it shows in — the next one, or the
  /// one before when it is the last — or null when it stands alone: what a
  /// hand holding [id] takes up when it is deleted (F-250).
  BrushPresetId? presetBeside(BrushPresetId id) {
    final preset = _presets.where((each) => each.id == id).firstOrNull;
    if (preset == null) {
      return null;
    }
    final tab = presetsInGroup(preset.groupShownAmong(_groups));
    final at = tab.indexWhere((each) => each.id == id);
    if (at + 1 < tab.length) {
      return tab[at + 1].id;
    }
    return at > 0 ? tab[at - 1].id : null;
  }

  String _groupNameFor(Set<BrushGroupId?> groupIds) {
    if (groupIds.length != 1) {
      return 'Brushes';
    }
    for (final group in _groups) {
      if (group.id == groupIds.single) {
        return group.name;
      }
    }
    return 'Brushes';
  }

  /// The decode→merge half of [importFromFile], on a file already picked.
  Future<String?> _importBrushFile(PickedFile pick) async {
    final lowerName = pick.name.toLowerCase();
    final baseName = pick.stem;
    // 🚨The picker shows every file (유저 2026-08-29), so THIS is where a
    // wrong one is refused — by name, before any decoder sees the bytes.
    // ⛔It used to fall through to the ABR decoder, which failed with
    // whatever ABR happened to say about a JPEG's first bytes.
    if (!FileTypeGroups.brushes.extensions!.any(
      (extension) => lowerName.endsWith('.$extension'),
    )) {
      return AppText.strings.unsupportedFileMessageTemplate.replaceAll(
        '{kinds}',
        FileTypeGroups.brushes.extensions!
            .map((extension) => '.$extension')
            .join(', '),
      );
    }
    final List<BrushPreset> imported;
    final List<String> warnings;
    // What the exporting hand had set on each brush, by preset id.
    var handInFile = const <String, BrushHandSettings>{};
    try {
      if (lowerName.endsWith('.$anicelBrushExtension')) {
        final pack = decodeBrushPack(utf8.decode(pick.bytes));
        imported = pack.presets;
        warnings = const [];
        handInFile = pack.handSettings;
      } else if (lowerName.endsWith('.sut') || lowerName.endsWith('.sutg')) {
        final result = await _decodeSutBytes(pick.bytes, sourceName: baseName);
        imported = result.presets;
        warnings = result.warnings;
      } else {
        final result = decodeAbrBrushFile(pick.bytes, sourceName: baseName);
        imported = result.presets;
        warnings = result.warnings;
      }
    } on BrushPackFormatException catch (error) {
      return error.message;
    } on AbrDecodeException catch (error) {
      return error.message;
    } on SutDecodeException catch (error) {
      return error.message;
    } on Exception {
      return 'This file could not be read as a brush file.';
    }
    if (_disposed) {
      return null;
    }
    final merged = mergeImportedBrushPresets(
      library: (groups: _groups, presets: _presets),
      imported: imported,
      sourceName: baseName,
    );
    _groups = merged.groups;
    _presets = merged.presets;
    // 🚨THE HAND SETTINGS ARRIVE WITH THEIR BRUSH (유저, `Q-brush-store`:
    // 「내보낼 때는 브러시 파일에 쓴다」).
    //
    // ⚠️Keyed by id, and that is checked rather than assumed: the merge
    // REPLACES a colliding preset instead of re-minting it (two presets may
    // never share an id), so the id in the file is the id in the library.
    // An entry naming a brush that did not land is dropped — a bank row for
    // a preset that does not exist would attach to whatever took that id
    // later.
    final port = handSettingsPort;
    if (handInFile.isNotEmpty && port != null) {
      final landedIds = {for (final preset in _presets) preset.id.value};
      final landed = {
        for (final entry in handInFile.entries)
          if (landedIds.contains(entry.key)) entry.key: entry.value,
      };
      if (landed.isNotEmpty) {
        port.write(landed);
      }
    }
    _notify();
    _persist();
    // The pack's tips become library tips in their own right, so they can be
    // put on any brush and survive the preset they arrived with.
    unawaited(_adoptCarriedTips());
    final summary = imported.length == 1
        ? 'Imported 1 brush from "${pick.name}".'
        : 'Imported ${imported.length} brushes from "${pick.name}".';
    return warnings.isEmpty
        ? summary
        : '$summary (${warnings.length} entries with warnings)';
  }

  /// The SQLite reader needs a file path; work on a scratch copy so the
  /// user's original brush file is never opened for writing or locked.
  Future<SutImportResult> _decodeSutBytes(
    Uint8List bytes, {
    required String sourceName,
  }) async {
    final directory = await Directory.systemTemp.createTemp('sut_import');
    try {
      final file = File('${directory.path}/import.sut');
      await file.writeAsBytes(bytes, flush: true);
      return await decodeSutBrushFile(
        filePath: file.path,
        sourceName: sourceName,
      );
    } finally {
      unawaited(
        directory.delete(recursive: true).catchError((Object _) => directory),
      );
    }
  }

  String _nextPresetName() {
    final names = {for (final preset in _presets) preset.name};
    final template = AppText.strings.brNewPresetName;
    String nameFor(int index) => template.replaceAll('{n}', '$index');
    var index = _presets.length + 1;
    while (names.contains(nameFor(index))) {
      index += 1;
    }
    return nameFor(index);
  }

  /// Writes the library as it stands, without waiting on the disk.
  ///
  /// 🚨ONE WRITER, IN CALL ORDER. Eleven mutators call this, and it used to
  /// fire each save off with nothing serializing them: two edits a frame
  /// apart raced, and "last write wins" meant last to FINISH, not last
  /// called — so a rename could land on disk after the delete that followed
  /// it and bring the preset back on the next load (2026-09-09). The library
  /// queued its own writes then; every settings file's writes keep their
  /// order now, the newest waiting behind the one on its way
  /// ([saveVersionedSettings]), and a failed one never reaches the editor.
  void _persist() =>
      unawaited(_fileService.save((groups: _groups, presets: _presets)));
}

/// How the library reaches the hand-settings bank without owning it.
///
/// ⚠️Two operations because there are two: an export READS what the hand has
/// set, and an import WRITES what arrived. One callback answering both would
/// be a flag deciding which question it was asked.
typedef BrushHandSettingsPort = ({
  Map<String, BrushHandSettings> Function() read,
  void Function(Map<String, BrushHandSettings> arrived) write,
});
