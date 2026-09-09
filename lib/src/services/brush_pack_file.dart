import 'dart:convert';

import '../models/brush_hand_settings.dart';
import '../models/brush_preset.dart';

/// The extension of a brush file Anicel writes itself.
const String anicelBrushExtension = 'anibrush';

/// Anicel's OWN brush file — the format the app exports brushes in.
///
/// 🚨유저 확정 (`brush-export-format-Q1`, 답 1, 2026-09-08): our own format,
/// nothing lost. ⛔The `.sut` option was refused by the user in the same
/// breath — 「애초에 sut로 내보내기가 클튜나 법적으로? 문제있지않을까 생각」 —
/// and writing a competitor's undocumented container would also mean throwing
/// away every setting Clip Studio has no column for.
///
/// ⚠️THE MASKS TRAVEL INLINE, unlike the app's own preset library, which
/// stores tip ids and resolves them out of the tip library on load. A file
/// that leaves this machine has no tip library to resolve against, so
/// `BrushPreset.toJson` — which embeds them — is exactly the right encoder
/// here and the library's id-swapping is the special case, not this.
///
/// ⚠️AND THE HAND SETTINGS TRAVEL WITH THEM. 유저 (`Q-brush-store`): 「앱
/// 안에서는 앱 저장소에 두되 내보낼 때는 브러시 파일에 쓴다」, and again on
/// 2026-09-08: 「불투명도든 뭐든 손설정이든 정한거 싹 다 내보낼때 나르도록
/// 하고싶음」. A brush someone shares should carry the size they were using
/// when they shared it.
/// ⛔THE GROUP IS NOT IN HERE, and that is measured rather than forgotten:
/// `mergeImportedBrushPresets` puts every imported brush into a group named
/// after the SOURCE FILE, whatever the file says — one import law for all
/// three formats. The group travels as the file's NAME instead, which the
/// exporter sets to the group's name, so 「브러시 그룹 내보내기」 arrives as a
/// group of that name on the other side. A `groups` key would be data the
/// importer is contractually unable to honour.
class BrushPack {
  const BrushPack({required this.presets, this.handSettings = const {}});

  final List<BrushPreset> presets;

  /// Keyed by preset id. ⚠️Ids SURVIVE an import — the merge replaces on a
  /// collision rather than re-minting (two presets may never share an id) —
  /// so these keys are the same ids the receiving library will hold.
  final Map<String, BrushHandSettings> handSettings;
}

/// Thrown when a file cannot be read as an Anicel brush pack.
class BrushPackFormatException implements Exception {
  const BrushPackFormatException(this.message);

  final String message;

  @override
  String toString() => 'BrushPackFormatException: $message';
}

/// The format's version.
///
/// ⚠️A reader refuses a HIGHER version rather than guessing: a pack written
/// by a newer Anicel may carry settings this build would silently drop, and
/// a brush that arrives quietly wrong is worse than one that does not
/// arrive. Older versions stay readable — nothing has been removed yet.
const int brushPackVersion = 1;

String encodeBrushPack(BrushPack pack) => jsonEncode({
  'anicelBrushPack': brushPackVersion,
  'presets': [for (final preset in pack.presets) preset.toJson()],
  if (pack.handSettings.isNotEmpty)
    'handSettings': brushHandSettingsBankToJson(pack.handSettings),
});

BrushPack decodeBrushPack(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const BrushPackFormatException(
      'This file is not readable as an Anicel brush file.',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const BrushPackFormatException(
      'This file is not readable as an Anicel brush file.',
    );
  }
  final version = decoded['anicelBrushPack'];
  if (version is! int) {
    throw const BrushPackFormatException(
      'This file is not an Anicel brush file.',
    );
  }
  if (version > brushPackVersion) {
    throw BrushPackFormatException(
      'This brush file was written by a newer version of Anicel '
      '(format $version); this build reads up to $brushPackVersion.',
    );
  }
  final presetsJson = decoded['presets'];
  if (presetsJson is! List || presetsJson.isEmpty) {
    throw const BrushPackFormatException(
      'This brush file contains no brushes.',
    );
  }
  final List<BrushPreset> presets;
  final Map<String, BrushHandSettings> hand;
  try {
    presets = [
      for (final entry in presetsJson)
        BrushPreset.fromJson(entry as Map<String, dynamic>),
    ];
    final handJson = decoded['handSettings'];
    hand = brushHandSettingsBankFromJson(
      handJson is Map<String, dynamic> ? handJson : null,
    );
  } on Object {
    // ⚠️Deliberately wide: every model constructor in here validates and
    // throws its own type, and what the user needs to hear is the same
    // sentence for all of them.
    throw const BrushPackFormatException(
      'This brush file is damaged and could not be read.',
    );
  }
  return BrushPack(presets: presets, handSettings: hand);
}
