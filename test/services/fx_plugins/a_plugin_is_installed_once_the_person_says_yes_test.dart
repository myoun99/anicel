import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/app_gpu_settings.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_bundle.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:flutter/foundation.dart'
    show FlutterError, FlutterErrorDetails;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fx_plugin_file.dart';
import '../../helpers/temp_dir.dart';

/// I-132, fx spec 2: installing an fx plugin from its file — its
/// description read, its WGSL opened on the device, the person shown who
/// it is and asked, and nothing kept before they say yes; a plugin the
/// device has already replaced where it stood.
///
/// The device is asked through a stand-in here: opening WGSL on the GPU is
/// `a_gpu_plugin_opens_and_runs_on_the_engine_test`'s.
void main() {
  late Directory room;
  late FxPluginLibraryService library;

  setUp(() {
    room = Directory.systemTemp.createTempSync('anicel_fx_install_');
    library = FxPluginLibraryService(directoryPath: '${room.path}/fx');
  });
  tearDown(() => deleteTempQuietly(room));

  Uint8List fileOf(String id, String version) => fxPluginFileOf(
    fxPluginDescriptionOf(id, version: version),
    source: '// $id $version\n',
  );

  final asked = <({String id, String? replacing})>[];
  FxPluginConfirm answering(bool yes) =>
      (description, {required replacing}) async {
        asked.add((id: description.id, replacing: replacing?.version));
        return yes;
      };
  setUp(asked.clear);

  final checked = <String>[];
  setUp(checked.clear);
  InstalledFxPlugins plugins({String? refusal}) => InstalledFxPlugins(
    service: library,
    check: (FxPluginBundle bundle) {
      checked.add(bundle.source);
      return refusal;
    },
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
        fxPluginFileOf(
          fxPluginDescriptionOf('a.b'),
          withoutDescription: true,
        ),
        confirm: answering(true),
      ),
      isA<FxPluginUnreadable>(),
    );
    expect(checked, isEmpty, reason: 'no device asked of what is no plugin');
    final unopened = await plugins(refusal: '3:7: no float here').install(
      fileOf('a.b', '1'),
      confirm: answering(true),
    );
    expect((unopened as FxPluginUnopened).why, '3:7: no float here');
    expect(checked, ['// a.b 1\n']);
    expect(asked, isEmpty);
    expect(await library.loadIndex(), isEmpty);
  });

  test('a no keeps nothing', () async {
    final installed = plugins();
    final outcome = await installed.install(
      fileOf('a.b', '1'),
      confirm: answering(false),
    );
    expect(outcome, isA<FxPluginDeclined>());
    expect(asked.single.id, 'a.b');
    expect(installed.plugins, isEmpty);
    expect(await library.loadIndex(), isEmpty);
    expect(Directory(library.directoryPath).existsSync(), isFalse);
  });

  test('a yes keeps it, opened on the device before it was asked', () async {
    final installed = plugins();
    var heard = 0;
    installed.addListener(() => heard += 1);
    final outcome = await installed.install(
      fileOf('a.b', '1'),
      confirm: (description, {required replacing}) async {
        expect(checked, ['// a.b 1\n'], reason: 'checked before asking');
        return answering(true)(description, replacing: replacing);
      },
    );
    expect((outcome as FxPluginInstalled).description.id, 'a.b');
    expect(outcome.replaced, isNull);
    await installed.install(fileOf('c.d', '1'), confirm: answering(true));
    expect(asked, [
      (id: 'a.b', replacing: null),
      (id: 'c.d', replacing: null),
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
    await installed.install(fileOf('a.b', '1'), confirm: answering(true));
    await installed.install(fileOf('c.d', '1'), confirm: answering(true));
    final first = installed.plugins.first;
    final outcome = await installed.install(
      fileOf('a.b', '2'),
      confirm: answering(true),
    );
    expect(asked.last, (id: 'a.b', replacing: '1'));
    expect((outcome as FxPluginInstalled).replaced?.version, '1');
    expect([
      for (final p in installed.plugins)
        (p.description.id, p.description.version),
    ], [('a.b', '2'), ('c.d', '1')]);
    expect(await library.read(first.source), isNull);
    final kept = await library.loadIndex();
    expect(kept.first.description.version, '2');
    expect(
      utf8.decode((await library.read(kept.first.source))!),
      '// a.b 2\n',
    );
  });

  test('a plugin deleted goes off the device, its file and all, and the '
      'rest stay as they stood', () async {
    final installed = plugins();
    await installed.install(fileOf('a.b', '1'), confirm: answering(true));
    await installed.install(fileOf('c.d', '1'), confirm: answering(true));
    final gone = installed.plugins.first;
    var heard = 0;
    installed.addListener(() => heard += 1);

    await installed.uninstall('a.b');

    expect(heard, 1);
    expect([for (final p in installed.plugins) p.description.id], ['c.d']);
    expect(await library.read(gone.source), isNull);
    expect(await library.read(installed.plugins.single.source), isNotNull);
    final again = InstalledFxPlugins(service: library);
    await again.load();
    expect([for (final p in again.plugins) p.description.id], ['c.d']);

    await installed.uninstall('a.b');
    expect(heard, 1, reason: 'one it has not is no change');
  });

  test('moving to or from never cutting opens its plugins again, the new '
      'way, and no other share does', () async {
    // 🗣️an-endless-plugin-stalls-the-app-Q18: 「끊지 않음」 is compiled
    // with no count; a share is handed each run.
    addTearDown(AppGpu.debugReset);
    final opened = <bool>[];
    final closed = <int>[];
    final installed = InstalledFxPlugins(
      service: library,
      check: (_) => null,
      open: (_, _) {
        opened.add(AppGpu.settings.value.pluginShare.cuts);
        return _Kept(opened.length, closed);
      },
    );
    addTearDown(installed.dispose);
    await installed.install(fileOf('a.b', '1'), confirm: answering(true));
    final plugin = installed.plugins.single.description;
    final first = installed.runnerFor(plugin);
    AppGpu.settings.value = const AppGpuSettings(
      pluginShare: FxPluginShare.tenThousand,
    );
    expect(installed.runnerFor(plugin), same(first), reason: 'the same build');
    var heard = 0;
    installed.addListener(() => heard += 1);
    AppGpu.settings.value = const AppGpuSettings(
      pluginShare: FxPluginShare.uncut,
    );
    expect(closed, [1], reason: 'let go at once');
    expect(heard, 1, reason: 'and said so');
    final uncut = installed.runnerFor(plugin);
    AppGpu.settings.value = const AppGpuSettings();
    expect(installed.runnerFor(plugin), isNot(same(uncut)));
    expect(opened, [true, false, true]);
    expect(closed, [1, 2]);
  });

  test('let go, it hears the GPU setting no more', () {
    addTearDown(AppGpu.debugReset);
    final reported = <FlutterErrorDetails>[];
    final reporting = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = reporting);
    plugins().dispose();

    AppGpu.settings.value = const AppGpuSettings(
      pluginShare: FxPluginShare.uncut,
    );
    expect(reported, isEmpty, reason: 'one let go was told of a change');
  });
}

/// A build that says when it is let go.
final class _Kept implements FxPluginRunner {
  _Kept(this.number, this.closed);

  final int number;
  final List<int> closed;

  @override
  int? reach(Float64List values, FxPluginMoment moment) => 0;

  @override
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) => null;

  @override
  void close() => closed.add(number);
}
