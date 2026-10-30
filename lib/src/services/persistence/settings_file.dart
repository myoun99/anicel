/// Anicel's own settings file (I-142): some of the app's settings
/// documents, each as its store writes it (`versionedSettingsDocument`),
/// under the store's own file name (`appSettingsEntries`).
///
/// 🗣️I-142-Q5 (유저 2026-10-29): 「우리 형식이라기보다 뭔가 json? … 최대한
/// 최신식인 저장형식 뭐 가벼운거? 그런건 맡김」 — the settings are small
/// JSON documents already, so the file is those documents, as they are.
///
/// ★ONE FORMAT FOR ONE AND FOR ALL. A palette or a shortcut preset leaves
/// as its store's document holding just it, and the whole settings leave
/// as every store's — so each kind is read by the one decoder its store
/// reads its own file with, whether the file holds one thing or all.
/// What the file is FOR — something to add, or the settings to put in
/// place — its name says ([anicelPaletteExtension] ·
/// [anicelShortcutExtension] · [anicelSettingsExtension]), the way every
/// door tells a file.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The extension of a file holding one colour palette.
const String anicelPaletteExtension = 'anipalette';

/// The extension of a file holding one shortcut preset.
const String anicelShortcutExtension = 'anishortcut';

/// The extension of a file holding every setting that travels — the
/// preferences window's 「설정 전부 내보내기」 (I-142-Q1).
const String anicelSettingsExtension = 'anisettings';

/// The format's version.
///
/// ⚠️A reader refuses a HIGHER one, as the brush pack's does: each document
/// keeps its store's own version beside it, and this one is for the
/// envelope.
const int settingsFileVersion = 1;

/// What a settings file holds: its [documents] by their stores' file names,
/// the other [files] of an entry that is a folder — the brush tips'
/// pictures — by their names under the settings room (`brush_tips/<id>.png`),
/// and the entries it holds [atDefaults]: ones its settings room held
/// nothing of, which is what each store reads as its defaults.
///
/// 🗣️I-142-Q3 (유저 2026-10-29): 「전부 갈아끼운다」 — 「통째로 바뀐다(백업
/// 복원처럼)」. ↩️A setting at its defaults used to be left out of the file
/// as nothing to say (10-29), so one changed after the export stayed changed
/// when the file was read back: the hands-on verify's accent colour.
typedef SettingsFile = ({
  Map<String, Map<String, dynamic>> documents,
  Map<String, Uint8List> files,
  Set<String> atDefaults,
});

/// [documents], by their stores' file names, [files] and the entries
/// [atDefaults] as a settings file's text.
String encodeSettingsFile(
  Map<String, Map<String, dynamic>> documents, {
  Map<String, Uint8List> files = const {},
  Set<String> atDefaults = const {},
}) => jsonEncode({
  'anicelSettings': settingsFileVersion,
  'documents': documents,
  if (files.isNotEmpty)
    'files': {
      for (final MapEntry(:key, :value) in files.entries)
        key: base64Encode(value),
    },
  if (atDefaults.isNotEmpty) 'atDefaults': [...atDefaults]..sort(),
});

/// The documents [source] holds by their stores' file names, or null where
/// it is no settings file this build reads.
Map<String, Map<String, dynamic>>? decodeSettingsFile(String source) =>
    readSettingsFile(source)?.documents;

/// What [source] holds ([SettingsFile]), or null where it is no settings
/// file this build reads. What is no document, or no file's bytes, is
/// left out.
SettingsFile? readSettingsFile(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    return null;
  }
  if (decoded case {
    'anicelSettings': final int version,
    'documents': final Map<String, dynamic> documents,
  } when version <= settingsFileVersion) {
    return (
      documents: {
        for (final MapEntry(:key, :value) in documents.entries)
          if (value is Map<String, dynamic>) key: value,
      },
      files: {
        if (decoded['files'] case final Map<String, dynamic> files)
          for (final MapEntry(:key, :value) in files.entries)
            if (value is String) key: ?_bytesOf(value),
      },
      atDefaults: {
        if (decoded['atDefaults'] case final List<dynamic> entries)
          for (final entry in entries)
            if (entry is String) entry,
      },
    );
  }
  return null;
}

Uint8List? _bytesOf(String base64) {
  try {
    return base64Decode(base64);
  } on FormatException {
    return null;
  }
}
