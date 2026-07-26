import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../models/brush_group.dart';
import '../../models/brush_group_id.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import '../../models/brush_settings.dart';
import '../../services/abr/abr_decoder.dart';
import '../../services/brush_preset_defaults.dart';
import '../../services/brush_preset_file_service.dart';
import '../../services/sut/sut_decoder.dart';
import 'brush_import_merge.dart';
import 'brush_tip_library.dart';

/// A picked brush file: display name plus raw bytes.
typedef BrushFilePick = ({String name, Uint8List bytes});

/// Opens a brush file picker; `null` when the user cancels.
typedef BrushFilePicker = Future<BrushFilePick?> Function();

/// Production picker: the platform open-file dialog filtered to the
/// supported brush formats.
Future<BrushFilePick?> _openBrushFileDialog() async {
  const typeGroup = XTypeGroup(
    label: 'Brushes (Photoshop, Clip Studio)',
    extensions: ['abr', 'sut', 'sutg'],
  );
  final file = await openFile(acceptedTypeGroups: const [typeGroup]);
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
class BrushPresetLibrary extends ChangeNotifier {
  BrushPresetLibrary({
    BrushPresetFileService? fileService,
    BrushFilePicker? filePicker,
    BrushTipLibrary? tipLibrary,
  }) : _fileService = fileService ?? BrushPresetFileService(),
       _filePicker = filePicker ?? _openBrushFileDialog,
       _tipLibrary = tipLibrary;

  final BrushPresetFileService _fileService;
  final BrushFilePicker _filePicker;

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

  void renameGroup(BrushGroupId id, String name) {
    _groups = [
      for (final group in _groups)
        group.id == id ? group.copyWith(name: name) : group,
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
  Future<String?> importFromFile() async {
    final BrushFilePick? pick;
    try {
      pick = await _filePicker();
    } catch (error) {
      return 'Could not open the file: $error';
    }
    if (pick == null || _disposed) {
      return null;
    }

    final lowerName = pick.name.toLowerCase();
    final baseName = pick.name.contains('.')
        ? pick.name.substring(0, pick.name.lastIndexOf('.'))
        : pick.name;
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
