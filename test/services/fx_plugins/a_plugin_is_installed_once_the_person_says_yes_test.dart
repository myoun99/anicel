import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// I-132: installing an fx plugin from its file — its module asked who it
/// is, the person shown that and asked, and nothing kept before they say
/// yes; a plugin the device has already replaced where it stood.
///
/// The module is asked through a stand-in here: the engine's own tests
/// hold its sandbox (qa_fx_plugin_test.c).
void main() {
  late Directory room;
  late FxPluginLibraryService library;

  setUp(() {
    room = Directory.systemTemp.createTempSync('anicel_fx_install_');
    library = FxPluginLibraryService(directoryPath: '${room.path}/fx');
  });
  tearDown(() => deleteTempQuietly(room));

  String describing(String id, String version) => jsonEncode({
    'spec': 1,
    'id': id,
    'name': 'Plugin $id',
    'vendor': 'Example',
    'version': version,
    'can': ['cpu'],
    'params': <Object?>[],
  });

  // A file whose module is its description's text — what the stand-in
  // answers with.
  Uint8List fileOf(String description, {bool natives = false}) {
    final archive = Archive()
      ..add(ArchiveFile.bytes('plugin.wasm', utf8.encode(description)));
    if (natives) {
      for (final entry in [
        'native/windows-x64.dll',
        'native/windows-arm64.dll',
        'native/macos.dylib',
        'native/linux-x64.so',
        'native/linux-arm64.so',
      ]) {
        archive.add(ArchiveFile.bytes(entry, utf8.encode(entry)));
      }
    }
    return ZipEncoder().encodeBytes(archive);
  }

  final asked = <({String id, bool native, String? replacing})>[];
  FxPluginConfirm answering(bool yes) =>
      (description, {required native, required replacing}) async {
        asked.add((
          id: description.id,
          native: native,
          replacing: replacing?.version,
        ));
        return yes;
      };
  setUp(asked.clear);

  InstalledFxPlugins plugins({String? refusal}) => InstalledFxPlugins(
    service: library,
    describe: (wasm) => refusal == null
        ? (text: utf8.decode(wasm), refusal: null)
        : (text: null, refusal: refusal),
  );

  test('what is no plugin is said so, and nobody is asked', () async {
    final installed = plugins();
    expect(
      await installed.install(
        Uint8List.fromList([1, 2, 3]),
        confirm: answering(true),
      ),
      isA<FxPluginUnreadable>(),
    );
    expect(
      await installed.install(
        fileOf('{"spec":1}'),
        confirm: answering(true),
      ),
      isA<FxPluginUnreadable>(),
    );
    final unopened = await plugins(refusal: 'no engine here').install(
      fileOf(describing('a.b', '1')),
      confirm: answering(true),
    );
    expect((unopened as FxPluginUnopened).why, 'no engine here');
    expect(asked, isEmpty);
    expect(await library.loadIndex(), isEmpty);
  });

  test('a no keeps nothing', () async {
    final installed = plugins();
    final outcome = await installed.install(
      fileOf(describing('a.b', '1')),
      confirm: answering(false),
    );
    expect(outcome, isA<FxPluginDeclined>());
    expect(asked.single.id, 'a.b');
    expect(installed.plugins, isEmpty);
    expect(await library.loadIndex(), isEmpty);
    expect(Directory(library.directoryPath).existsSync(), isFalse);
  });

  test('a yes keeps it, and the person is told of a native build', () async {
    final installed = plugins();
    var heard = 0;
    installed.addListener(() => heard += 1);
    final outcome = await installed.install(
      fileOf(describing('a.b', '1'), natives: true),
      confirm: answering(true),
    );
    expect((outcome as FxPluginInstalled).description.id, 'a.b');
    expect(outcome.replaced, isNull);
    await installed.install(
      fileOf(describing('c.d', '1')),
      confirm: answering(true),
    );
    expect(asked, [
      (id: 'a.b', native: true, replacing: null),
      (id: 'c.d', native: false, replacing: null),
    ]);
    expect(heard, 2);
    expect([for (final p in installed.plugins) p.description.id], [
      'a.b',
      'c.d',
    ]);

    final again = InstalledFxPlugins(service: library);
    await again.load();
    expect([for (final p in again.plugins) p.description.id], ['a.b', 'c.d']);
  });

  test('a plugin installed again replaces itself where it stood', () async {
    final installed = plugins();
    await installed.install(
      fileOf(describing('a.b', '1')),
      confirm: answering(true),
    );
    await installed.install(
      fileOf(describing('c.d', '1')),
      confirm: answering(true),
    );
    final first = installed.plugins.first;
    final outcome = await installed.install(
      fileOf(describing('a.b', '2')),
      confirm: answering(true),
    );
    expect(asked.last, (id: 'a.b', native: false, replacing: '1'));
    expect((outcome as FxPluginInstalled).replaced?.version, '1');
    expect([
      for (final p in installed.plugins)
        (p.description.id, p.description.version),
    ], [('a.b', '2'), ('c.d', '1')]);
    expect(await library.read(first.wasm), isNull);
    final kept = await library.loadIndex();
    expect(kept.first.description.version, '2');
    expect(
      FxPluginDescription.read(
        utf8.decode((await library.read(kept.first.wasm))!),
      )!.version,
      '2',
    );
  });

  test('a plugin deleted goes off the device, files and all, and the rest '
      'stay as they stood', () async {
    final installed = plugins();
    await installed.install(
      fileOf(describing('a.b', '1'), natives: true),
      confirm: answering(true),
    );
    await installed.install(
      fileOf(describing('c.d', '1')),
      confirm: answering(true),
    );
    final gone = installed.plugins.first;
    var heard = 0;
    installed.addListener(() => heard += 1);

    await installed.uninstall('a.b');

    expect(heard, 1);
    expect([for (final p in installed.plugins) p.description.id], ['c.d']);
    expect(await library.read(gone.wasm), isNull);
    expect(await library.read(gone.native!), isNull);
    expect(await library.read(installed.plugins.single.wasm), isNotNull);
    final again = InstalledFxPlugins(service: library);
    await again.load();
    expect([for (final p in again.plugins) p.description.id], ['c.d']);

    await installed.uninstall('a.b');
    expect(heard, 1, reason: 'one it has not is no change');
  });
}
