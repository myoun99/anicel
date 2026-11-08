@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/app_gpu_settings.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/native/gpu_fx_plugin.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:flutter_test/flutter_test.dart';

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
    final (:plugin, :refusal) = GpuFxPlugin.open(source, description);
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
    expect(GpuFxPlugin.open(fxPluginFixture('invert'), invert).refusal, isNull);
    final float = GpuFxPlugin.open(fxPluginFixture('float'), invert).refusal;
    expect(float, matches(RegExp(r'^\d+:\d+: ')), reason: 'its line named');
    expect(GpuFxPlugin.open('not WGSL', invert).refusal, isNotEmpty);
  });

  test('it draws the straight picture handed it, in its place', () {
    final invert = opened(
      fxPluginFixture('invert'),
      fxPluginDescriptionOf('a.invert'),
    );
    final drawn = invert.render(
      input: pictureOf(input),
      values: Float64List(0),
      layers: const [],
      moment: moment,
    )!;
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
      'not', () {
    final invert = opened(
      fxPluginFixture('invert'),
      fxPluginDescriptionOf('a.invert'),
    );
    final off = Uint8List(input.length + 1)..setAll(1, input);
    FxPluginPicture at(Uint8List pixels) => pictureOf(pixels);
    expect(
      invert.render(
        input: at(Uint8List.sublistView(off, 1)),
        values: Float64List(0),
        layers: const [],
        moment: moment,
      ),
      invert.render(
        input: at(input),
        values: Float64List(0),
        layers: const [],
        moment: moment,
      ),
    );
  });

  test('every kind of parameter reaches it as the spec says its words', () {
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
    final drawn = probe.render(
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
    )!;
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
    AppGpu.settings.value = const AppGpuSettings(pluginLimit: 1000000);
    expect(endless.reach(values, moment), isNull, reason: 'cut');
  });

  test('a layer it reads is the one its value names, where the canvas '
      'puts it', () {
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
    final drawn = layer.render(
      input: pictureOf(clear),
      values: Float64List.fromList([0, 0, 0, 0]),
      layers: [(pixels: map, width: 5, height: 3, left: 0, top: -2)],
      moment: moment,
    )!;
    expect(drawn.sublist(0, 4), [255, 255, 255, 255], reason: 'its own');
    for (var at = 1; at < 15; at += 1) {
      final (x, y) = (at % 5 - 1, at ~/ 5 - 2);
      final behind = x >= 0 ? [9, 99, (y + 2) * 5 + x, 255] : [0, 0, 0, 0];
      expect(drawn.sublist(at * 4, at * 4 + 4), behind, reason: '($x, $y)');
    }
  });

  test('a run cut at this machine\'s limit is no picture', () {
    final blur = opened(fxPluginFixture('blur'), _blurOf());
    Uint8List? drawn(int side, int limit) {
      AppGpu.settings.value = AppGpuSettings(pluginLimit: limit);
      return blur.render(
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
    }

    expect(
      drawn(64, AppGpuSettings.defaultPluginLimit),
      isNotNull,
      reason: '⛔CONTROL: the default draws it',
    );
    // The fewest a pixel of this blur spends: one pixel draws on it, and
    // not on one fewer.
    var (low, high) = (0, 1 << 24);
    expect((drawn(1, high), drawn(1, low)), (isNotNull, isNull));
    while (high - low > 1) {
      final mid = (low + high) ~/ 2;
      if (drawn(1, mid) == null) {
        low = mid;
      } else {
        high = mid;
      }
    }
    expect(drawn(2, 4 * high), isNotNull, reason: 'four pixels, each its');
    expect(drawn(2, 4 * high - 1), isNull, reason: 'one a share short');
  });

  test('once closed it answers nothing', () {
    final (:plugin, refusal: _) = GpuFxPlugin.open(
      fxPluginFixture('invert'),
      fxPluginDescriptionOf('a.invert'),
    );
    plugin!.close();
    expect(plugin.reach(Float64List(0), moment), isNull);
    expect(
      plugin.render(
        input: pictureOf(input),
        values: Float64List(0),
        layers: const [],
        moment: moment,
      ),
      isNull,
    );
    plugin.close();
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
      final drawn = plugins.runnerFor(description)!.render(
        input: pictureOf(input),
        values: Float64List(0),
        layers: const [],
        moment: moment,
      )!;
      expect(drawn.sublist(0, 4), [
        255 - input[0],
        255 - input[1],
        255 - input[2],
        input[3],
      ]);
    });
  });
}

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
const _probe = r'''
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
