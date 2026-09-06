import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

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
import '../text/app_strings.dart';

/// Production picker: the platform open-file dialog, showing EVERY file.
///
/// 🚨유저 2026-08-29: 「픽커는 어떤플랫폼이든 어떤 확장자던 선택할수
/// 있게하고, 대응만 지원안되는 확장자면 그 때 해당 파일 지원안된다고 안내창
/// 띄우게」. [BrushPresetLibrary.importFromFile] is the "그 때" — it already
/// returns a user-facing message, so the refusal has somewhere to go.
Future<PickedFile?> _openBrushFileDialog() async {
  final file = await openFile(acceptedTypeGroups: const []);
  if (file == null) {
    return null;
  }
  final bytes = await File(file.path).readAsBytes();
  return (name: file.name, bytes: bytes);
}

/// The brush preset library: the groups, the preset list, the active
/// (highlighted) preset and every mutation on them — save/rename/reorder/
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

class BrushPresetLibrary extends ChangeNotifier {
  BrushPresetLibrary({
    BrushPresetFileService? fileService,
    FilePicker? filePicker,
    BrushTipLibrary? tipLibrary,
  }) : _fileService = fileService ?? BrushPresetFileService(),
       _filePicker = filePicker ?? _openBrushFileDialog,
       _tipLibrary = tipLibrary;

  final BrushPresetFileService _fileService;
  final FilePicker _filePicker;

  /// Where the sampled tips live. Presets reference them by id on disk, so
  /// loading resolves through here — and any tip that arrives INSIDE a
  /// preset (an old library, a freshly imported pack) is handed over so it
  /// gets a home of its own.
  final BrushTipLibrary? _tipLibrary;

  List<BrushGroup> _groups = const <BrushGroup>[];
  List<BrushPreset> _presets = const <BrushPreset>[];
  BrushPresetId? _activePresetId;
  bool _disposed = false;

  /// Library groups in display order (the root section is not one of them —
  /// it is simply every preset without a group).
  List<BrushGroup> get groups => _groups;

  List<BrushPreset> get presets => _presets;

  /// The last-applied (or last-saved) preset, highlighted in the list.
  /// Tweaking settings keeps the highlight; deleting the preset clears it.
  BrushPresetId? get activePresetId => _activePresetId;

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

  Future<void> load() async {
    final library = await _fileService.loadOrDefaults(
      resolveTip: _tipLibrary?.maskFor,
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

  void markActive(BrushPresetId? id) {
    if (_activePresetId == id) {
      return;
    }
    _activePresetId = id;
    _notify();
  }

  /// Saves the given settings as a new preset and makes it active. It lands
  /// in [groupId] — the caller passes the active preset's group, so saving a
  /// variant of a brush keeps it next to the brush it came from.
  void saveCurrent(BrushSettings settings, {BrushGroupId? groupId}) {
    final preset = BrushPreset(
      id: BrushPresetId('user-${DateTime.now().millisecondsSinceEpoch}'),
      name: _nextPresetName(),
      groupId: _groups.any((group) => group.id == groupId) ? groupId : null,
      settings: settings,
    );
    _presets = [..._presets, preset];
    _activePresetId = preset.id;
    _notify();
    _persist();
  }

  void rename(BrushPresetId id, String name) {
    _presets = [
      for (final preset in _presets)
        preset.id == id ? preset.copyWith(name: name) : preset,
    ];
    _notify();
    _persist();
  }

  void reorder(List<BrushPreset> presets) {
    _presets = List.of(presets);
    _notify();
    _persist();
  }

  void delete(BrushPresetId id) {
    _presets = [
      for (final preset in _presets)
        if (preset.id != id) preset,
    ];
    if (_activePresetId == id) {
      _activePresetId = null;
    }
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
    _groups = [
      for (final group in _groups)
        group.id == id
            // A null icon means "no icon chosen", which has to be writable
            // — that is how a group goes back to wearing its first brush.
            ? group.copyWith(name: name, icon: icon, clearIcon: icon == null)
            : group,
    ];
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
    if (!_presets.any((preset) => preset.id == _activePresetId)) {
      _activePresetId = null;
    }
    _notify();
    _persist();
  }

  void setGroupCollapsed(BrushGroupId id, bool collapsed) {
    _groups = [
      for (final group in _groups)
        group.id == id ? group.copyWith(collapsed: collapsed) : group,
    ];
    _notify();
    _persist();
  }

  void reorderGroups(List<BrushGroup> groups) {
    _groups = List.of(groups);
    _notify();
    _persist();
  }

  /// Throws the whole library away and re-seeds the built-ins.
  void resetToDefaults() {
    _groups = List.of(defaultBrushGroups);
    _presets = List.of(defaultBrushPresets);
    _activePresetId = null;
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
    try {
      if (lowerName.endsWith('.sut') || lowerName.endsWith('.sutg')) {
        final result = await _decodeSutBytes(pick.bytes, sourceName: baseName);
        imported = result.presets;
        warnings = result.warnings;
      } else {
        final result = decodeAbrBrushFile(pick.bytes, sourceName: baseName);
        imported = result.presets;
        warnings = result.warnings;
      }
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
    if (!_presets.any((preset) => preset.id == _activePresetId)) {
      _activePresetId = null;
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
    var index = _presets.length + 1;
    while (names.contains('Preset $index')) {
      index += 1;
    }
    return 'Preset $index';
  }

  void _persist() {
    // Fire-and-forget: preset persistence must never block or crash the
    // editor; a failed write just leaves the in-memory library unsaved.
    unawaited(
      _fileService
          .save((groups: _groups, presets: _presets))
          .catchError((Object _) {}),
    );
  }
}
