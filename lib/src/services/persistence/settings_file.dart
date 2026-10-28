/// Anicel's own settings file (I-142): some of the app's settings
/// documents, each as its store writes it (`versionedSettingsDocument`),
/// under the store's own file name (`appSettingsEntries`).
///
/// 🗣️I-142-Q5 (유저 2026-10-29): 「우리 형식이라기보다 뭔가 json? … 최대한
/// 최신식인 저장형식 뭐 가벼운거? 그런건 맡김」 — the settings are small
/// JSON documents already, so the file is those documents, as they are.
///
/// ★ONE FORMAT FOR ONE AND FOR ALL. A palette or a shortcut preset leaves
/// as its store's document holding just it, and the whole settings will
/// leave as every store's — so each kind is read by the one decoder its
/// store reads its own file with, whether the file holds one thing or all.
/// What the file is FOR — something to add, or the settings to put in
/// place — its name says ([anicelPaletteExtension] ·
/// [anicelShortcutExtension]), the way every door tells a file.
library;

import 'dart:convert';

/// The extension of a file holding one colour palette.
const String anicelPaletteExtension = 'anipalette';

/// The extension of a file holding one shortcut preset.
const String anicelShortcutExtension = 'anishortcut';

/// The format's version.
///
/// ⚠️A reader refuses a HIGHER one, as the brush pack's does: each document
/// keeps its store's own version beside it, and this one is for the
/// envelope.
const int settingsFileVersion = 1;

/// [documents], by their stores' file names, as a settings file's text.
String encodeSettingsFile(Map<String, Map<String, dynamic>> documents) =>
    jsonEncode({'anicelSettings': settingsFileVersion, 'documents': documents});

/// The documents [source] holds by their stores' file names, or null where
/// it is no settings file this build reads.
Map<String, Map<String, dynamic>>? decodeSettingsFile(String source) {
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
    return {
      for (final MapEntry(:key, :value) in documents.entries)
        if (value is Map<String, dynamic>) key: value,
    };
  }
  return null;
}
