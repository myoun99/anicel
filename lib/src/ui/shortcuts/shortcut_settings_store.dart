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
  _command: _commandHere(),
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

/// Where a shortcut document names the command key its keys were pressed
/// under ([pressedHere]).
const String _command = 'command';

/// The command key a document written HERE names.
String _commandHere() => commandIsMeta() ? 'meta' : 'ctrl';

/// How the keys a saved shortcut [document] holds are pressed HERE.
///
/// 🗣️I-142-Q8 (유저 2026-10-29): 「기기가 바뀌면 Ctrl 과 ⌘ 를 바꿔
/// 읽는다」. A document names the command key its keys were pressed under,
/// and read where the command key is the other one, each key's Ctrl and ⌘
/// trade places — as a registry default is read on each device
/// ([platformActivator]): a Ctrl+K recorded on a PC is ⌘K on a Mac.
/// ⚠️A key pressed with both trades both — the cost the question named.
/// A document that names no command key is read as pressed.
SingleActivator Function(SingleActivator) pressedHere(
  Map<String, Object?>? document,
) => switch (document?[_command]) {
  'ctrl' when commandIsMeta() => commandSwapped,
  'meta' when !commandIsMeta() => commandSwapped,
  _ => _asPressed,
};

SingleActivator _asPressed(SingleActivator activator) => activator;

/// What [payload] — [shortcutSettingsPayload]'s — holds, each key as it is
/// pressed here ([pressedHere]); null where it holds no overrides. Unknown
/// action ids ([keeps]) and malformed entries are dropped, and a preset no
/// build knows reads as the registry's own — an app update or a corrupt
/// file never breaks the bindings.
({
  List<UserShortcutPreset> userPresets,
  ShortcutLayout inUse,
  Map<ShortcutPreset, Map<String, List<SingleActivator>>> recorded,
  Map<String, TouchGesture?> touch,
})?
shortcutSettingsFromPayload(
  Map<String, Object?>? payload, {
  required bool Function(String actionId) keeps,
}) {
  final byPreset = payload?['overrides'];
  if (byPreset is! Map) {
    return null;
  }
  final pressed = pressedHere(payload);
  final userPresets = [
    if (payload?['presets'] case final List saved)
      for (final json in saved)
        ?_userPresetFromJson(
          json,
          recordedById: byPreset,
          keeps: keeps,
          pressed: pressed,
        ),
  ];
  final inUse = payload?['preset'];
  return (
    userPresets: userPresets,
    inUse:
        userPresets.where((preset) => preset.id == inUse).firstOrNull ??
        _shippedPresetNamed(inUse),
    recorded: {
      for (final preset in ShortcutPreset.values)
        preset: _shortcutKeysFromJson(byPreset[preset.name], keeps, pressed),
    },
    touch: _touchGesturesFromJson(payload?['touch'], keeps),
  );
}

/// A preset of the user's as the settings write it ([_userPresetFromJson]
/// reads it back).
Map<String, Object?> _presetJson(UserShortcutPreset preset) => {
  'id': preset.id,
  'name': preset.name,
  'base': preset.base.name,
  'keys': _keysToJson(preset.ownKeys),
};

/// [preset] alone as a settings file (I-142), named [name] and pressing
/// [keys] over its [ShortcutLayout.base]'s: the shortcut store's own
/// document, holding it as one of the user's — what was recorded over it
/// among its own keys, so the file holds no overrides.
String shortcutPresetSettingsFile(
  ShortcutLayout preset, {
  required String name,
  required Map<String, List<SingleActivator>> keys,
}) => encodeSettingsFile({
  ShortcutSettingsStore.fileName: versionedSettingsDocument(
    ShortcutSettingsStore.version,
    {
      _command: _commandHere(),
      'presets': [
        _presetJson(
          UserShortcutPreset(
            id: preset.id,
            name: name,
            base: preset.base,
            keys: keys,
          ),
        ),
      ],
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
    final lifted = liftVersionedSettingsDocument(
      document,
      version: ShortcutSettingsStore.version,
      fromJson: ShortcutSettingsStore._inThisShape,
    );
    final listed = lifted?['presets'];
    if (listed is! List) {
      return null;
    }
    return [
      for (final json in listed)
        ?_userPresetFromJson(
          json,
          recordedById: const {},
          keeps: keeps,
          pressed: pressedHere(lifted),
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
ShortcutPreset _shippedPresetNamed(Object? name) =>
    ShortcutPreset.named(name) ?? ShortcutPreset.anicel;

/// One of the user's presets out of its saved [json], with what was
/// recorded under it out of [recordedById], each key as it is [pressed]
/// here; null where [json] is none. An action [keeps] declines is dropped.
UserShortcutPreset? _userPresetFromJson(
  Object? json, {
  required Map<Object?, Object?> recordedById,
  required bool Function(String actionId) keeps,
  required SingleActivator Function(SingleActivator) pressed,
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
      base: _shippedPresetNamed(base),
      keys: _shortcutKeysFromJson(keys, keeps, pressed),
      recorded: {..._shortcutKeysFromJson(recordedById[id], keeps, pressed)},
    );
  }
  return null;
}

/// One layout's keys out of their saved [json], each as it is [pressed]
/// here ([pressedHere]) — an action [keeps] declines and a malformed entry
/// dropped.
Map<String, List<SingleActivator>> _shortcutKeysFromJson(
  Object? json,
  bool Function(String actionId) keeps,
  SingleActivator Function(SingleActivator) pressed,
) => {
  for (final (actionId, listJson) in _keptEntries(json, keeps))
    if (listJson is List)
      actionId: List.unmodifiable([
        for (final activatorJson in listJson)
          if (singleActivatorFromJson(activatorJson) case final activator?)
            pressed(activator),
      ]),
};

/// The touch gestures out of their saved [json]: a gesture by its name, or
/// null for an action deliberately unbound — an action [keeps] declines
/// and a name no gesture has dropped.
Map<String, TouchGesture?> _touchGesturesFromJson(
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
