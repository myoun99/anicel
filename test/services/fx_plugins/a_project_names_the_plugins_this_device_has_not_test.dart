import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// 🗣️I-132-Q28 a: a project keeps the effects of a plugin this device has
/// not — and the device's list says which those are, by the plugin's id
/// whatever its version, each once, wherever in the project it is worn.
void main() {
  late Directory room;
  late FxPluginLibraryService library;

  setUp(() {
    room = Directory.systemTemp.createTempSync('anicel_fx_missing_');
    library = FxPluginLibraryService(directoryPath: '${room.path}/fx');
  });
  tearDown(() => deleteTempQuietly(room));

  FxPluginDescription plugin(String id, {String version = '1'}) =>
      FxPluginDescription.fromJson({
        'spec': 1,
        'id': id,
        'name': 'Plugin $id',
        'vendor': 'Example',
        'version': version,
        'can': ['cpu'],
        'params': <Object?>[],
      })!;

  // A file whose module is its description's text — what the stand-in
  // answers with.
  Uint8List fileOf(FxPluginDescription description) =>
      ZipEncoder().encodeBytes(
        Archive()..add(
          ArchiveFile.bytes(
            'plugin.wasm',
            utf8.encode(jsonEncode(description.toJson())),
          ),
        ),
      );

  Future<InstalledFxPlugins> installing(List<FxPluginDescription> of) async {
    final installed = InstalledFxPlugins(
      service: library,
      describe: (wasm) => (text: utf8.decode(wasm), refusal: null),
    );
    for (final description in of) {
      await installed.install(
        fileOf(description),
        confirm: (_, {required native, required replacing}) async => true,
      );
    }
    return installed;
  }

  LayerEffect effectOf(FxPluginDescription? plugin, String id) =>
      LayerEffect.defaults(
        id: EffectId(id),
        kind: plugin == null ? EffectKind.blur : EffectKind.plugin,
        plugin: plugin,
      );

  Layer row(String id, List<LayerEffect> effects) =>
      Layer(id: LayerId(id), name: id, frames: const [], effects: effects);

  test('a plugin of its id is one the device has, whatever its version',
      () async {
    final installed = await installing([plugin('a.b')]);
    expect(installed.has(plugin('a.b', version: '9')), isTrue);
    expect(installed.has(plugin('c.d')), isFalse);
  });


  final wearing = Project(
    id: const ProjectId('p'),
    name: 'p',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 't',
        effects: [effectOf(plugin('on.track'), 'fx-1')],
        seLayers: [
          row('se', [effectOf(plugin('on.se'), 'fx-2')]),
        ],
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'c',
            duration: 1,
            canvasSize: const CanvasSize(width: 8, height: 6),
            layers: [
              row('a', [
                effectOf(plugin('here'), 'fx-3'),
                effectOf(null, 'fx-4'),
                effectOf(plugin('on.cut'), 'fx-5'),
              ]),
              row('b', [
                effectOf(plugin('on.track', version: '2'), 'fx-6'),
              ]),
            ],
          ),
        ],
      ),
    ],
  );

  Future<List<String>> missingIn(InstalledFxPlugins installed) async => [
    for (final plugin in await installed.missingFrom(wearing)) plugin.id,
  ];

  test('the plugins a project wears that the device has not — on a track, '
      'on a track\'s own row and on a cut\'s — each once', () async {
    final installed = await installing([plugin('here')]);

    expect(await missingIn(installed), ['on.track', 'on.se', 'on.cut']);
    final missing = await installed.missingFrom(wearing);
    expect(missing.first.version, '1');
    expect(() => missing.add(plugin('else')), throwsUnsupportedError);

    await installed.install(
      fileOf(plugin('on.se', version: '3')),
      confirm: (_, {required native, required replacing}) async => true,
    );
    expect(await missingIn(installed), ['on.track', 'on.cut']);
  });

  test('a project opened before the device is read is asked after it',
      () async {
    await installing([plugin('here'), plugin('on.cut')]);
    final unread = InstalledFxPlugins(service: library);
    expect(unread.plugins, isEmpty);

    expect(await missingIn(unread), ['on.track', 'on.se']);
  });

  test('the device is read once — a later caller waits for the same read',
      () {
    final installed = InstalledFxPlugins(service: library);
    expect(identical(installed.load(), installed.load()), isTrue);
  });
}
