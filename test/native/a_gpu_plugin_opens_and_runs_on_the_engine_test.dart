@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/app_gpu_settings.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/native/app_gpu_engine.dart' show AppKernels;
import 'package:anicel/src/native/gpu_fx_plugin.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart'
    show debugKernelsCompiledHere, debugWaitsHere;

import '../helpers/fx_plugin_file.dart';
import '../helpers/temp_dir.dart';

/// A GPU fx plugin (fx spec 2) as the app asks it — its WGSL opened on the
/// app's engine ([GpuFxPlugin]), its values handed as `fxPluginValuesOf`
/// gives them and its pictures straight — held to answers worked out here.
/// The device's run against the CPU's, pixel for pixel, is the engine's
/// (rust/src/kernels/plugin/tests.rs); this holds what the app hands it.
void main() {
  const moment = (frameIndex: 7, time: 1.25, frameRate: 24.0, scale: 0.5);
  setUp(AppGpu.debugReset);
  tearDown(AppGpu.debugReset);

  GpuFxPlugin opened(String source, FxPluginDescription description) {
    final (:plugin, :refusal) = GpuFxPlugin.open(
      source,
      description,
      cut: true,
    );
    expect(refusal, isNull);
    addTearDown(plugin!.close);
    return plugin;
  }

  // 5×3 at canvas (−1, −2), straight: half of it half clear.
  final input = Uint8List(5 * 3 * 4);
  for (var at = 0; at < 15; at += 1) {
    final alpha = at.isEven ? 255 : 128;
    input.setAll(at * 4, [at * 17, 200 - at * 9, 7 + at, alpha]);
  }
  FxPluginPicture pictureOf(Uint8List pixels) =>
      (pixels: pixels, width: 5, height: 3, left: -1, top: -2);

  test('a plugin opens from its WGSL, or the engine says why not', () {
    final invert = fxPluginDescriptionOf('a.invert');
    String? refusalOf(String source) =>
        GpuFxPlugin.open(source, invert, cut: true).refusal;
    expect(refusalOf(fxPluginFixture('invert')), isNull);
    final float = refusalOf(fxPluginFixture('float'));
    expect(float, matches(RegExp(r'^\d+:\d+: ')), reason: 'its line named');
    expect(refusalOf('not WGSL'), isNotEmpty);
  });

  test('it draws the straight picture handed it, in its place', () async {
    final invert = opened(
      fxPluginFixture('invert'),
      fxPluginDescriptionOf('a.invert'),
    );
    final drawn = (await invert.render(
      input: pictureOf(input),
      values: Float64List(0),
      layers: const [],
      moment: moment,
    ))!;
    for (var at = 0; at < input.length; at += 4) {
      expect(drawn.sublist(at, at + 4), [
        255 - input[at],
        255 - input[at + 1],
        255 - input[at + 2],
        input[at + 3],
      ], reason: 'pixel ${at ~/ 4}: no alpha multiplied in or out');
    }
  });

  test('a picture whose bytes start off a word is read as one that does '
      'not', () async {
    final invert = opened(
      fxPluginFixture('invert'),
      fxPluginDescriptionOf('a.invert'),
    );
    final off = Uint8List(input.length + 1)..setAll(1, input);
    FxPluginPicture at(Uint8List pixels) => pictureOf(pixels);
    expect(
      await invert.render(
        input: at(Uint8List.sublistView(off, 1)),
        values: Float64List(0),
        layers: const [],
        moment: moment,
      ),
      await invert.render(
        input: at(input),
        values: Float64List(0),
        layers: const [],
        moment: moment,
      ),
    );
  });

  test('every kind of parameter reaches it as the spec says its '
      'words', () async {
    final probe = opened(
      _probe,
      fxPluginDescriptionOf(
        'a.probe',
        params: [
          _ranged('n', 'number', -9, 9),
          _ranged('a', 'angle', 0, 360),
          {'id': 'c', 'kind': 'color', 'label': 'c', 'default': [0, 0, 0, 1]},
          {'id': 'p', 'kind': 'point', 'label': 'p'},
          {'id': 'f', 'kind': 'checkbox', 'label': 'f', 'default': false},
          {
            'id': 'm',
            'kind': 'menu',
            'label': 'm',
            'choices': [
              for (final id in ['x', 'y', 'z']) {'id': id, 'label': id},
            ],
            'default': 0,
          },
          {'id': 'l', 'kind': 'layer', 'label': 'l'},
        ],
      ),
    );
    final drawn = (await probe.render(
      input: (pixels: Uint8List(32 * 4), width: 32, height: 1, left: 3, top: 9),
      values: Float64List.fromList([
        1.5, 0, 0, 0, // number
        90, 0, 0, 0, // angle
        1, 0.5, 0, 128 / 255, // colour
        10.25, -3, 0, 0, // point
        1, 0, 0, 0, // checkbox
        2, 0, 0, 0, // menu
        -1, 0, 0, 0, // layer
      ]),
      layers: const [],
      moment: moment,
    ))!;
    final words = drawn.buffer.asInt32List(drawn.offsetInBytes, 32);
    expect(words, [
      7, 5 << 14, 24 << 16, 1 << 15, // the moment
      3 << 15, 0, 0, 0, // Q.16
      90 << 16, 0, 0, 0,
      65535, 32768, 0, 32896, // 16 bits a channel
      (10 << 16) + (1 << 14), -3 << 16, 0, 0,
      1, 0, 0, 0, // whole
      2, 0, 0, 0,
      -1, 0, 0, 0,
    ]);
  });

  test('its reach is the plugin\'s for the values', () {
    final blur = opened(fxPluginFixture('blur'), _blurOf());
    final values = Float64List.fromList([3.4, 0, 0, 0]);
    expect(blur.reach(values, moment), 3);
    final endless = opened(fxPluginFixture('endless'), _blurOf());
    AppGpu.settings.value = const AppGpuSettings(
      pluginShare: FxPluginShare.tenThousand,
    );
    expect(endless.reach(values, moment), isNull, reason: 'cut');
  });

  test('a layer it reads is the one its value names, where the canvas '
      'puts it', () async {
    final layer = opened(
      fxPluginFixture('layer'),
      fxPluginDescriptionOf(
        'a.layer',
        params: [
          {'id': 'map', 'kind': 'layer', 'label': 'Map'},
        ],
      ),
    );
    final map = Uint8List(5 * 3 * 4);
    for (var at = 0; at < 15; at += 1) {
      map.setAll(at * 4, [9, 99, at, 255]);
    }
    final clear = Uint8List(5 * 3 * 4)..fillRange(0, 4, 255);
    final drawn = (await layer.render(
      input: pictureOf(clear),
      values: Float64List.fromList([0, 0, 0, 0]),
      layers: [(pixels: map, width: 5, height: 3, left: 0, top: -2)],
      moment: moment,
    ))!;
    expect(drawn.sublist(0, 4), [255, 255, 255, 255], reason: 'its own');
    for (var at = 1; at < 15; at += 1) {
      final (x, y) = (at % 5 - 1, at ~/ 5 - 2);
      final behind = x >= 0 ? [9, 99, (y + 2) * 5 + x, 255] : [0, 0, 0, 0];
      expect(drawn.sublist(at * 4, at * 4 + 4), behind, reason: '($x, $y)');
    }
  });

  test('each pixel of a run has this machine\'s share, however many pixels '
      'there are', () async {
    // 🗣️an-endless-plugin-stalls-the-app-Q19: 「화소 하나의 몫으로 고정」 —
    // ↩️the share was the limit over the pixels, so a picture of more of
    // them was cut first.
    final blur = opened(fxPluginFixture('blur'), _blurOf());
    final endless = opened(fxPluginFixture('endless'), _blurOf());
    Future<Uint8List?> drawn(GpuFxPlugin plugin, int side) =>
        plugin.render(
          input: (
            pixels: Uint8List(side * side * 4),
            width: side,
            height: side,
            left: 0,
            top: 0,
          ),
          values: Float64List.fromList([2, 0, 0, 0]),
          layers: const [],
          moment: moment,
        );

    AppGpu.settings.value = const AppGpuSettings(
      pluginShare: FxPluginShare.tenThousand,
    );
    expect(
      await drawn(blur, 1),
      isNotNull,
      reason: '⛔CONTROL: the least share',
    );
    expect(
      await drawn(blur, 64),
      isNotNull,
      reason: '4,096 pixels, each its own',
    );
    expect(await drawn(endless, 64), isNull, reason: 'cut');
  });

  test('once closed it answers nothing', () async {
    final (:plugin, refusal: _) = GpuFxPlugin.open(
      fxPluginFixture('invert'),
      fxPluginDescriptionOf('a.invert'),
      cut: true,
    );
    plugin!.close();
    expect(plugin.reach(Float64List(0), moment), isNull);
    expect(
      await plugin.render(
        input: pictureOf(input),
        values: Float64List(0),
        layers: const [],
        moment: moment,
      ),
      isNull,
    );
    plugin.close();
  });

  /// 🧭관제 2026-11-12 08:5x (float-warp-resamples-in-the-c-engine): a box
  /// dragged over a row under a device plugin held the UI thread for each
  /// run — 72–94 ms p50, 🔬Surface Pro 11. ⚠️The suite runs every worker's
  /// job here (`debugWorkersRunHere`), so these turn it off: the road the
  /// app takes.
  group('🚨a run goes on a worker (GpuPluginRenderer)', () {
    late bool corpus;
    setUp(() => corpus = debugWorkersRunHere);
    tearDown(() => debugWorkersRunHere = corpus);

    Future<Uint8List?> inverted(GpuFxPlugin invert) => invert.render(
      input: pictureOf(input),
      values: Float64List(0),
      layers: const [],
      moment: moment,
    );

    GpuFxPlugin anInvert() =>
        opened(fxPluginFixture('invert'), fxPluginDescriptionOf('a.invert'));

    test('the isolate that asks waits for the GPU none of the times it '
        'runs', () async {
      final invert = anInvert();
      Future<int> waited() async {
        final before = debugWaitsHere;
        expect(await inverted(invert), isNotNull);
        return debugWaitsHere - before;
      }

      debugWorkersRunHere = true;
      expect(await waited(), greaterThan(0), reason: '⛔CONTROL: run here');
      debugWorkersRunHere = false;
      expect(await waited(), 0);
    });

    test('closed while a run is on its way, it is let go once the run has '
        'ended — the run drew', () async {
      debugWorkersRunHere = false;
      final invert = anInvert();
      final drawing = inverted(invert);
      invert.close();
      expect(invert.debugLetGo, isFalse, reason: 'not under the run');
      final drawn = (await drawing)!;
      expect(invert.debugLetGo, isTrue, reason: 'once it has ended');
      expect(drawn.sublist(0, 4), [
        255 - input[0],
        255 - input[1],
        255 - input[2],
        input[3],
      ]);
      expect(await inverted(invert), isNull, reason: 'closed');
    });
  });

  group('installed on this device', () {
    late Directory room;
    setUp(() => room = Directory.systemTemp.createTempSync('anicel_fx_gpu_'));
    tearDown(() => deleteTempQuietly(room));

    test('a plugin is opened on the device before the person is asked, and '
        'runs from what the device kept', () async {
      final plugins = InstalledFxPlugins(
        service: FxPluginLibraryService(directoryPath: '${room.path}/fx'),
      );
      addTearDown(plugins.dispose);
      final description = fxPluginDescriptionOf('a.invert');
      var asked = 0;
      final refused = await plugins.install(
        fxPluginFileOf(description, source: fxPluginFixture('float')),
        confirm: (_, {required replacing}) async => (asked += 1) > 0,
      );
      expect((refused as FxPluginUnopened).why, matches(RegExp(r'^\d+:')));
      expect(asked, 0);

      final installed = await plugins.install(
        fxPluginFileOf(description, source: fxPluginFixture('invert')),
        confirm: (_, {required replacing}) async => (asked += 1) > 0,
      );
      expect(installed, isA<FxPluginInstalled>());
      final drawn = (await plugins.runnerFor(description)!.render(
        input: pictureOf(input),
        values: Float64List(0),
        layers: const [],
        moment: moment,
      ))!;
      expect(drawn.sublist(0, 4), [
        255 - input[0],
        255 - input[1],
        255 - input[2],
        input[3],
      ]);
    });

    test('never cutting opens it on the device again, without its '
        'count', () async {
      // 🗣️an-endless-plugin-stalls-the-app-Q18 「끊지 않음」: what the share
      // would cut is drawn to its end, and its reach answered.
      final plugins = InstalledFxPlugins(
        service: FxPluginLibraryService(directoryPath: '${room.path}/fx'),
      );
      addTearDown(plugins.dispose);
      final description = fxPluginDescriptionOf('a.spin');
      await plugins.install(
        fxPluginFileOf(description, source: _spin),
        confirm: (_, {required replacing}) async => true,
      );
      Future<Uint8List?> drawn() => plugins.runnerFor(description)!.render(
        input: (pixels: Uint8List(4), width: 1, height: 1, left: 0, top: 0),
        values: Float64List(0),
        layers: const [],
        moment: moment,
      );

      int? reach() =>
          plugins.runnerFor(description)!.reach(Float64List(0), moment);

      expect(await drawn(), isNull, reason: '⛔CONTROL: the standard share cuts it');
      expect(reach(), isNull, reason: '⛔CONTROL: and its reach');
      AppGpu.settings.value = const AppGpuSettings(
        pluginShare: FxPluginShare.uncut,
      );
      expect(await drawn(), isNotNull);
      expect(reach(), 0);
    });

    test('🚨a frame that asks for a plugin is answered at once: its build is '
        'opened off this isolate, which compiles nothing of it', () async {
      // 🗣️관제 2026-11-12 22:25 (an-endless-plugin-stalls-the-app ④): the
      // app's route, not a test's that compiles here.
      AppKernels.debugCompileHere = false;
      addTearDown(() => AppKernels.debugCompileHere = true);
      final library = FxPluginLibraryService(directoryPath: '${room.path}/fx');
      final description = fxPluginDescriptionOf('a.invert');
      final installing = InstalledFxPlugins(service: library);
      await installing.install(
        fxPluginFileOf(description, source: fxPluginFixture('invert')),
        confirm: (_, {required replacing}) async => true,
      );
      installing.dispose();
      final plugins = InstalledFxPlugins(service: library);
      addTearDown(plugins.dispose);
      await plugins.load();

      final compiledHere = debugKernelsCompiledHere;
      final runner = plugins.runnerFor(description)!;
      final toCome = runner.toCome;
      expect(toCome, isNotNull, reason: 'its build is still to come');
      await toCome;
      expect(runner.toCome, isNull);
      expect(debugKernelsCompiledHere, compiledHere);
      final drawn = (await runner.render(
        input: pictureOf(input),
        values: Float64List(0),
        layers: const [],
        moment: moment,
      ))!;
      expect(drawn.sublist(0, 4), [
        255 - input[0],
        255 - input[1],
        255 - input[2],
        input[3],
      ]);
    });
  });
}

/// Spends more of a pixel's share than the standard gives — a million
/// turns, in its drawing and its reach alike — and ends.
const _spin = '''
fn spun() -> u32 {
  var n = 0u;
  for (var i = 0u; i < 1000000u; i++) {
    n += i;
  }
  return n;
}

@compute @workgroup_size(1, 1)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  anicel_out(spun());
}

fn anicel_reach() -> u32 {
  return spun() & 0u;
}
''';

/// The blur fixture's description: its radius a number.
FxPluginDescription _blurOf() => fxPluginDescriptionOf(
  'a.blur',
  params: [_ranged('radius', 'number', 0, 64)],
);

/// A parameter of [kind] — a number or an angle — from [min] to [max], 0
/// where its range has it, else [min].
Map<String, Object?> _ranged(String id, String kind, num min, num max) => {
  'id': id,
  'kind': kind,
  'label': id,
  'default': min <= 0 && 0 <= max ? 0 : min,
  'min': min,
  'max': max,
};

/// Writes what it is handed, a word a pixel along its row from its left:
/// the moment's four, then each value's four words.
const _probe = '''
@compute @workgroup_size(16, 1)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  let i = i32(at.x);
  var word = 0;
  switch i {
    case 0: { word = anicel_frame(); }
    case 1: { word = anicel_time(); }
    case 2: { word = anicel_rate(); }
    case 3: { word = anicel_scale(); }
    default: { word = anicel_value((i - 4) / 4, (i - 4) % 4); }
  }
  anicel_out(bitcast<u32>(word));
}

fn anicel_reach() -> u32 {
  return 0u;
}
''';
