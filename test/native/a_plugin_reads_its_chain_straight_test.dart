import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/core/rgba_premultiply.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';

import '../helpers/a_plugin_that_shifts.dart';
import '../helpers/a_row_laid_on_the_engine.dart';

/// 🚨★★A PLUG-IN IS HANDED ITS CHAIN STRAIGHT, AS THE CHAIN HOLDS IT,
/// WHEREVER IT STANDS (float-warp-resamples-in-the-c-engine (2) ⓐ, 관제
/// 2026-11-11).
///
/// A row's chain holds straight words and keeps them so for a plug-in
/// (`GpuChainRead`), and a plug-in reads and draws straight
/// (`FxPluginInput`): the first plug-in of a cel's chain is handed the
/// cel's own bytes, the next what the first made, and what the last made
/// is what the row lays — a colour at alpha 3 the colour it is, each way.
///
/// A pixel a plug-in leaves clear is clear whatever colour it gave it, by
/// the device's run (plugin/tests.rs, `a_run_over_a_chains_tiles_lays_on_
/// them_what_the_cpu_draws`) — ↩️by the step here till 2026-11-15, which
/// read it back to clear it. ↩️And the read of a step's chain went on a
/// worker (관제 2026-11-12 08:5x) — a step reads none since.
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

  /// The alphas a premultiplied byte keeps least of a colour at, among
  /// others.
  const alphas = [3, 1, 2, 7, 66, 128, 254, 255];

  /// A cel of one tile, a spread of colours in bands of [alphas].
  BitmapSurface cel() {
    final pixels = Uint8List(side * side * 4);
    for (var y = 0; y < side; y += 1) {
      for (var x = 0; x < side; x += 1) {
        pixels.setAll((y * side + x) * 4, [
          (x * 7 + 13) & 255,
          (y * 11 + 200) & 255,
          (x * y + 91) & 255,
          alphas[(x + y) % alphas.length],
        ]);
      }
    }
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

  Future<Uint8List> laid(
    BitmapSurface surface,
    List<ResolvedLayerEffect> effects,
  ) => aRowLaidOnTheEngine(composite, letters, surface, effects);

  test("the first plug-in of a cel's chain is handed the cel's own bytes, "
      'the next what the first made, and the row lays what the last '
      'made', () async {
    final surface = cel();
    final own = surface.tiles[origin]!.readPixels(
      (_, view) => Uint8List.fromList(view),
    );
    // ⛔liveness: colours a premultiplied byte cannot hold.
    expect(straightRgbaFor(premultipliedRgbaCopy(own)), isNot(own));

    final first = ShiftingFxPlugin(by: 0);
    final next = ShiftingFxPlugin(by: 0);
    final shown = await laid(surface, [through(first), through(next)]);

    expect([first.renders, next.renders], [1, 1]);
    expect(first.inputs.single, (left: 0, top: 0, width: side, height: side));
    expect(first.lastInput, own, reason: "the cel's own bytes");
    expect(next.lastInput, own, reason: 'what the first made');
    expect(shown, await laid(surface, const []), reason: 'what the last made');
  });
}
