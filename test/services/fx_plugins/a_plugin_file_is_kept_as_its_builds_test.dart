import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_bundle.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// I-132: an fx plugin's file (anicel_fx_plugin.h, THE FILE) read for each
/// device — its module everywhere, the native build of that device's own
/// where the file has one — and kept on this device as those builds, under
/// names the library mints, with what the plugin said of itself.
void main() {
  final module = Uint8List.fromList([0, 0x61, 0x73, 0x6D, 1, 0, 0, 0]);
  final windows = Uint8List.fromList([0x4D, 0x5A, 1]);
  final mac = Uint8List.fromList([0xCF, 0xFA, 2]);

  Uint8List fileOf(Map<String, Uint8List> entries) {
    final archive = Archive();
    for (final MapEntry(:key, :value) in entries.entries) {
      archive.add(ArchiveFile.bytes(key, value));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  final both = fileOf({
    'plugin.wasm': module,
    'native/windows-x64.dll': windows,
    'native/macos.dylib': mac,
  });

  group('a plugin file', () {
    test('gives each device its own native build', () {
      final onWindows = readFxPluginBundle(both, abi: Abi.windowsX64)!;
      expect(onWindows.wasm, module);
      expect(onWindows.native, windows);
      expect(readFxPluginBundle(both, abi: Abi.macosArm64)!.native, mac);
      expect(readFxPluginBundle(both, abi: Abi.macosX64)!.native, mac);
    });

    test('gives the module alone where it has no build for the device', () {
      for (final abi in [Abi.linuxX64, Abi.windowsArm64, Abi.androidArm64]) {
        final bundle = readFxPluginBundle(both, abi: abi)!;
        expect(bundle.wasm, module);
        expect(bundle.native, isNull, reason: '$abi');
      }
    });

    test('is no plugin without its module, or as no zip', () {
      expect(
        readFxPluginBundle(fileOf({'native/windows-x64.dll': windows})),
        isNull,
      );
      expect(readFxPluginBundle(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  group('the library', () {
    late Directory room;
    late FxPluginLibraryService library;

    setUp(() {
      room = Directory.systemTemp.createTempSync('anicel_fx_plugins_');
      library = FxPluginLibraryService(directoryPath: '${room.path}/fx');
    });
    tearDown(() => deleteTempQuietly(room));

    final description = FxPluginDescription.read(
      jsonEncode({
        'spec': 1,
        'id': 'com.example.invert',
        'name': 'Invert',
        'vendor': 'Example',
        'version': '1.0.0',
        'can': ['cpu'],
        'params': [
          {'id': 'map', 'kind': 'layer', 'label': 'Map'},
        ],
      }),
    )!;

    test('nothing installed is no plugins — no folder, no error', () async {
      expect(await library.loadIndex(), isEmpty);
      expect(Directory(library.directoryPath).existsSync(), isFalse);
    });

    test('keeps the builds under names of its own, and reads them back by '
        'what the index says', () async {
      final kept = await library.keep(
        readFxPluginBundle(both, abi: Abi.windowsX64)!,
        description,
        abi: Abi.windowsX64,
      );
      expect(kept.wasm, endsWith('com.example.invert.wasm'));
      expect(kept.native, endsWith('com.example.invert.dll'));
      expect(isFxPluginLibraryFileName(kept.wasm), isTrue);
      await library.saveIndex([kept]);

      final again = FxPluginLibraryService(
        directoryPath: library.directoryPath,
      );
      final [read] = await again.loadIndex();
      expect((read.wasm, read.native), (kept.wasm, kept.native));
      expect(read.description.toJson(), description.toJson());
      expect(await again.read(read.wasm), module);
      expect(await again.read(read.native!), windows);
    });

    test('a second install of one plugin is files of its own', () async {
      final bundle = readFxPluginBundle(both, abi: Abi.androidArm64)!;
      final first = await library.keep(bundle, description);
      final second = await library.keep(bundle, description);
      expect(second.wasm, isNot(first.wasm));
      await library.delete(first);
      expect(await library.read(first.wasm), isNull);
      expect(await library.read(second.wasm), module);
    });

    test('a device without a native build keeps the module alone', () async {
      final kept = await library.keep(
        readFxPluginBundle(both, abi: Abi.androidArm64)!,
        description,
        abi: Abi.androidArm64,
      );
      expect(kept.native, isNull);
    });

    test('an index naming a path, or a file no build is, is no plugin', () async {
      final kept = await library.keep(
        readFxPluginBundle(both, abi: Abi.windowsX64)!,
        description,
        abi: Abi.windowsX64,
      );
      final entry = {
        'wasm': kept.wasm,
        'native': kept.native,
        'description': description.toJson(),
      };
      File(library.indexPath).writeAsStringSync(
        jsonEncode({
          'version': FxPluginLibraryService.indexVersion,
          'plugins': [
            {...entry, 'wasm': '../escape.wasm'},
            {...entry, 'wasm': 'a1-notes.txt'},
            {...entry, 'native': '../../escape.dll'},
            {...entry, 'description': {'spec': 2}},
            entry,
          ],
        }),
      );
      final plugins = await library.loadIndex();
      expect([for (final plugin in plugins) plugin.wasm], [kept.wasm]);
      expect(library.pathOf('../escape.wasm'), isNull);
      expect(await library.read('../escape.wasm'), isNull);
    });
  });
}
