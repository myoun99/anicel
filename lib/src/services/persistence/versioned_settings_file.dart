/// Reading and writing the app's own settings files — the small versioned
/// JSON documents beside the project data, not project data itself.
///
/// ⛔TWELVE STORES WROTE THIS OUT. The exists check, the decode, the
/// version gate and the catch-everything were copied per settings kind,
/// which is twelve places for one of them to start THROWING where its
/// neighbours return the defaults — and a settings file that cannot be
/// read must never stop the app from starting.
library;

import 'dart:convert';
import 'dart:io';

/// The document in [filePath], or null when it is missing, unreadable, or
/// stamped with a version this build does not know.
///
/// ⚠️Null means "use the defaults", for every reason at once, ON PURPOSE:
/// a corrupt settings file and a missing one are the same situation to
/// every caller, and telling them apart would only invite one of them to
/// be handled and the other forgotten.
///
/// ⚠️The exists check is a FAST PATH, not the thing that answers null: a
/// missing file is the ordinary first-run case and reading one throws, so
/// the catch below would answer null without it. Measured 2026-09-05 — a
/// mutant that deletes the check survives, which is why this says so
/// rather than leaving the next reader to decide it is redundant.
Future<T?> loadVersionedSettings<T>({
  required String filePath,
  required int version,
  required T? Function(Map<String, dynamic> json) fromJson,
}) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if ((decoded['version'] as int? ?? 0) > version) {
      return null;
    }
    return fromJson(decoded);
  } on Object {
    return null;
  }
}

/// Writes [json] to [filePath] under [version], creating the directory.
Future<void> saveVersionedSettings({
  required String filePath,
  required int version,
  required Map<String, dynamic> json,
}) async {
  final file = File(filePath);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode({'version': version, ...json}));
}

/// [loadVersionedSettings] without the await.
///
/// ⛔A SEPARATE FUNCTION, NOT A FLAG. Two stores read synchronously on
/// purpose — the export settings because widget tests drive the dialog
/// that reads them, the recent list because the launcher shows it before
/// anything is awaited — and a `sync: true` argument would make one
/// function answer "what does it read" and "when does it return" at once.
T? loadVersionedSettingsSync<T>({
  required String filePath,
  required int version,
  required T? Function(Map<String, dynamic> json) fromJson,
}) {
  try {
    final file = File(filePath);
    if (!file.existsSync()) {
      return null;
    }
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    if ((decoded['version'] as int? ?? 0) > version) {
      return null;
    }
    return fromJson(decoded);
  } on Object {
    return null;
  }
}
