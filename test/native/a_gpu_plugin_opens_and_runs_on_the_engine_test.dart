@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/app_gpu_settings.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/native/gpu_fx_plugin.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart'
    show GpuComposite, debugKernelsCompiledHere, debugWaitsHere, gpuTileSide;

import '../helpers/a_plugin_steps_input.dart';
import '../helpers/a_plugin_that_shifts.dart'
    show fxPluginTilesPixels;
import '../helpers/fx_plugin_file.dart';
import '../helpers/temp_dir.dart';

/// A GPU fx plugin (fx spec 2) as the app asks it — its WGSL opened on the
/// app's engine ([GpuFxPlugin]), its values handed as `fxPluginValuesOf`
/// gives them, its input a step's chain where the engine holds it — held
/// to answers worked out here. The device's run against the CPU's, pixel
/// for pixel and wherever it lies, is the engine's
/// (rust/src/kernels/plugin/tests.rs); this holds what the app hands it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const moment = (frameIndex: 7, time: 1.25, frameRate: 24.0, scale: 0.5);
  final side = gpuTileSide;
  late GpuComposite composite;
  late EngineLetters letters;

  setUpAll(() async {
    composite = GpuComposite(appGpuEngine);
    letters = await EngineLetters.open(composite);
  });
  tearDownAll(() {
    composite.free();
  });
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

  // A tile left of the canvas's first, straight: half of it half clear.
  final spread = Uint8List(side * side * 4);
  for (var at = 0; at < side * side; at += 1) {
    final alpha = at.isEven ? 255 : 128;
    spread.setAll(at * 4, [
      (at * 17) & 255,
      (200 - at * 9) & 255,
      (7 + at) & 255,
      alpha,
    ]);
  }

  /// A cel of [canvas] holding [tiles].
  BitmapSurface celOf(
    CanvasSize canvas, [
    Map<TileCoord, BitmapTile> tiles = const {},
  ]) => BitmapSurface(canvasSize: canvas, tileSize: side, tiles: tiles);

  /// The step's input over [spread], at its tile left of a canvas of one
  /// pixel: a picture of 129 × 128 from (−128, 0), the canvas's pixel
  /// clear.
  FxPluginInput spreadInput() => aPluginStepsInput(
    composite,
    letters,
    celOf(const CanvasSize(width: 1, height: 1), {
      TileCoord(x: -1, y: 0): BitmapTile(
        size: side,
        pixels: Uint8List.fromList(spread),
      ),
    }),
  );

  /// The step's input over a clear tile at the canvas's first, asked over
  /// [width] × [height] of it from its first pixel.
  FxPluginInput clearInput(int width, int height) => aPluginStepsInput(
    composite,
    letters,
    celOf(const CanvasSize(width: 1, height: 1), {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: side,
        pixels: Uint8List(side * side * 4),
      ),
    }),
    picture: (left: 0, top: 0, width: width, height: height),
  );

  /// [spread]'s pixel [at], inverted: its colour, not its alpha.
  List<int> inverted(int at) => [
    255 - spread[at * 4],
    255 - spread[at * 4 + 1],
    255 - spread[at * 4 + 2],
    spread[at * 4 + 3],
  ];

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
    final input = spreadInput();
    expect(input.picture, (left: -side, top: 0, width: side + 1, height: side));
    final made = (await invert.render(
      input: input,
      values: Float64List(0),
      moment: moment,
    ))!;
    expect(made.keys, {
      TileCoord(x: -1, y: 0),
      TileCoord(x: 0, y: 0),
    }, reason: 'the tiles it lies on');
    final drawn = fxPluginTilesPixels(input, made);
    for (var y = 0; y < side; y += 1) {
      for (var x = 0; x <= side; x += 1) {
        final at = (y * (side + 1) + x) * 4;
        expect(
          drawn.sublist(at, at + 4),
          x < side ? inverted(y * side + x) : [0, 0, 0, 0],
          reason: '($x, $y): no alpha multiplied in or out',
        );
      }
    }
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
    final input = clearInput(64, 1);
    final made = (await probe.render(
      input: input,
      values: Float64List.fromList([
        1.5, 0, 0, 0, // number
        90, 0, 0, 0, // angle
        1, 0.5, 0, 128 / 255, // colour
        10.25, -3, 0, 0, // point
        1, 0, 0, 0, // checkbox
        2, 0, 0, 0, // menu
        -1, 0, 0, 0, // layer
      ]),
      moment: moment,
    ))!;
    final drawn = fxPluginTilesPixels(input, made);
    // A word in two pixels, its low half then its high, each in red and
    // green.
    final words = [
      for (var at = 0; at < 64 * 4; at += 8)
        (drawn[at] |
                drawn[at + 1] << 8 |
                drawn[at + 4] << 16 |
                drawn[at + 5] << 24)
            .toSigned(32),
    ];
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
    const canvas = CanvasSize(width: 5, height: 3);
    final origin = TileCoord(x: 0, y: 0);
    // Its own first pixel, and the map right of it.
    final own = Uint8List(side * side * 4)..fillRange(0, 4, 255);
    final map = Uint8List(side * side * 4);
    for (var y = 0; y < 3; y += 1) {
      for (var x = 1; x < 5; x += 1) {
        map.setAll((y * side + x) * 4, [9, 99, y * 5 + x, 255]);
      }
    }
    final input = aPluginStepsInput(
      composite,
      letters,
      celOf(canvas, {origin: BitmapTile(size: side, pixels: own)}),
      rows: [
        celOf(canvas, {origin: BitmapTile(size: side, pixels: map)}),
      ],
    );
    final made = (await layer.render(
      input: input,
      values: Float64List.fromList([0, 0, 0, 0]),
      moment: moment,
    ))!;
    final drawn = fxPluginTilesPixels(input, made);
    List<int> at(int x, int y) =>
        drawn.sublist((y * side + x) * 4, (y * side + x) * 4 + 4);
    expect(at(0, 0), [255, 255, 255, 255], reason: 'its own');
    for (var y = 0; y < 4; y += 1) {
      for (var x = 0; x < 6; x += 1) {
        if ((x, y) != (0, 0)) {
          final behind = x > 0 && x < 5 && y < 3
              ? [9, 99, y * 5 + x, 255]
              : [0, 0, 0, 0];
          expect(at(x, y), behind, reason: '($x, $y)');
        }
      }
    }
  });

  test('each pixel of a run has this machine\'s share, however many pixels '
      'there are', () async {
    // 🗣️an-endless-plugin-stalls-the-app-Q19: 「화소 하나의 몫으로 고정」 —
    // ↩️the share was the limit over the pixels, so a picture of more of
    // them was cut first.
    final blur = opened(fxPluginFixture('blur'), _blurOf());
    final endless = opened(fxPluginFixture('endless'), _blurOf());
    Future<FxPluginTiles?> drawn(GpuFxPlugin plugin, int side) =>
        plugin.render(
          input: clearInput(side, side),
          values: Float64List.fromList([2, 0, 0, 0]),
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
        input: clearInput(1, 1),
        values: Float64List(0),
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
  /// app takes. What the run made lands with no wait (`GpuPluginMade.land`).
  group('🚨a run goes on a worker (GpuPluginRenderer)', () {
    late bool corpus;
    setUp(() => corpus = debugWorkersRunHere);
    tearDown(() => debugWorkersRunHere = corpus);

    GpuFxPlugin anInvert() =>
        opened(fxPluginFixture('invert'), fxPluginDescriptionOf('a.invert'));

    test('the isolate that asks waits for the GPU none of the times it '
        'runs and lands what it made', () async {
      final invert = anInvert();
      Future<int> waited() async {
        final input = spreadInput();
        final before = debugWaitsHere;
        expect(
          await invert.render(
            input: input,
            values: Float64List(0),
            moment: moment,
          ),
          isNotNull,
        );
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
      final input = spreadInput();
      final drawing = invert.render(
        input: input,
        values: Float64List(0),
        moment: moment,
      );
      invert.close();
      expect(invert.debugLetGo, isFalse, reason: 'not under the run');
      final made = (await drawing)!;
      expect(invert.debugLetGo, isTrue, reason: 'once it has ended');
      expect(fxPluginTilesPixels(input, made).sublist(0, 4), inverted(0));
      expect(
        await invert.render(
          input: input,
          values: Float64List(0),
          moment: moment,
        ),
        isNull,
        reason: 'closed',
      );
    });
  });

  group('installed on this device', () {
    late Directory room;
    setUp(() => room = Directory.systemTemp.createTempSync('anicel_fx_gpu_'));
    tearDown(() => deleteTempQuietly(room));

    /// What [runner] draws of [spread]'s first pixel.
    Future<List<int>> firstPixel(FxPluginRunner runner) async {
      final input = spreadInput();
      final made = (await runner.render(
        input: input,
        values: Float64List(0),
        moment: moment,
      ))!;
      return fxPluginTilesPixels(input, made).sublist(0, 4);
    }

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
      expect(await firstPixel(plugins.runnerFor(description)!), inverted(0));
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
      Future<FxPluginTiles?> drawn() => plugins.runnerFor(description)!.render(
        input: clearInput(1, 1),
        values: Float64List(0),
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
      expect(await firstPixel(runner), inverted(0));
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

/// Writes what it is handed along its row from its left, a word in two
/// pixels — its low half, then its high, in red and green, opaque: a pixel
/// no alpha shows is drawn clear — the moment's four, then each value's
/// four words.
const _probe = '''
@compute @workgroup_size(16, 1)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  let i = i32(at.x) / 2;
  var word = 0;
  switch i {
    case 0: { word = anicel_frame(); }
    case 1: { word = anicel_time(); }
    case 2: { word = anicel_rate(); }
    case 3: { word = anicel_scale(); }
    default: { word = anicel_value((i - 4) / 4, (i - 4) % 4); }
  }
  let bits = bitcast<u32>(word);
  let half = select(bits & 0xffffu, bits >> 16u, at.x % 2u == 1u);
  anicel_out(half | 0xff000000u);
}

fn anicel_reach() -> u32 {
  return 0u;
}
''';
