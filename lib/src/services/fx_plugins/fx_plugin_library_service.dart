import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import '../../models/fx_plugin_description.dart';
import '../../models/media_asset.dart' show isOneStoredName, mintMediaCarry;
import '../persistence/app_support_path.dart';
import '../persistence/versioned_settings_file.dart';
import 'fx_plugin_bundle.dart';

/// One fx plugin installed on this device: the names its module and its
/// native build (where it has one for this device) are kept under, and
/// what it said of itself when it was installed.
typedef InstalledFxPlugin = ({
  String wasm,
  String? native,
  FxPluginDescription description,
});

/// Reads and writes THE FX PLUGINS INSTALLED ON THIS DEVICE (I-132): a
/// folder of their builds, kept under names the library mints, and a small
/// index of what each said of itself — the font library's layout
/// (`FontLibraryService`), for its reason: the list of plugins is shown
/// without opening one, and a description is asked of a plugin only when
/// it is installed.
///
/// Plugins here are this DEVICE's, for ever (the settings room, beside the
/// fonts). What of one a project keeps is that project's business — its
/// description ([FxPluginDescription.toJson], 🗣️I-132-Q28).
class FxPluginLibraryService {
  FxPluginLibraryService({String? directoryPath})
    : directoryPath = directoryPath ?? defaultFxPluginDirectoryPath();

  /// Folder holding `index.json` and the plugins' builds.
  final String directoryPath;

  /// ⚠️Sandboxed under `FLUTTER_TEST`, as the fonts are: a widget test
  /// reaches this library through the production wiring.
  static String defaultFxPluginDirectoryPath() =>
      testRedirectedAppSettingsPath('fx_plugins', sandbox: 'fx_plugins');

  /// Index file format version.
  static const int indexVersion = 1;

  String get indexPath => '$directoryPath/index.json';

  /// Where the library keeps a file called [file] — null where [file] is
  /// not a name of its own ([isFxPluginLibraryFileName]). ⛔THE ONE LINE
  /// THAT JOINS THE FOLDER AND A NAME IT WAS HANDED (board `law-저장`):
  /// what the index says reaches the disk through here or not at all.
  String? pathOf(String file) =>
      isFxPluginLibraryFileName(file) ? '$directoryPath/$file' : null;

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
    return switch ((entry['wasm'], entry['native'])) {
      (final String wasm, final String? native)
          when description != null &&
              isFxPluginLibraryFileName(wasm) &&
              (native == null || isFxPluginLibraryFileName(native)) =>
        (wasm: wasm, native: native, description: description),
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
                'wasm': plugin.wasm,
                'native': ?plugin.native,
                'description': plugin.description.toJson(),
              },
          ],
        },
      );

  /// Writes [bundle]'s builds under names minted for [description]'s
  /// plugin — the module, and the native build for [abi] (this device's
  /// where none is named) where the bundle has one. The caller owns the
  /// index; this only puts the files on disk.
  Future<InstalledFxPlugin> keep(
    FxPluginBundle bundle,
    FxPluginDescription description, {
    Abi? abi,
  }) async {
    final id = description.id;
    final stem = mintMediaCarry(
      '$directoryPath/'
      '${id.length > _idLettersKept ? id.substring(0, _idLettersKept) : id}',
    );
    final wasm = '$stem.wasm';
    await _write(wasm, bundle.wasm);
    final nativeBytes = bundle.native;
    final entry = fxPluginNativeEntryFor(abi ?? Abi.current());
    String? native;
    if (nativeBytes != null && entry != null) {
      native = '$stem.${entry.split('.').last}';
      await _write(native, nativeBytes);
    }
    return (wasm: wasm, native: native, description: description);
  }

  /// The bytes of [file], or null when it is gone or unreadable — a plugin
  /// that cannot be read is a plugin this device does not have.
  Future<Uint8List?> read(String file) async {
    final path = pathOf(file);
    if (path == null) {
      return null;
    }
    try {
      return await File(path).readAsBytes();
    } on Object {
      return null;
    }
  }

  /// Removes [plugin]'s files. A file that will not delete stays on disk;
  /// the index has dropped it, so nothing reads it.
  Future<void> delete(InstalledFxPlugin plugin) async {
    for (final file in [plugin.wasm, ?plugin.native]) {
      final path = pathOf(file);
      if (path == null) {
        continue;
      }
      try {
        final target = File(path);
        if (await target.exists()) {
          await target.delete();
        }
      } on Object {
        // Left on disk, read by nothing.
      }
    }
  }

  Future<void> _write(String file, Uint8List bytes) async {
    final path = pathOf(file);
    if (path == null) {
      throw ArgumentError.value(file, 'file', 'is not a name of the library');
    }
    final target = File(path);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
  }
}

/// How much of a plugin's id rides in its files' names: enough to tell two
/// apart in the folder, never enough to make a path too long to open.
const int _idLettersKept = 40;

/// Whether [file] is a name a plugin's build can be kept under — the only
/// names the library reads, writes and deletes: ONE NAME, WITH NOTHING OF
/// A PATH IN IT ([isOneStoredName], board `law-저장`), ending as a module or
/// a native build does.
bool isFxPluginLibraryFileName(String file) =>
    file.length <= _longestName &&
    isOneStoredName(file) &&
    _endsAsAPluginBuild.hasMatch(file);

/// Longer than any name this library mints.
const int _longestName = 120;

final RegExp _endsAsAPluginBuild = RegExp(r'\.(wasm|dll|dylib|so)$');
