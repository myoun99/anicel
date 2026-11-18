import 'dart:convert';
import 'dart:typed_data';

import '../../models/fx_plugin_description.dart';
import '../../models/media_asset.dart' show isOneStoredName, mintMediaCarry;
import '../persistence/app_support_path.dart';
import '../persistence/named_file_folder.dart';
import '../persistence/versioned_settings_file.dart';
import 'fx_plugin_bundle.dart';

/// One fx plugin installed on this device: the name its WGSL is kept
/// under, and what it said of itself when it was installed.
typedef InstalledFxPlugin = ({String source, FxPluginDescription description});

/// Reads and writes THE FX PLUGINS INSTALLED ON THIS DEVICE (I-132): a
/// folder of their WGSL, kept under names the library mints, and a small
/// index of what each said of itself — the font library's layout
/// (`FontLibraryService`), for its reason: the list of plugins is shown
/// without opening one, and a plugin is opened on the device only when it
/// is installed or first run.
///
/// Plugins here are this DEVICE's, for ever (the settings room, beside the
/// fonts). What of one a project keeps is that project's business — its
/// description ([FxPluginDescription.toJson], 🗣️I-132-Q28).
class FxPluginLibraryService {
  FxPluginLibraryService({String? directoryPath})
    : directoryPath = directoryPath ?? defaultFxPluginDirectoryPath();

  /// Folder holding `index.json` and the plugins' WGSL.
  final String directoryPath;

  /// ⚠️Sandboxed under `FLUTTER_TEST`, as the fonts are: a widget test
  /// reaches this library through the production wiring.
  static String defaultFxPluginDirectoryPath() =>
      testRedirectedAppSettingsPath('fx_plugins', sandbox: 'fx_plugins');

  /// Index file format version: 2, a plugin's WGSL (fx spec 2). ↩️1 named a
  /// module and a native build — read as no plugins (no production data).
  static const int indexVersion = 2;

  String get indexPath => '$directoryPath/index.json';

  /// The folder, holding the WGSL under names of its own
  /// ([isFxPluginLibraryFileName]) — nothing is kept, read or deleted under
  /// another ([NamedFileFolder.pathOf], board `law-저장`).
  NamedFileFolder get _folder =>
      NamedFileFolder(directoryPath, isName: isFxPluginLibraryFileName);

  /// Where the library keeps a file called [file] — null where [file] is
  /// not a name of its own. What a plugin's WGSL is read from to open it.
  String? pathOf(String file) => _folder.pathOf(file);

  /// The installed plugins, in the order they were installed. A missing or
  /// unreadable index is no plugins, never an error; an entry whose
  /// description no longer reads is no plugin.
  Future<List<InstalledFxPlugin>> loadIndex() async =>
      await loadVersionedSettings(
        filePath: indexPath,
        version: indexVersion,
        fromJson: (json) => [
          for (final entry in json['plugins'] as List<dynamic>)
            ?_installedOf(entry),
        ],
      ) ??
      const [];

  /// [entry] of the index as one installed plugin — null where it names a
  /// file as the library never would, or its description no longer reads.
  static InstalledFxPlugin? _installedOf(Object? entry) {
    if (entry is! Map<String, Object?>) {
      return null;
    }
    final description = FxPluginDescription.fromJson(entry['description']);
    return switch (entry['source']) {
      final String source
          when description != null && isFxPluginLibraryFileName(source) =>
        (source: source, description: description),
      _ => null,
    };
  }

  Future<void> saveIndex(List<InstalledFxPlugin> plugins) =>
      saveVersionedSettings(
        filePath: indexPath,
        version: indexVersion,
        json: {
          'plugins': [
            for (final plugin in plugins)
              {
                'source': plugin.source,
                'description': plugin.description.toJson(),
              },
          ],
        },
      );

  /// Writes [bundle]'s WGSL under a name minted for its plugin. The caller
  /// owns the index; this only puts the file on disk.
  Future<InstalledFxPlugin> keep(FxPluginBundle bundle) async {
    final id = bundle.description.id;
    final stem = mintMediaCarry(
      '$directoryPath/'
      '${id.length > _idLettersKept ? id.substring(0, _idLettersKept) : id}',
    );
    final source = '$stem.wgsl';
    await _folder.write(source, utf8.encode(bundle.source));
    return (source: source, description: bundle.description);
  }

  /// The bytes of [file], or null when it is gone or unreadable — a plugin
  /// that cannot be read is a plugin this device does not have.
  Future<Uint8List?> read(String file) => _folder.read(file);

  /// Removes [plugin]'s file — the index has dropped it, so what will not
  /// delete is read by nothing.
  Future<void> delete(InstalledFxPlugin plugin) =>
      _folder.delete(plugin.source);
}

/// How much of a plugin's id rides in its files' names: enough to tell two
/// apart in the folder, never enough to make a path too long to open.
const int _idLettersKept = 40;

/// Whether [file] is a name a plugin's WGSL can be kept under — the only
/// names the library reads, writes and deletes: ONE NAME, WITH NOTHING OF
/// A PATH IN IT ([isOneStoredName], board `law-저장`), ending as WGSL does.
bool isFxPluginLibraryFileName(String file) =>
    file.length <= _longestName &&
    isOneStoredName(file) &&
    file.endsWith('.wgsl');

/// Longer than any name this library mints.
const int _longestName = 120;
