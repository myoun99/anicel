import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'app_support_path.dart';
import 'settings_file.dart';

/// The settings room's entries ([appSettingsEntries]) that stay on this
/// machine when every setting leaves as one file (I-142).
///
/// 🗣️I-142-Q2 (유저 2026-10-29): 「기계에 묶인 넷은 넣지 않는다」 — the
/// recent projects (paths on this disk), the window (this screen), the
/// memory budget (this machine's memory) and the fonts (installed here).
const Set<String> settingsBoundToThisMachine = {
  'recent_projects.json',
  'window.json',
  'memory_settings.json',
  'fonts',
};

/// The settings room's entries that leave in the whole-settings file —
/// every one but [settingsBoundToThisMachine].
final List<String> travellingSettingsEntries = List.unmodifiable([
  for (final entry in appSettingsEntries)
    if (!settingsBoundToThisMachine.contains(entry)) entry,
]);

/// Where the settings room keeps [entry] — the room itself
/// ([appSettingsFilePath]), or a sandbox under a test, which must not read
/// or write the developer's own settings.
String settingsRoomPath(String entry) =>
    testRedirectedAppSettingsPath(entry, sandbox: 'settings_room');

/// The settings file of [entries] as they stand in the room, [at] each
/// entry's place ([settingsRoomPath]): an entry that is a `.json` file its
/// document, and one that is a folder each of its files — a `.json` its
/// document, any other its bytes — under `<entry>/<name>`.
///
/// ⚠️An entry with nothing in the room is left out: no store has written it,
/// so it holds its defaults. A document that is no JSON object is left out
/// too — its store reads it as its defaults.
Future<String> settingsFileOfTheRoom(
  Iterable<String> entries, {
  String Function(String entry) at = settingsRoomPath,
}) async {
  final documents = <String, Map<String, dynamic>>{};
  final files = <String, Uint8List>{};
  Future<void> take(String name, File file) async {
    if (!name.endsWith('.json')) {
      files[name] = await file.readAsBytes();
    } else if (_documentOf(await file.readAsString()) case final document?) {
      documents[name] = document;
    }
  }

  for (final entry in entries) {
    final path = at(entry);
    if (await File(path).exists()) {
      await take(entry, File(path));
    } else if (await Directory(path).exists()) {
      final inside = [
        ...(await Directory(path).list().toList()).whereType<File>(),
      ]..sort((a, b) => a.path.compareTo(b.path));
      for (final file in inside) {
        await take('$entry/${file.uri.pathSegments.last}', file);
      }
    }
  }
  return encodeSettingsFile(documents, files: files);
}

Map<String, dynamic>? _documentOf(String text) {
  try {
    return switch (jsonDecode(text)) {
      final Map<String, dynamic> document => document,
      _ => null,
    };
  } on FormatException {
    return null;
  }
}
