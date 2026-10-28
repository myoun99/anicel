import 'package:flutter/widgets.dart' show SingleActivator;

import '../../services/persistence/settings_file.dart';
import '../../services/persistence/versioned_settings_file.dart';

import '../../services/persistence/app_support_path.dart';
import 'shortcut_activator_codec.dart';
import 'shortcut_presets.dart';
import 'touch_shortcuts.dart' show TouchGesture;

/// Loads and saves the user's shortcut settings: the preset in use, the keys
/// recorded under each preset ({preset: {actionId: [activator json]}}), the
/// presets the user made (I-107: [{id, name, base, keys}] — a build before
/// them passes the list over) and the touch gestures. Editor/app state like
/// the workspace layout: an
/// app-support JSON file; missing or corrupt files simply yield no overrides
/// (the registry defaults win).
class ShortcutSettingsStore {
  ShortcutSettingsStore({String? filePath})
    : filePath = filePath ?? defaultShortcutSettingsFilePath();

  final String filePath;

  /// Its document's name in a settings file ([shortcutPresetSettingsFile]):
  /// its file's in the settings room. ⚠️Spelled out again below on purpose —
  /// the room's scan reads the store's call as written
  /// (`settings_live_in_one_room_test`); a test holds the two together.
  static const String fileName = 'shortcut_overrides.json';

  static String defaultShortcutSettingsFilePath() =>
      appSettingsFilePath('shortcut_overrides.json');

  /// ↩️1 held ONE set of overrides ({actionId: […]}) — there was one layout,
  /// the registry's. 2 (I-63) holds a set per preset and the preset in use.
  static const int version = 2;

  /// The saved payload in THIS version's shape; null when
  /// missing/corrupt/newer.
  Future<Map<String, Object?>?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: _inThisShape,
  );

  /// A version 1 document's overrides were recorded over the registry's own
  /// keys, which is the anicel preset — so that is whose they are now, and a
  /// key somebody recorded before the presets still presses what it did.
  static Map<String, Object?> _inThisShape(Map<String, dynamic> json) =>
      (json['version'] as int? ?? 0) >= version
      ? json
      : {
          ...json,
          'overrides': {ShortcutPreset.anicel.name: json['overrides']},
        };

  Future<void> save(Map<String, Object?> payload) => saveVersionedSettings(
    filePath: filePath,
    version: version,
    json: payload,
  );
}

/// The payload [ShortcutSettingsStore.save] writes: the layout [inUse], what
/// was [recorded] under each layout, the [userPresets] and the [touch]
/// gestures.
Map<String, Object?> shortcutSettingsPayload({
  required ShortcutLayout inUse,
  required Map<ShortcutLayout, Map<String, List<SingleActivator>>> recorded,
  required List<UserShortcutPreset> userPresets,
  required Map<String, TouchGesture?> touch,
}) => {
  'preset': inUse.id,
  'overrides': {
    for (final MapEntry(key: layout, value: keys) in recorded.entries)
      layout.id: _keysToJson(keys),
  },
  'presets': [for (final preset in userPresets) _presetJson(preset)],
  'touch': {
    for (final entry in touch.entries) entry.key: entry.value?.name,
  },
};

/// A preset of the user's as the settings write it ([userPresetFromJson]
/// reads it back).
Map<String, Object?> _presetJson(UserShortcutPreset preset) => {
  'id': preset.id,
  'name': preset.name,
  'base': preset.base.name,
  'keys': _keysToJson(preset.ownKeys),
};

/// [preset] alone as a settings file (I-142): the shortcut store's own
/// document, holding just it — as one of the user's, the keys it presses
/// over its [ShortcutLayout.base]'s all its own.
String shortcutPresetSettingsFile(UserShortcutPreset preset) =>
    encodeSettingsFile({
      ShortcutSettingsStore.fileName: versionedSettingsDocument(
        ShortcutSettingsStore.version,
        {
          'presets': [_presetJson(preset)],
        },
      ),
    });

/// The presets the settings file [source] holds, read as the shortcut store
/// reads its own file — an action [keeps] declines dropped; null where it
/// holds none.
List<UserShortcutPreset>? shortcutPresetsInSettingsFile(
  String source, {
  required bool Function(String actionId) keeps,
}) {
  final document = decodeSettingsFile(
    source,
  )?[ShortcutSettingsStore.fileName];
  if (document == null) {
    return null;
  }
  try {
    final payload = liftVersionedSettingsDocument(
      document,
      version: ShortcutSettingsStore.version,
      fromJson: ShortcutSettingsStore._inThisShape,
    );
    final listed = payload?['presets'];
    final recorded = payload?['overrides'];
    if (listed is! List) {
      return null;
    }
    return [
      for (final json in listed)
        ?userPresetFromJson(
          json,
          recordedById: recorded is Map ? recorded : const {},
          keeps: keeps,
        ),
    ];
  } on Object {
    return null;
  }
}

Map<String, Object?> _keysToJson(Map<String, List<SingleActivator>> keys) => {
  for (final MapEntry(key: actionId, value: activators) in keys.entries)
    actionId: [
      for (final activator in activators) singleActivatorToJson(activator),
    ],
};

/// The preset the app ships that a settings file names.
///
/// ⚠️NOT the preset an install with no file opens on (the bindings' first
/// value, Clip Studio's since I-63-Q5). A file that names no preset this
/// build knows was written over the registry's keys: before the presets,
/// or by a build whose preset this one lacks.
ShortcutPreset shippedPresetNamed(Object? name) =>
    ShortcutPreset.named(name) ?? ShortcutPreset.anicel;

/// One of the user's presets out of its saved [json], with what was
/// recorded under it out of [recordedById]; null where [json] is none. An
/// action [keeps] declines is dropped.
UserShortcutPreset? userPresetFromJson(
  Object? json, {
  required Map<Object?, Object?> recordedById,
  required bool Function(String actionId) keeps,
}) {
  if (json case {
    'id': final String id,
    'name': final String name,
    'base': final Object? base,
    'keys': final Object? keys,
  }) {
    return UserShortcutPreset(
      id: id,
      name: name,
      base: shippedPresetNamed(base),
      keys: shortcutKeysFromJson(keys, keeps),
      recorded: {...shortcutKeysFromJson(recordedById[id], keeps)},
    );
  }
  return null;
}

/// One layout's keys out of their saved [json] — an action [keeps] declines
/// and a malformed entry dropped.
Map<String, List<SingleActivator>> shortcutKeysFromJson(
  Object? json,
  bool Function(String actionId) keeps,
) => {
  for (final (actionId, listJson) in _keptEntries(json, keeps))
    if (listJson is List)
      actionId: List.unmodifiable([
        for (final activatorJson in listJson)
          ?singleActivatorFromJson(activatorJson),
      ]),
};

/// The touch gestures out of their saved [json]: a gesture by its name, or
/// null for an action deliberately unbound — an action [keeps] declines
/// and a name no gesture has dropped.
Map<String, TouchGesture?> touchGesturesFromJson(
  Object? json,
  bool Function(String actionId) keeps,
) => {
  for (final (actionId, name) in _keptEntries(json, keeps))
    if (name == null)
      actionId: null
    else if (name is String)
      actionId: ?TouchGesture.fromName(name),
};

/// The entries of a saved {actionId: …} [json] whose action [keeps] takes.
Iterable<(String, Object?)> _keptEntries(
  Object? json,
  bool Function(String actionId) keeps,
) => [
  if (json is Map)
    for (final MapEntry(:key, :value) in json.entries)
      if (key is String && keeps(key)) (key, value),
];
