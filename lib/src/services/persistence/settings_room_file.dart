import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'app_support_path.dart';
import 'settings_file.dart';
import 'versioned_settings_file.dart';

/// The settings room's entries ([appSettingsEntries]) that stay on this
/// machine when every setting leaves as one file (I-142).
///
/// 🗣️I-142-Q2 (유저 2026-10-29): 「기계에 묶인 넷은 넣지 않는다」 — the
/// recent projects (paths on this disk), the window (this screen), the
/// memory budget (this machine's memory) and the fonts (installed here).
///
/// ⚖️Two more that came after Q2, each this device's own by what it holds
/// (관제 2026-10-29, the user away — 「판단필요한건 알아서 판단해서
/// 진행해줘」): the launch notice's dismissal (what THIS install was shown)
/// and the usage statistics (I-70: a consent given on this device, the
/// days THIS device was used, which the privacy policy keeps on it, and
/// the events it still has to send).
const Set<String> settingsBoundToThisMachine = {
  'recent_projects.json',
  'window.json',
  'memory_settings.json',
  'fonts',
  'launch_notice.json',
  'usage_stats.json',
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
/// An entry the room gives nothing of — no store has written it, or what it
/// holds is no JSON object — is held [SettingsFile.atDefaults]: its store
/// reads it as its defaults.
///
/// 🗣️I-142-Q3 (유저 2026-10-29): 「전부 갈아끼운다」 — 「통째로 바뀐다(백업
/// 복원처럼)」. ↩️Such an entry was left out as nothing to say (10-29), and a
/// setting changed after the export stayed changed when the file was read
/// back: the hands-on verify's accent colour.
Future<String> settingsFileOfTheRoom(
  Iterable<String> entries, {
  String Function(String entry) at = settingsRoomPath,
}) async {
  final documents = <String, Map<String, dynamic>>{};
  final files = <String, Uint8List>{};
  final atDefaults = <String>{};
  Future<void> take(String name, File file) async {
    if (!name.endsWith('.json')) {
      files[name] = await file.readAsBytes();
    } else if (_documentOf(await file.readAsString()) case final document?) {
      documents[name] = document;
    }
  }

  for (final entry in entries) {
    final path = at(entry);
    final taken = documents.length + files.length;
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
    if (documents.length + files.length == taken) {
      atDefaults.add(entry);
    }
  }
  return encodeSettingsFile(documents, files: files, atDefaults: atDefaults);
}

/// Puts [entries] of [file] in the room, [at] each entry's place, in place of
/// what stood there.
///
/// 🗣️I-142-Q3 (유저 2026-10-29): 「전부 갈아끼운다」 · Q7: 「남기지 않는다」 —
/// an entry that is a document is written as the file holds it, through the
/// queue its store's own saves go by ([saveVersionedSettings]), so a save
/// still on its way lands before it rather than over it; one that is a
/// folder holds the file's files under it, and nothing else; and one the
/// file holds [SettingsFile.atDefaults] holds nothing — a document's file
/// goes in its turn ([removeVersionedSettings]), a folder's files go.
///
/// ⚠️A file names its own entries, so only [entries] the caller asked for
/// are put — and inside a folder only a plain file name: a name that climbs
/// out of the folder, or into one below it, is no file of the folder. An
/// entry the file says nothing of stands as it is.
Future<void> putSettingsIntoTheRoom(
  SettingsFile file,
  Iterable<String> entries, {
  String Function(String entry) at = settingsRoomPath,
}) async {
  for (final entry in entries) {
    final path = at(entry);
    if (file.documents[entry] case final document?) {
      if (document['version'] case final int version) {
        await saveVersionedSettings(
          filePath: path,
          version: version,
          json: document,
        );
      }
    } else if (_folderOf(file, entry) case final inside
        when inside.isNotEmpty) {
      await _fillFolder(path, inside);
    } else if (file.atDefaults.contains(entry)) {
      await (await Directory(path).exists()
          ? _fillFolder(path, const {})
          : removeVersionedSettings(path));
    }
  }
}

/// The folder at [path] holding [inside] by each file's name, and nothing
/// else.
Future<void> _fillFolder(String path, Map<String, List<int>> inside) async {
  final folder = Directory(path);
  if (await folder.exists()) {
    for (final stale in (await folder.list().toList()).whereType<File>()) {
      if (!inside.containsKey(stale.uri.pathSegments.last)) {
        await stale.delete();
      }
    }
  }
  for (final MapEntry(key: name, value: bytes) in inside.entries) {
    final written = File('$path/$name');
    await written.parent.create(recursive: true);
    await written.writeAsBytes(bytes, flush: true);
  }
}

/// What [file] holds under the folder [entry], by each file's plain name.
Map<String, List<int>> _folderOf(SettingsFile file, String entry) {
  final under = '$entry/';
  String? plain(String key) => switch (key.substring(under.length)) {
    final name
        when name.isNotEmpty &&
            !name.contains('/') &&
            !name.contains(r'\') &&
            name != '.' &&
            name != '..' =>
      name,
    _ => null,
  };
  return {
    for (final MapEntry(:key, :value) in file.documents.entries)
      if (key.startsWith(under)) ?plain(key): utf8.encode(jsonEncode(value)),
    for (final MapEntry(:key, :value) in file.files.entries)
      if (key.startsWith(under)) ?plain(key): value,
  };
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
