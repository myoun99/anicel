import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/native/plan_plugins.dart' show PlanPlugins;
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/canvas/fx_plugin_stages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/a_row_laid_on_the_engine.dart';
import '../../helpers/tiles_on_the_engine.dart';

/// 🗣️I-132-Q34 a (유저 2026-10-30): 「어디에 걸어도 돌고, 결과가 올 때까지
/// 그 프레임의 직전 완성 그림에 머문다」 — a plugin past a cel's own pixels
/// runs over the picture its chain made before it, read back from the GPU,
/// where a route can wait for it ([FxPluginStages]); laid as if off where
/// it cannot.
///
/// ↩️Laid through the Flutter chain (`applyEffectSteps`) until it went
/// (the-flutter-fx-chain-is-a-second-chain): the rounds are the engine's
/// now, through the same stages.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const width = 6;
  const height = 2;
  const paper = Rect.fromLTWH(0, 0, width + 0.0, height + 0.0);
  const red = [200, 10, 20, 255];
  const clear = [0, 0, 0, 0];
  late GpuComposite composite;
  late EngineLetters letters;

  setUpAll(() async {
    composite = GpuComposite(appGpuEngine);
    letters = await EngineLetters.open(composite);
  });
  tearDownAll(() {
    composite.free();
  });

  /// A cel [width] × [rows] with red at (0, 0) and nothing else.
  BitmapSurface source({int rows = height}) => BitmapSurface(
    canvasSize: CanvasSize(width: width, height: rows),
    tileSize: defaultCelTileSize,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: defaultCelTileSize,
        pixels: Uint8List(BitmapTile.bytesFor(defaultCelTileSize))
          ..setAll(0, red),
      ),
    },
  );

  ResolvedLayerEffect plugin(FxPluginRunner runner) => ResolvedLayerEffect(
    kind: EffectKind.plugin,
    plugin: shiftingFxPluginDescription,
    values: const [],
    run: fxPluginRunOf(runner),
  );

  /// The top row of what the engine laid, a tile row by row, pixel by
  /// pixel.
  List<List<int>> rowOf(Uint8List laid) => [
    for (var x = 0; x < width; x += 1) laid.sublist(x * 4, x * 4 + 4),
  ];

  /// The steps a route that waits records for this round.
  PlanPlugins waiting() => (
    steps: FxPluginStages.recording!,
    engine: appGpuEngine,
    ofThePensFrame: true,
  );

  /// What a plugin reaching [reach] is handed of the row [source] lays:
  /// the row's content — the canvas and the tile it holds — grown by
  /// [reach], its chain run there, before the row's pose
  /// (rowExtentWithItsReach). ↩️The paper alone while these rounds ran
  /// on the Flutter chain, handed a picture the paper's size
  /// (the-flutter-fx-chain-is-a-second-chain).
  ({int left, int top, int width, int height}) handedReaching(int reach) => (
    left: -reach,
    top: -reach,
    width: defaultCelTileSize + 2 * reach,
    height: defaultCelTileSize + 2 * reach,
  );

  /// The pixel at the paper's ([x], [y]) of the picture [runner] was last
  /// handed.
  List<int> handedAt(ShiftingFxPlugin runner, int x, int y) {
    final picture = runner.inputs.last;
    final at = ((y - picture.top) * picture.width + (x - picture.left)) * 4;
    return runner.lastInput.sublist(at, at + 4);
  }


  test('is a step of its own in a chain past the head, as far as its plugin '
      'reaches — and none where it has no run on this device', () {
    final runner = ShiftingFxPlugin(by: 2);
    final plan = resolveCompositeEffectPlan([plugin(runner)], paper: paper);
    expect(plan.preSteps.single.lead, isA<PluginEffect>());
    expect(plan.outsetPixels, 2);

    final off = ResolvedLayerEffect(
      kind: EffectKind.plugin,
      plugin: shiftingFxPluginDescription,
      values: const [],
    );
    expect(
      resolveCompositeEffectPlan([off], paper: paper).isSingleDraw,
      isTrue,
    );
  });

  // ↩️The head of a cel's chain bounded it so alone, by what the cel could
  // store, while it ran on the CPU (float-warp-resamples-in-the-c-engine
  // (2), 2026-11-11): one plugin, one bound.
  test('reaches no farther than the paper is long, whatever it names', () {
    final plan = resolveCompositeEffectPlan([
      plugin(ShiftingFxPlugin(by: 1000)),
    ], paper: paper);
    expect(plan.outsetPixels, width);
    // ⛔liveness: a reach inside the bound is the plugin's own.
    expect(
      resolveCompositeEffectPlan([
        plugin(ShiftingFxPlugin(by: width - 1)),
      ], paper: paper).outsetPixels,
      width - 1,
    );
  });

  // 🗣️관제 2026-11-12 22:25 (an-endless-plugin-stalls-the-app ④): its build
  // opened off the isolate that asks, a plugin cannot say how far it reaches
  // till it is.
  test('one whose build is still to come reaches as far as the paper is '
      'long, asked nothing and told nothing till it is open', () {
    final opening = _OpensLater(ShiftingFxPlugin(by: 1));
    var told = 0;
    ResolvedLayerEffect telling() => ResolvedLayerEffect(
      kind: EffectKind.plugin,
      plugin: shiftingFxPluginDescription,
      values: const [],
      run: fxPluginRunOf(opening, told: ({required failed}) => told += 1),
    );
    expect(
      resolveCompositeEffectPlan([telling()], paper: paper).outsetPixels,
      width,
    );
    expect(opening.askedEarly, 0);
    expect(told, 0, reason: 'not failed: still to come');
    // ⛔liveness: open, the reach is its own.
    opening.open();
    expect(
      resolveCompositeEffectPlan([telling()], paper: paper).outsetPixels,
      1,
    );
  });


  test('a route that waits lays it again once the plugin has run, and the '
      'step lays what it made', () async {
    final runner = ShiftingFxPlugin(by: 2);
    var rounds = 0;
    final row = rowOf(
      await aRowLaidOnTheEngine(
        composite,
        letters,
        source(),
        [plugin(runner)],
        recorded: () => rounds += 1,
      ),
    );

    expect(row[0], clear);
    expect(row[2], red);
    expect(rounds, 2, reason: 'one round to meet it, one to lay it');
    expect(runner.renders, 1);
    // Handed the picture its chain made, where it lies.
    expect(runner.inputs.single, handedReaching(2));
  });

  test('🚨a route that waits for a plugin whose build is still to come '
      'lays it again once it is open — its step run once, over what it '
      'reaches then', () async {
    final runner = ShiftingFxPlugin(by: 2);
    final opening = _OpensLater(runner);
    final waits = <bool>[];
    var rounds = 0;
    final laying = aRowLaidOnTheEngine(
      composite,
      letters,
      source(),
      [plugin(opening)],
      recorded: () => rounds += 1,
      waitsForKernels: waits.add,
    );
    await pumpEventQueue();
    expect(waits, [true], reason: 'it waits for the open');
    expect(runner.renders, 0);

    opening.open();
    final row = rowOf(await laying);
    expect(row[2], red);
    expect(waits, [true, false]);
    expect(opening.askedEarly, 0);
    expect(runner.renders, 1, reason: 'run once, once open');
    expect(runner.inputs.single, handedReaching(2));
    expect(
      rounds,
      3,
      reason: 'the one that waited, then one to meet it and one to lay it',
    );
  });

  test('handed its picture where it lies on the paper, and each row it '
      'names on the same grid, as the row\'s own cel holds it', () async {
    final reading = FxPluginDescription.fromJson({
      ...shiftingFxPluginDescription.toJson(),
      'params': [
        {'id': 'map', 'kind': 'layer', 'label': 'Map'},
      ],
    })!;
    const green = [0, 200, 0, 255];
    const map = LayerId('map');
    final runner = ShiftingFxPlugin(by: 1);
    final effect = ResolvedLayerEffect(
      kind: EffectKind.plugin,
      plugin: reading,
      values: const [0],
      layers: const {'map': map},
      run: fxPluginRunOf(
        runner,
        rows: {
          // A cel green at its (1, 0).
          map: BitmapSurface(
            canvasSize: const CanvasSize(width: 4, height: height),
            tileSize: defaultCelTileSize,
            tiles: {
              TileCoord(x: 0, y: 0): tileOnEngine(
                BitmapTile(
                  size: defaultCelTileSize,
                  pixels: Uint8List(BitmapTile.bytesFor(defaultCelTileSize))
                    ..setAll(4, green),
                ),
              ),
            },
          ),
        },
      ),
    );
    addTearDown(() => EngineTileLedger.debugBeforeRead = null);
    var reads = 0;
    EngineTileLedger.debugBeforeRead = (_) => reads += 1;

    // The row posed two left on a paper four wide, reached past by one: its
    // chain runs on its own grid, before its pose — what the plugin is
    // handed lies one up and left of the paper's first pixel, wherever the
    // pose puts the row.
    await aRowLaidOnTheEngine(
      composite,
      letters,
      BitmapSurface(
        canvasSize: const CanvasSize(width: 4, height: height),
        tileSize: defaultCelTileSize,
        tiles: source().tiles,
      ),
      [effect],
      placement: const GuideTransform(1, 0, 0, 1, -2, 0),
    );

    final picture = handedReaching(1);
    expect(runner.inputs.single, picture);
    final row = runner.lastLayers.single;
    expect(
      (row.left, row.top, row.width, row.height),
      (picture.left, picture.top, picture.width, picture.height),
    );
    bool isGreen(int at) =>
        row.pixels.sublist(at * 4, at * 4 + 4).join(',') == green.join(',');
    expect(
      {
        for (var at = 0; at < row.width * row.height; at += 1)
          if (isGreen(at))
            (at % row.width + row.left, at ~/ row.width + row.top),
      },
      {(1, 0)},
      reason: 'the cel\'s (1, 0), where it lies on this grid',
    );
    expect(reads, 1, reason: 'the row is read back from the engine');
  });

  test('a row it names with no cel there is handed clear, at its place; one '
      'not in its cut is none', () async {
    final reading = FxPluginDescription.fromJson({
      ...shiftingFxPluginDescription.toJson(),
      'params': [
        {'id': 'map', 'kind': 'layer', 'label': 'Map'},
      ],
    })!;
    const map = LayerId('map');
    Future<ShiftingFxPlugin> ranWith(Map<LayerId, BitmapSurface?> rows) async {
      final runner = ShiftingFxPlugin(by: 0);
      await aRowLaidOnTheEngine(composite, letters, source(), [
        ResolvedLayerEffect(
          kind: EffectKind.plugin,
          plugin: reading,
          values: const [0],
          layers: const {'map': map},
          run: fxPluginRunOf(runner, rows: rows),
        ),
      ]);
      expect(runner.renders, 1, reason: '⛔fixture: the step ran');
      return runner;
    }

    final noCel = await ranWith({map: null});
    expect(noCel.lastValues[0], 0, reason: 'its place among the rows');
    final picture = noCel.inputs.single;
    expect(
      noCel.lastLayers.single.pixels,
      Uint8List(picture.width * picture.height * 4),
    );

    final notInCut = await ranWith(const {});
    expect(notInCut.lastValues[0], -1);
    expect(notInCut.lastLayers, isEmpty);
  });

  for (final (what, rows, metAs)
      in [
        (
          'over a picture of another size',
          height * 2,
          (ResolvedLayerEffect effect) => effect,
        ),
        (
          'as another sample',
          height,
          (ResolvedLayerEffect effect) => ResolvedLayerEffect(
            kind: effect.kind,
            plugin: effect.plugin,
            values: effect.values,
            frame: 1,
            run: effect.run,
          ),
        ),
      ]) {
    test('a step met again $what is run again', () async {
      final runner = ShiftingFxPlugin(by: 0);
      final step = plugin(runner);
      var rounds = 0;

      await FxPluginStages.recordedThrough(() {
        rounds += 1;
        return rounds == 1
            ? aRowLaidOnce(
                composite,
                letters,
                source(),
                [step],
                plugins: waiting(),
              )
            : aRowLaidOnce(
                composite,
                letters,
                source(rows: rows),
                [metAs(step)],
                plugins: waiting(),
              );
      }, discard: (_) {});

      expect(runner.renders, 2, reason: 'once for each it was met as');
      expect(rounds, 3);
    });
  }

  test('a route that cannot wait lays it as if off', () {
    final runner = ShiftingFxPlugin(by: 2);

    final row = rowOf(
      aRowLaidOnce(composite, letters, source(), [plugin(runner)]),
    );

    expect(row[0], red);
    expect(row[2], clear);
    expect(runner.renders, 0);
  });

  test('a plugin over another\'s picture is run a round after it, over what '
      'the first made', () async {
    final first = ShiftingFxPlugin(by: 1);
    final second = ShiftingFxPlugin(by: 2);
    var rounds = 0;
    final row = rowOf(
      await aRowLaidOnTheEngine(
        composite,
        letters,
        source(),
        [plugin(first), plugin(second)],
        recorded: () => rounds += 1,
      ),
    );

    expect(row[3], red);
    expect(row[0], clear);
    expect(rounds, 3);
    expect((first.renders, second.renders), (1, 1));
    // The second was handed the first's picture: red at 1.
    expect(handedAt(second, 1, 0), red);
  });

  test('a plugin that fails is laid as if off, and asked no more', () async {
    final runner = ShiftingFxPlugin(by: 2, fails: true);
    var rounds = 0;
    final row = rowOf(
      await aRowLaidOnTheEngine(
        composite,
        letters,
        source(),
        [plugin(runner)],
        recorded: () => rounds += 1,
      ),
    );

    expect(row[0], red);
    expect(rounds, 2);
    expect(runner.renders, 1);
  });

  // ↩️A moment's scale was how many of its picture's pixels a canvas pixel
  // was while the Flutter chain rastered a step at a route's own
  // resolution (the-flutter-fx-chain-is-a-second-chain).
  test('is handed its moment a canvas pixel a pixel, as the engine runs a '
      'chain, whatever scale its run was met at', () async {
    final runner = ShiftingFxPlugin(by: 0);
    await aRowLaidOnTheEngine(composite, letters, source(), [
      ResolvedLayerEffect(
        kind: EffectKind.plugin,
        plugin: shiftingFxPluginDescription,
        values: const [],
        run: FxPluginRun(
          runner: runner,
          moment: (frameIndex: 0, time: 0, frameRate: 24, scale: 3.0),
          rows: const {},
        ),
      ),
    ]);

    expect(runner.renders, 1, reason: '⛔fixture: the step ran');
    expect(runner.lastMoment.scale, 1);
  });

  test('a step tells its run how it went: failed — its picture, or how far '
      'it reaches, not given — or drew '
      '(🗣️a-failed-plugin-shows-the-cel-silently-Q1)', () async {
    Future<List<bool>> toldBy(ShiftingFxPlugin runner) async {
      final heard = <bool>[];
      await aRowLaidOnTheEngine(composite, letters, source(), [
        ResolvedLayerEffect(
          kind: EffectKind.plugin,
          plugin: shiftingFxPluginDescription,
          values: const [],
          run: FxPluginRun(
            runner: runner,
            moment: (frameIndex: 0, time: 0, frameRate: 24, scale: 1),
            rows: const {},
            told: ({required failed}) => heard.add(failed),
          ),
        ),
      ]);
      return heard;
    }

    expect(await toldBy(ShiftingFxPlugin(by: 2, fails: true)), [true]);
    expect(await toldBy(ShiftingFxPlugin(by: 2)), [false]);
    expect((await toldBy(ShiftingFxPlugin(reachFails: true))).toSet(), {true});
  });
}

/// [_build], its build still to come till [open] ([FxPluginRunner.toCome]),
/// counting what it is asked before.
final class _OpensLater implements FxPluginRunner {
  _OpensLater(this._build);

  final FxPluginRunner _build;
  final Completer<void> _opened = Completer();

  /// How often its reach or its picture was asked before it was open.
  int askedEarly = 0;

  void open() => _opened.complete();

  void _asked() {
    if (!_opened.isCompleted) {
      askedEarly += 1;
    }
  }

  @override
  Future<void>? get toCome => _opened.isCompleted ? null : _opened.future;

  @override
  int? reach(Float64List values, FxPluginMoment moment) {
    _asked();
    return _build.reach(values, moment);
  }

  @override
  Future<Uint8List?> render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) {
    _asked();
    return _build.render(
      input: input,
      values: values,
      layers: layers,
      moment: moment,
    );
  }

  @override
  void close() => _build.close();

  @override
  bool get closed => _build.closed;
}
