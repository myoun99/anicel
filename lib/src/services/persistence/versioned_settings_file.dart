/// Reading and writing the app's own settings files — the small versioned
/// JSON documents beside the project data, not project data itself.
///
/// ⛔TWELVE STORES WROTE THIS OUT. The exists check, the decode, the
/// version gate and the catch-everything were copied per settings kind,
/// which is twelve places for one of them to start THROWING where its
/// neighbours return the defaults — and a settings file that cannot be
/// read must never stop the app from starting.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

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
    return _liftVersionedSettings(
      await file.readAsString(),
      version: version,
      fromJson: fromJson,
    );
  } on Object {
    return null;
  }
}

/// The part of a load that is not IO: decode, version-gate, lift. Shared
/// by both readers the way the SDK's own `readAsString` and
/// `readAsStringSync` share their decode — only the IO half is per colour.
/// Throws on a corrupt document; each shell's catch turns that into null.
T? _liftVersionedSettings<T>(
  String text, {
  required int version,
  required T? Function(Map<String, dynamic> json) fromJson,
}) {
  final decoded = jsonDecode(text) as Map<String, dynamic>;
  if ((decoded['version'] as int? ?? 0) > version) {
    return null;
  }
  return fromJson(decoded);
}

/// Writes [json] to [filePath] under [version], creating the directory.
/// The future completes once the file holds this document or a newer one.
///
/// 🚨★★A SETTINGS FILE HOLDS WHAT WAS SAVED LAST. Two `writeAsString`s
/// into one file promise nothing about the order they finish in, and each
/// truncates before it writes, so two in flight at once interleave and the
/// longer one's tail outlives the shorter. So each file is written ONE AT A
/// TIME, in the order the saves were asked; while one write is on its way,
/// only the NEWEST document waits behind it — a file is written whole, so
/// the ones in between can only ever be overwritten by it.
///
/// ⛔FOUR STORES FOUND THIS ONE AT A TIME and each fixed only itself: the
/// shortcut overrides chained their writes (2026-07-11), the brush preset
/// library queued its own (2026-09-09: a rename landed after the delete
/// that followed it and brought the preset back), the workspace layout
/// chained its (2026-09-26: two writes interleaved into a file no restore
/// could read, and the whole arrangement was lost), and the brush hand
/// bank went synchronous (2026-09-27, F-181: a save of the old bank
/// finished after the reset's and put the forgotten values back). The
/// other settings files had nothing (board
/// `settings-writes-land-out-of-order`). The law lives here now, for every
/// settings file.
///
/// ⚠️Asynchronous ON PURPOSE — the caller does not wait on the disk (see
/// [saveVersionedSettingsSync] for the few that must). Measured 2026-09-30
/// on this Windows machine under load: a synchronous write of 1.2 KB held
/// the calling isolate 1.5 ms at the median and 7 ms at the 99th
/// percentile, and the 30 KB brush preset library 14 ms at the median — a
/// frame, on the UI isolate, per save.
///
/// A write that fails leaves the file as it was and never reaches the
/// caller, whose live state stays valid — settings are best-effort. So does
/// a document JSON cannot hold (a NaN): it is not written at all.
Future<void> saveVersionedSettings({
  required String filePath,
  required int version,
  required Map<String, dynamic> json,
}) {
  final String text;
  try {
    text = _versionedText(version, json);
  } on Object {
    return Future<void>.value();
  }
  return _SettingsFileWrites.of(filePath).save(text);
}

/// [saveVersionedSettings], written before this returns.
///
/// ⛔A SEPARATE FUNCTION, NOT A FLAG, as the readers are. A synchronous
/// write needs no queue — nothing can overtake it — but it holds the
/// calling isolate on the disk, so it is for the stores that have a reason
/// written beside them. ⚠️A file is written in ONE colour: a synchronous
/// write does not wait for an asynchronous one still on its way to the same
/// file.
void saveVersionedSettingsSync({
  required String filePath,
  required int version,
  required Map<String, dynamic> json,
}) {
  try {
    final file = File(filePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_versionedText(version, json));
  } on Object {
    // Best-effort, as the asynchronous writes are.
  }
}

String _versionedText(int version, Map<String, dynamic> json) =>
    jsonEncode({'version': version, ...json});

/// The disk half of an asynchronous save, in place of the real one — a test
/// holds a write open with it to see what waits behind. Null puts the real
/// write back.
@visibleForTesting
set debugSettingsFileWrite(
  Future<void> Function(String filePath, String text)? write,
) => _writeOverride = write;

Future<void> Function(String filePath, String text)? _writeOverride;

Future<void> _writeSettingsFile(String filePath, String text) async {
  final file = File(filePath);
  await file.parent.create(recursive: true);
  await file.writeAsString(text);
}

/// One settings file's writes: the one on its way, and the newest document
/// waiting behind it ([saveVersionedSettings]). One per file, for the run —
/// the app has a handful of settings files.
final class _SettingsFileWrites {
  _SettingsFileWrites._(this._filePath);

  static final Map<String, _SettingsFileWrites> _byFile = {};

  static _SettingsFileWrites of(String filePath) =>
      _byFile.putIfAbsent(filePath, () => _SettingsFileWrites._(filePath));

  final String _filePath;
  String? _waiting;
  Completer<void>? _waitingLanded;
  bool _writing = false;

  Future<void> save(String text) {
    _waiting = text;
    final landed = _waitingLanded ??= Completer<void>();
    if (!_writing) {
      unawaited(_drain());
    }
    return landed.future;
  }

  Future<void> _drain() async {
    _writing = true;
    while (_waiting != null) {
      final text = _waiting!;
      final landed = _waitingLanded!;
      _waiting = null;
      _waitingLanded = null;
      try {
        await (_writeOverride ?? _writeSettingsFile)(_filePath, text);
      } on Object {
        // Best-effort: the file keeps what it had, and the next save runs.
      }
      landed.complete();
    }
    _writing = false;
  }
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
    return _liftVersionedSettings(
      file.readAsStringSync(),
      version: version,
      fromJson: fromJson,
    );
  } on Object {
    return null;
  }
}
