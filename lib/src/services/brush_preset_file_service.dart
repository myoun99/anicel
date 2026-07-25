import 'dart:convert';
import 'dart:io';

import '../models/brush_group.dart';
import '../models/brush_group_id.dart';
import '../models/brush_preset.dart';
import '../models/brush_preset_id.dart';
import 'brush_preset_defaults.dart';
import 'persistence/app_support_path.dart';

/// A whole brush library: the groups in display order plus every preset.
///
/// Membership lives on the presets ([BrushPreset.groupId]), not on the
/// groups, so a preset only ever appears once and moving one between groups
/// is a single field write.
typedef BrushPresetLibraryData = ({
  List<BrushGroup> groups,
  List<BrushPreset> presets,
});

/// Loads and saves the app-level brush preset library.
///
/// Presets are editor/app state, not project data: they live in an
/// app-support JSON file and never enter the project save schema (per the
/// brush settings boundary in `Current_Brush_Architecture.md`).
class BrushPresetFileService {
  BrushPresetFileService({String? filePath})
    : filePath = filePath ?? defaultBrushPresetFilePath();

  /// Absolute path of the preset library file.
  final String filePath;

  static String defaultBrushPresetFilePath() =>
      appSupportFilePath('brush_presets.json');

  /// Library file format version. Bump when a release adds new built-in
  /// groups or presets: libraries saved with an older version get the new
  /// built-ins merged in once on load (an explicitly deleted built-in stays
  /// deleted within the same version).
  ///
  /// 3 turned groups into first-class entities: they live in their own
  /// `groups` list and presets reference one by id, where versions 1-2
  /// repeated the group NAME on every member.
  static const int libraryVersion = 3;

  /// Reads the preset library; a missing or unreadable file yields the
  /// built-in defaults (nothing is written back until the next save).
  Future<BrushPresetLibraryData> loadOrDefaults() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return _defaults();
      }
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final entries = decoded['presets'] as List<dynamic>;
      final savedVersion = decoded['version'] as int? ?? 1;
      // An empty saved library is a valid user choice (all presets deleted).
      var presets = _withUniquePresetIds([
        for (final entry in entries)
          BrushPreset.fromJson(entry as Map<String, dynamic>),
      ]);

      final rawGroups = decoded['groups'] as List<dynamic>?;
      List<BrushGroup> groups;
      if (rawGroups == null) {
        // Version 1-2 stored the group as a NAME repeated on every member;
        // rebuild the entities from those names, in first-appearance order.
        final migrated = _migrateLegacyGroups(entries, presets);
        groups = migrated.groups;
        presets = migrated.presets;
      } else {
        groups = _withoutDuplicateGroups([
          for (final raw in rawGroups)
            BrushGroup.fromJson(raw as Map<String, dynamic>),
        ]);
      }

      if (savedVersion < libraryVersion) {
        final knownGroupIds = {for (final group in groups) group.id};
        final knownPresetIds = {for (final preset in presets) preset.id};
        groups = [
          ...groups,
          for (final builtin in defaultBrushGroups)
            if (!knownGroupIds.contains(builtin.id)) builtin,
        ];
        presets = [
          ...presets,
          for (final builtin in defaultBrushPresets)
            if (!knownPresetIds.contains(builtin.id)) builtin,
        ];
      }

      return (groups: groups, presets: _withKnownGroups(presets, groups));
    } catch (_) {
      // A corrupt library must not fail the editor: fall back to the
      // defaults; the file is replaced on the next save.
      return _defaults();
    }
  }

  static BrushPresetLibraryData _defaults() => (
    groups: List.of(defaultBrushGroups),
    presets: List.of(defaultBrushPresets),
  );

  /// Rebuilds group entities from the group NAMES a version 1-2 library
  /// repeated on each preset, keeping first-appearance order. [entries] is
  /// the raw json in the same order as [presets].
  static BrushPresetLibraryData _migrateLegacyGroups(
    List<dynamic> entries,
    List<BrushPreset> presets,
  ) {
    final groups = <BrushGroup>[];
    final idsByName = <String, BrushGroupId>{};
    final migrated = <BrushPreset>[];
    for (var index = 0; index < presets.length; index += 1) {
      final name = (entries[index] as Map<String, dynamic>)['group'] as String?;
      if (name == null) {
        migrated.add(presets[index]);
        continue;
      }
      final groupId = idsByName.putIfAbsent(name, () {
        final id = importedBrushGroupId(name);
        groups.add(BrushGroup(id: id, name: name));
        return id;
      });
      migrated.add(presets[index].copyWith(groupId: groupId));
    }
    return (groups: groups, presets: migrated);
  }

  /// Preset ids must be unique (they key preset rows and drive
  /// replace-on-import), so duplicates in a saved library — e.g. written by
  /// the pre-fix ABR importer when several brushes shared one tip — are
  /// healed on load by suffixing later occurrences deterministically.
  static List<BrushPreset> _withUniquePresetIds(List<BrushPreset> presets) {
    final seen = <String>{};
    return [
      for (final preset in presets)
        if (seen.add(preset.id.value))
          preset
        else
          preset.copyWith(
            id: BrushPresetId(_nextFreeId(preset.id.value, seen)),
          ),
    ];
  }

  static String _nextFreeId(String id, Set<String> seen) {
    var suffix = 2;
    while (true) {
      final candidate = '$id-$suffix';
      if (seen.add(candidate)) {
        return candidate;
      }
      suffix += 1;
    }
  }

  /// A repeated group id can only mean the same group written twice, and
  /// members point at it by id — so duplicates COLLAPSE (first wins) rather
  /// than getting suffixed the way preset ids do, which would orphan every
  /// member of the later copy.
  static List<BrushGroup> _withoutDuplicateGroups(List<BrushGroup> groups) {
    final seen = <BrushGroupId>{};
    return [
      for (final group in groups)
        if (seen.add(group.id)) group,
    ];
  }

  /// Sends presets whose group no longer exists back to the root section, so
  /// a hand-edited or partially-merged file can never hide a preset behind a
  /// header that is not there.
  static List<BrushPreset> _withKnownGroups(
    List<BrushPreset> presets,
    List<BrushGroup> groups,
  ) {
    final knownIds = {for (final group in groups) group.id};
    return [
      for (final preset in presets)
        if (preset.groupId == null || knownIds.contains(preset.groupId))
          preset
        else
          preset.copyWith(groupId: null),
    ];
  }

  /// Writes the preset library, creating the app-data directory as needed.
  Future<void> save(BrushPresetLibraryData library) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'version': libraryVersion,
        'groups': [for (final group in library.groups) group.toJson()],
        'presets': [for (final preset in library.presets) preset.toJson()],
      }),
    );
  }
}
