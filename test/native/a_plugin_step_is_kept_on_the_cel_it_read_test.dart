import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/composite_tree_plan.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/ui/canvas/fx_plugin_stages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../helpers/a_plugin_that_shifts.dart';
import '../helpers/a_row_laid_through_its_plugins.dart';

/// 🚨★A PLUG-IN'S STEP IS KEPT ON THE CEL IT READ, where the cel is all it
/// read (float-warp-resamples-in-the-c-engine (2) ⓒ, 관제 2026-11-11):
/// what it made is a picture the app holds — a census row of its own
/// (`FxPluginStages.keptBytes`) — and what a hand holds over the cel goes
/// into what it reads, so the cel alone is not that input.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const side = 128;
  const canvas = CanvasSize(width: side, height: side);
  final origin = TileCoord(x: 0, y: 0);
  late GpuComposite composite;
  late EngineLetters letters;

  setUpAll(() async {
    composite = GpuComposite(appGpuEngine);
    letters = await EngineLetters.open(composite);
  });
  tearDownAll(() {
    composite.free();
  });

  /// A surface of one tile, [rgba] at [at] and clear elsewhere.
  BitmapSurface oneTile((int, int) at, List<int> rgba) {
    final pixels = Uint8List(side * side * 4)
      ..setAll((at.$2 * side + at.$1) * 4, rgba);
    return BitmapSurface(
      canvasSize: canvas,
      tileSize: side,
      tiles: {origin: BitmapTile(size: side, pixels: pixels)},
    );
  }

  ResolvedLayerEffect through(ShiftingFxPlugin runner) => ResolvedLayerEffect(
    kind: EffectKind.plugin,
    plugin: shiftingFxPluginDescription,
    values: const [],
    run: fxPluginRunOf(runner),
  );

  test('what a step kept is counted: its picture\'s bytes', () async {
    final cel = oneTile((3, 3), const [200, 10, 10, 255]);
    final before = FxPluginStages.keptBytes;

    await aRowLaidThroughItsPlugins(composite, letters, cel, [
      through(ShiftingFxPlugin(by: 0)),
    ]);

    expect(FxPluginStages.keptBytes - before, side * side * 4);
    // Held to here: what its step kept goes when it does.
    expect(cel.tiles, hasLength(1));
  });

  test('what a hand holds over the cel is read too: the step runs again '
      'over it', () async {
    final cel = oneTile((3, 3), const [200, 10, 10, 255]);
    final runner = ShiftingFxPlugin(by: 0);
    final effects = [through(runner)];
    await aRowLaidThroughItsPlugins(composite, letters, cel, effects);
    expect(runner.renders, 1, reason: '⛔premise: run over the cel');

    final float = oneTile((9, 9), const [10, 200, 10, 255]);
    await aRowLaidThroughItsPlugins(
      composite,
      letters,
      cel,
      effects,
      held: [EngineHeld(lineage: float, tiles: float.tiles)],
    );

    expect(runner.renders, 2);
    expect(
      runner.lastInput.sublist((9 * side + 9) * 4, (9 * side + 9) * 4 + 4),
      [10, 200, 10, 255],
      reason: 'what the hand holds, read',
    );
  });

  test('a step kept on the cel is laid as it was made', () async {
    final cel = oneTile((3, 3), const [200, 10, 10, 255]);
    final runner = ShiftingFxPlugin(by: 1);
    final effects = [through(runner)];
    final made = await aRowLaidThroughItsPlugins(
      composite,
      letters,
      cel,
      effects,
    );
    expect(
      made,
      isNot(await aRowLaidThroughItsPlugins(composite, letters, cel, const [])),
      reason: '⛔liveness: the plugin moves the cel',
    );

    final kept = await aRowLaidThroughItsPlugins(
      composite,
      letters,
      cel,
      effects,
    );

    expect(runner.renders, 1, reason: '⛔premise: kept, not run again');
    expect(kept, made);
  });

  // 🚨THE PLACE IS THE PEN'S FRAME'S, AND WHAT IS IN IT ANY RECORDING'S TO
  // READ (`FxPluginStages._keptSteps`; card a-stroke-step-reads-back-and-
  // pictures-each-tile-it-moved, 2026-11-13). One that asks under another
  // sample runs its own and takes nothing — pinned where the routes are
  // (`a_frame_that_waits_for_its_plugins_holds_its_picture_test`).
  test('a recording that is not of the pen\'s frame reads the step kept '
      'under the sample it asks with: it runs none', () async {
    final cel = oneTile((3, 3), const [200, 10, 10, 255]);
    final runner = ShiftingFxPlugin(by: 1);
    final effects = [through(runner)];
    final made = await aRowLaidThroughItsPlugins(
      composite,
      letters,
      cel,
      effects,
    );
    expect(runner.renders, 1, reason: '⛔premise: run, and kept');

    final ahead = await aRowLaidThroughItsPlugins(
      composite,
      letters,
      cel,
      effects,
      ofThePensFrame: false,
    );

    expect(runner.renders, 1);
    expect(ahead, made);
  });
}
