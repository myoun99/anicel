import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/services/fx_plugins/fx_plugin_bundle.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fx_plugin_file.dart';
import '../../helpers/temp_dir.dart';

/// I-132, fx spec 2: an fx plugin's file — its WGSL and its description,
/// one build for every device — and kept on this device as its WGSL,
/// under a name the library mints, with what the plugin said of itself.
void main() {
  const source = '// the plugin\n';
  final description = fxPluginDescriptionOf(
    'com.example.invert',
    params: [
      {'id': 'map', 'kind': 'layer', 'label': 'Map'},
    ],
  );

  group('a plugin file', () {
    test('holds its WGSL and its description', () {
      final bundle = readFxPluginBundle(
        fxPluginFileOf(description, source: source),
      )!;
      expect(bundle.source, source);
      expect(bundle.description, description);
    });

    test('is no plugin without either, as no zip, or with an entry no '
        'UTF-8', () {
      expect(
        readFxPluginBundle(fxPluginFileOf(description, withoutSource: true)),
        isNull,
      );
      expect(
        readFxPluginBundle(
          fxPluginFileOf(description, withoutDescription: true),
        ),
        isNull,
      );
      expect(readFxPluginBundle(Uint8List.fromList([1, 2, 3, 4])), isNull);
      final notText = ZipEncoder().encodeBytes(
        Archive()
          ..add(ArchiveFile.bytes(fxPluginSourceEntry, [0x66, 0xFF, 0x6E]))
          ..add(
            ArchiveFile.bytes(
              fxPluginDescriptionEntry,
              utf8.encode(jsonEncode(description.toJson())),
            ),
          ),
      );
      expect(readFxPluginBundle(notText), isNull);
    });

    test('is no plugin where its description is of spec 1', () {
      final spec1 = {...description.toJson(), 'spec': 1, 'can': ['cpu']};
      final file = ZipEncoder().encodeBytes(
        Archive()
          ..add(ArchiveFile.bytes(fxPluginSourceEntry, utf8.encode(source)))
          ..add(
            ArchiveFile.bytes(
              fxPluginDescriptionEntry,
              utf8.encode(jsonEncode(spec1)),
            ),
          ),
      );
      expect(readFxPluginBundle(file), isNull);
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

    FxPluginBundle bundle() => readFxPluginBundle(
      fxPluginFileOf(description, source: source),
    )!;

    test('nothing installed is no plugins — no folder, no error', () async {
      expect(await library.loadIndex(), isEmpty);
      expect(Directory(library.directoryPath).existsSync(), isFalse);
    });

    test('keeps the WGSL under a name of its own, and reads it back by '
        'what the index says', () async {
      final kept = await library.keep(bundle());
      expect(kept.source, endsWith('com.example.invert.wgsl'));
      expect(isFxPluginLibraryFileName(kept.source), isTrue);
      await library.saveIndex([kept]);

      final again = FxPluginLibraryService(
        directoryPath: library.directoryPath,
      );
      final [read] = await again.loadIndex();
      expect(read.source, kept.source);
      expect(read.description, description);
      expect(utf8.decode((await again.read(read.source))!), source);
      expect(
        File(again.pathOf(read.source)!).readAsStringSync(),
        source,
        reason: 'what the opener reads it from',
      );
    });

    test('a second install of one plugin is a file of its own', () async {
      final first = await library.keep(bundle());
      final second = await library.keep(bundle());
      expect(second.source, isNot(first.source));
      await library.delete(first);
      expect(await library.read(first.source), isNull);
      expect(utf8.decode((await library.read(second.source))!), source);
    });

    test('an index naming a path, or a file no WGSL is, is no '
        'plugin', () async {
      final kept = await library.keep(bundle());
      final entry = {
        'source': kept.source,
        'description': description.toJson(),
      };
      File(library.indexPath).writeAsStringSync(
        jsonEncode({
          'version': FxPluginLibraryService.indexVersion,
          'plugins': [
            {...entry, 'source': '../escape.wgsl'},
            {...entry, 'source': 'a1-notes.txt'},
            {...entry, 'source': 'old.wasm'},
            {...entry, 'description': {'spec': 1}},
            entry,
          ],
        }),
      );
      final plugins = await library.loadIndex();
      expect([for (final plugin in plugins) plugin.source], [kept.source]);
      expect(library.pathOf('../escape.wgsl'), isNull);
      expect(await library.read('../escape.wgsl'), isNull);
    });

    test('an index of spec 1 — a module and a native build — is no '
        'plugins', () async {
      File(library.indexPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'version': 1,
            'plugins': [
              {
                'wasm': 'com.example.invert.wasm',
                'native': 'com.example.invert.dll',
                'description': {
                  ...description.toJson(),
                  'spec': 1,
                  'can': ['cpu'],
                },
              },
            ],
          }),
        );
      expect(await library.loadIndex(), isEmpty);
    });
  });
}
