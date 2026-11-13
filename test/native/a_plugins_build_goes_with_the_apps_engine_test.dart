@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/app_gpu_settings.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/gpu_fx_plugin.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fx_plugin_file.dart';
import '../helpers/temp_dir.dart';
import '../helpers/the_apps_engine_let_go.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」 — a plugin's build is of the engine
/// the app had as it was opened, and the list of this device's plugins
/// lets every one go as the app lets that engine go
/// (a-lost-gpu-device-keeps-the-unsaved-tiles (C3) ④; 관제 2026-11-12 22:3x:
/// 「(C3) ④ 는 그 감싸개에 놓기를 단다」): the next frame that asks is
/// answered with one opened on the engine the app has by then.
///
/// On the app's own engine, which each test loses: the one after it finds
/// the next.
void main() {
  const moment = (frameIndex: 7, time: 1.25, frameRate: 24.0, scale: 1.0);
  final description = fxPluginDescriptionOf('a.invert');
  const inverted = [245, 55, 225, 255];

  late Directory room;
  setUp(() {
    AppGpu.debugReset();
    room = Directory.systemTemp.createTempSync('anicel_fx_engine_');
  });
  tearDown(() {
    AppGpu.debugReset();
    deleteTempQuietly(room);
  });

  FxPluginLibraryService library() =>
      FxPluginLibraryService(directoryPath: '${room.path}/fx');

  Future<void> install(InstalledFxPlugins plugins) => plugins.install(
    fxPluginFileOf(description, source: fxPluginFixture('invert')),
    confirm: (_, {required replacing}) async => true,
  );

  /// This device's list, the inverting plugin installed and its build the
  /// one the install's check opened.
  Future<InstalledFxPlugins> installed() async {
    final plugins = InstalledFxPlugins(service: library());
    addTearDown(plugins.dispose);
    await install(plugins);
    return plugins;
  }

  /// This device's list as a launch reads it, the inverting plugin
  /// installed before: no build of it opened yet.
  Future<InstalledFxPlugins> readAtLaunch() async {
    final installing = InstalledFxPlugins(service: library());
    await install(installing);
    installing.dispose();
    final plugins = InstalledFxPlugins(service: library());
    addTearDown(plugins.dispose);
    await plugins.load();
    return plugins;
  }

  /// From here on a build is opened as the app opens one: off this
  /// isolate.
  void opensOffFromHere() {
    AppKernels.debugCompileHere = false;
    addTearDown(() => AppKernels.debugCompileHere = true);
  }

  /// What [runner] makes of one pixel — null where it answers nothing.
  Future<List<int>?> drawnBy(FxPluginRunner runner) async {
    final drawn = await runner.render(
      input: (
        pixels: Uint8List.fromList(const [10, 200, 30, 255]),
        width: 1,
        height: 1,
        left: 0,
        top: 0,
      ),
      values: Float64List(0),
      layers: const [],
      moment: moment,
    );
    return drawn?.sublist(0, 4);
  }

  test('a build goes with the engine it was opened on: it is let go, the '
      'list says it changed, and the next ask opens one on the next '
      'engine', () async {
    final plugins = await installed();
    final first = plugins.runnerFor(description)!;
    expect(await drawnBy(first), inverted, reason: '⛔premise: it draws');
    var changed = 0;
    plugins.addListener(() => changed += 1);

    theAppsEngineLostAndLetGo();

    expect(changed, 1, reason: 'what bound it is bound another');
    expect((first as GpuFxPlugin).debugLetGo, isTrue);
    final next = plugins.runnerFor(description)!;
    expect(next, isNot(same(first)));
    expect(await drawnBy(next), inverted);
  });

  test('one asked for while the device was gone answers nothing, and goes '
      'with that engine as well: the next ask opens one that draws', () async {
    final plugins = await readAtLaunch();
    theAppsEngineLost();
    final asked = plugins.runnerFor(description)!;
    expect(await drawnBy(asked), isNull, reason: '⛔premise: no device');

    letTheGoneAppGpuEngineGo();

    expect(await drawnBy(plugins.runnerFor(description)!), inverted);
  });

  test('what its runs told on the engine let go is forgotten with '
      'it', () async {
    final plugins = await installed();
    const row = LayerId('row');
    const place = (owner: row, effect: EffectId('fx'));
    plugins.outcomes.toldFor(
      (owner: row, effect: place.effect, wearer: row),
      ResolvedLayerEffect(
        kind: EffectKind.plugin,
        plugin: description,
        values: const [],
        frame: 1,
      ),
      cut: const CutId('cut'),
      frame: 1,
    )(failed: true);
    expect(plugins.outcomes.failedAt(place, 1), isTrue, reason: '⛔premise');

    theAppsEngineLostAndLetGo();

    expect(plugins.outcomes.failedAt(place, 1), isFalse);
  });

  test('a build an install\'s check opened on an engine the app has let go '
      'since is not the list\'s: it is let go, and the first ask opens '
      'one', () async {
    FxPluginRunner? checked;
    final plugins = InstalledFxPlugins(
      service: library(),
      check: (bundle) async {
        final came = await checkFxPluginOnTheDevice(bundle);
        checked = came.opened;
        return came;
      },
    );
    addTearDown(plugins.dispose);

    await plugins.install(
      fxPluginFileOf(description, source: fxPluginFixture('invert')),
      confirm: (_, {required replacing}) async {
        theAppsEngineLostAndLetGo();
        return true;
      },
    );

    expect((checked! as GpuFxPlugin).debugLetGo, isTrue);
    expect(await drawnBy(plugins.runnerFor(description)!), inverted);
  });

  test('🚨one asked for once the app has let its engine go, before the next '
      'is open, waits for that engine opened off this isolate — none is '
      'opened where it is asked', () async {
    final plugins = await readAtLaunch();
    opensOffFromHere();
    theAppsEngineLostAndLetGo();
    expect(debugAppGpuEngineAskedFor, isFalse, reason: '⛔premise');

    final runner = plugins.runnerFor(description)!;
    await runner.toCome;

    expect(
      appGpuEngineOpen.value,
      isNotNull,
      reason: 'opened as the app opens it, and said to be',
    );
    expect(await drawnBy(runner), inverted);
  });

  test('one still opening as the app lets its engine go is the list\'s no '
      'more: it answers nothing once it comes, and the next ask opens '
      'another', () async {
    final plugins = await readAtLaunch();
    opensOffFromHere();
    await openAppGpuEngine();
    final first = plugins.runnerFor(description)!;
    final toCome = first.toCome;
    expect(toCome, isNotNull, reason: '⛔premise: still opening');

    theAppsEngineLostAndLetGo();

    final next = plugins.runnerFor(description)!;
    expect(next, isNot(same(first)));
    await toCome;
    expect(await drawnBy(first), isNull);
    await next.toCome;
    expect(await drawnBy(next), inverted);
  });
}
