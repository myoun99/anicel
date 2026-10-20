import 'dart:convert';
import 'dart:io';

import '../models/brush_group.dart';
import '../models/brush_group_id.dart';
import '../models/brush_preset.dart';
import '../models/brush_preset_id.dart';
import '../models/brush_settings.dart';
import '../models/brush_tip_mask.dart';
import 'brush_preset_defaults.dart';
import 'persistence/app_support_path.dart';
import 'persistence/versioned_settings_file.dart';

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

  /// ⚠️Sandboxed under `FLUTTER_TEST`: the workspace builds the preset
  /// library itself when no service is handed in, so every widget test that
  /// pumps HomePage reaches this through the production wiring — and read,
  /// and could WRITE INTO, the developer's own library without the redirect
  /// (an English test showed someone's Korean brush names; board
  /// `tests-read-the-real-brush-library`).
  static String defaultBrushPresetFilePath() => testRedirectedAppSettingsPath(
    'brush_presets.json',
    sandbox: 'brush_presets',
  );

  /// Library file format version. A file that does not carry EXACTLY this
  /// version is replaced by the built-in defaults on load.
  ///
  /// 🚨⛔**THERE IS NO MIGRATION, ON PURPOSE** (유저 2026-09-09: 「기존 프리셋
  /// 그냥 마이그레이션 관련 코드 깔끔하게 없애도되. 필요없어. **아무도
  /// 작업안했고**」). Nobody has authored a brush yet, so five versions of
  /// carry-forward machinery — group names rebuilt into entities, built-ins
  /// re-homed out of the root section, icons backfilled onto rows that
  /// already existed — was maintenance for data that does not exist. Bumping
  /// this number now RESETS the library rather than upgrading it, which is
  /// what makes a roster change reach the person running the app.
  ///
  /// 🔜**THIS IS A PRE-RELEASE POLICY AND IT HAS AN EXPIRY.** The first
  /// release that reaches someone who has drawn with their own brushes has to
  /// put carry-forward back before it bumps this number, or the bump eats
  /// their library. Nothing here enforces that; this comment is the warning.
  ///
  /// ⛔**A ROSTER CHANGE DOES NOT BUMP IT EITHER** (유저 2026-09-24, board
  /// `preset-spacing-library-delivery`: 「굳이 뭐 안해도되. 내가 그냥 지금
  /// 있는거 삭제해서 초기화시킬테니 그런 이행코드같은거 만들지마」). 유저 has
  /// brushes of their own now, which a bump would eat without asking; they
  /// bring a new roster in themselves with "Reset brush library". ↩️So "what
  /// makes a roster change reach the person running the app" above no longer
  /// holds — board F-218 reworked the roster under version 9.
  // 8: the paper texture stores its SOURCE plus invert/brightness/contrast,
  // where 7 stored one mask with the levels already baked in. A 7 file would
  // read its baked mask back as a source and bake the levels a second time.
  // 9: the roster grew by twelve built-ins and a Decoration group. An 8 file
  // was written before those existed, so keeping it would hide every new row
  // behind a library the user never edited.
  static const int libraryVersion = 9;

  /// Reads the preset library; a missing, unreadable or older file yields the
  /// built-in defaults (nothing is written back until the next save).
  ///
  /// [resolveTip] turns the tip ids the file stores back into masks. An id it
  /// cannot answer leaves the brush on its parametric round tip — a missing
  /// tip costs a brush its texture, never the editor.
  ///
  /// [nameBuiltIn] names each built-in as the defaults are made. The words
  /// belong to the UI, which this layer may not import, so a caller that
  /// speaks another language hands them in; the default keeps the English.
  Future<BrushPresetLibraryData> loadOrDefaults({
    BrushTipResolver? resolveTip,
    BuiltinBrushName nameBuiltIn = keepEnglishName,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return _defaults(nameBuiltIn);
      }
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (decoded['version'] != libraryVersion) {
        return _defaults(nameBuiltIn);
      }
      final entries = decoded['presets'] as List<dynamic>;
      // An empty saved library is a valid user choice (all presets deleted).
      final presets = _withUniquePresetIds([
        for (final entry in entries)
          _presetWithResolvedTips(entry as Map<String, dynamic>, resolveTip),
      ]);
      // A file of this version always carries `groups`; one that does not is
      // malformed, and the cast drops it into the catch below rather than
      // into a reconstruction nobody asked for.
      final groups = _withoutDuplicateGroups([
        for (final raw in decoded['groups'] as List<dynamic>)
          BrushGroup.fromJson(raw as Map<String, dynamic>),
      ]);

      return (groups: groups, presets: _withKnownGroups(presets, groups));
    } on Object catch (_) {
      // A corrupt library must not fail the editor: fall back to the
      // defaults; the file is replaced on the next save.
      return _defaults(nameBuiltIn);
    }
  }

  static BrushPresetLibraryData _defaults(BuiltinBrushName nameOf) => (
    groups: namedDefaultBrushGroups(nameOf),
    presets: namedDefaultBrushPresets(nameOf),
  );

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
  /// header that is not there — the tab it shows in
  /// ([BrushPreset.groupShownAmong]) made what it holds.
  static List<BrushPreset> _withKnownGroups(
    List<BrushPreset> presets,
    List<BrushGroup> groups,
  ) => [
    for (final preset in presets)
      if (preset.groupShownAmong(groups) == preset.groupId)
        preset
      else
        preset.copyWith(groupId: null),
  ];

  /// Writes the preset library, creating the app-data directory as needed.
  Future<void> save(BrushPresetLibraryData library) => saveVersionedSettings(
    filePath: filePath,
    version: libraryVersion,
    json: {
      'groups': [for (final group in library.groups) group.toJson()],
      'presets': [
        for (final preset in library.presets) _presetJsonWithTipIds(preset),
      ],
    },
  );

  /// Swaps each inline mask blob for its id on the way OUT.
  ///
  /// The swap lives here, at the file boundary, and nowhere else: settings
  /// in memory keep carrying mask OBJECTS, so the dabs, the three
  /// rasterizers and the parity tests never learn that a tip has an address.
  static Map<String, dynamic> _presetJsonWithTipIds(BrushPreset preset) {
    final json = preset.toJson();
    final settings = Map<String, dynamic>.from(
      json['settings'] as Map<String, dynamic>,
    );
    for (final key in brushSettingsMaskKeys) {
      settings.remove(key);
      final masks = brushSettingsMasksAt(preset.settings, key);
      if (masks.isNotEmpty) {
        settings[brushSettingsMaskIdKey(key)] = brushSettingsMaskIdsJson(
          key,
          masks,
        );
      }
    }
    json['settings'] = settings;
    return json;
  }

  /// Puts the masks back on the way IN. Versions 4 and older stored the
  /// blob itself, which [BrushPreset.fromJson] still reads — so a library
  /// written before the tip library existed loads with its tips intact, and
  /// the caller hoists them into the library afterwards.
  static BrushPreset _presetWithResolvedTips(
    Map<String, dynamic> json,
    BrushTipResolver? resolveTip,
  ) {
    final preset = BrushPreset.fromJson(json);
    if (resolveTip == null) {
      return preset;
    }
    final settingsJson = json['settings'] as Map<String, dynamic>;
    var settings = preset.settings;
    for (final key in brushSettingsMaskKeys) {
      settings = brushSettingsWithMasks(settings, key, [
        for (final id in brushSettingsMaskIdsFrom(
          settingsJson[brushSettingsMaskIdKey(key)],
        ))
          ?resolveTip(id),
      ]);
    }
    return preset.copyWith(settings: settings);
  }
}

/// Answers "what mask is behind this id?" for the preset loader — the tip
/// library, in production.
typedef BrushTipResolver = BrushTipMask? Function(String id);

/// The mask-valued settings, by json key.
///
/// ⚠️Shared by every writer that names tips by id — the preset file and the
/// hand bank (`brush_hand_overlay.dart`) — so a fifth mask cannot be named
/// by one and carried whole by the other; and by [brushTipMasksIn], so the
/// tip library adopts exactly the masks a file goes on to name.
// ⚠️'textureMaskSource', not 'textureMask': the file stores the texture AS
// PICKED, and the levelled bake beside it is derived — it has no id of its
// own and nothing in the library to resolve back to.
const List<String> brushSettingsMaskKeys = [
  'tipMask',
  brushSettingsMoreTipsKey,
  'dualMask',
  'textureMaskSource',
];

/// The tips after the first ([BrushSettings.tips], F-176-Q3) — the one mask
/// key that holds a LIST, so its value is one too, whole or by id. The first
/// tip keeps 'tipMask', which is why a file from before a brush could carry
/// several reads with no code of its own (see [BrushSettings.toJson]).
const String brushSettingsMoreTipsKey = 'moreTipMasks';

/// Where a writer that names tips keeps the ids of the masks at json [key].
String brushSettingsMaskIdKey(String key) => '${key}Id';

/// The masks [settings] holds at json [key] — one at most, but at
/// [brushSettingsMoreTipsKey].
List<BrushTipMask> brushSettingsMasksAt(BrushSettings settings, String key) =>
    switch (key) {
      'tipMask' => [...settings.tips.take(1)],
      brushSettingsMoreTipsKey => [...settings.tips.skip(1)],
      'dualMask' => [?settings.dualMask],
      _ => [?settings.textureMaskSource],
    };

/// [settings] holding [masks] at json [key].
///
/// ⚠️None leaves what is there — `copyWith` keeps what it is not given — so
/// a caller that means "no tip" starts from settings read without, and lays
/// the keys in [brushSettingsMaskKeys]' order: the first tip, then the ones
/// after it.
BrushSettings brushSettingsWithMasks(
  BrushSettings settings,
  String key,
  List<BrushTipMask> masks,
) {
  if (masks.isEmpty) {
    return settings;
  }
  return switch (key) {
    'tipMask' => settings.copyWith(
      tips: [masks.first, ...settings.tips.skip(1)],
    ),
    brushSettingsMoreTipsKey => settings.copyWith(
      tips: [...settings.tips.take(1), ...masks],
    ),
    'dualMask' => settings.copyWith(dualMask: masks.first),
    _ => settings.copyWith(textureMaskSource: masks.first),
  };
}

/// [masks], held at json [key], as a writer that names tips writes them.
Object brushSettingsMaskIdsJson(String key, List<BrushTipMask> masks) =>
    key == brushSettingsMoreTipsKey
    ? [for (final mask in masks) mask.id]
    : masks.first.id;

/// [masks], held at json [key], carried whole.
Object brushSettingsMasksJson(String key, List<BrushTipMask> masks) =>
    key == brushSettingsMoreTipsKey
    ? [for (final mask in masks) mask.toJson()]
    : masks.first.toJson();

/// The ids at an id key — the one of a one-mask key, or the list at
/// [brushSettingsMoreTipsKey]'s.
List<String> brushSettingsMaskIdsFrom(Object? json) => switch (json) {
  final String id => [id],
  final List<dynamic> ids => [
    for (final id in ids)
      if (id is String) id,
  ],
  _ => const [],
};

/// The masks a key carries whole — one, or the list at
/// [brushSettingsMoreTipsKey].
List<BrushTipMask> brushSettingsMasksFrom(Object? json) => switch (json) {
  final Map<String, dynamic> mask => [BrushTipMask.fromJson(mask)],
  final List<dynamic> masks => [
    for (final mask in masks)
      BrushTipMask.fromJson(mask as Map<String, dynamic>),
  ],
  _ => const [],
};

/// Every distinct mask carried by [presets].
///
/// The tip library hoists these on load (`brush_preset_library.dart`): a
/// preset arriving with its mask INLINE — from an import, or from a built-in
/// that carries a procedural one — has to reach the tip library, or the next
/// save writes an id pointing at nothing.
///
/// 🚨THE MASKS AT [brushSettingsMaskKeys], and no list of its own. It kept
/// one, which still read the texture's levelled BAKE after G5 (2026-09-09)
/// moved the file onto the texture as picked: the bake carries its
/// source's id, so the library adopted it under that id, and the next start
/// resolved the id to the bake and levelled it a second time.
List<({BrushTipMask mask, String name})> brushTipMasksIn(
  Iterable<BrushPreset> presets,
) {
  final seen = <String>{};
  final found = <({BrushTipMask mask, String name})>[];
  for (final preset in presets) {
    for (final key in brushSettingsMaskKeys) {
      for (final mask in brushSettingsMasksAt(preset.settings, key)) {
        if (seen.add(mask.id)) {
          found.add((mask: mask, name: preset.name));
        }
      }
    }
  }
  return found;
}
