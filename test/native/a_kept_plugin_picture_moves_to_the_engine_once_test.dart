import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../helpers/a_plugin_that_shifts.dart';
import '../helpers/a_row_laid_on_the_engine.dart';

/// 🚨★A KEPT PLUG-IN PICTURE MOVES TO THE ENGINE ONCE, HOWEVER MANY PLANS
/// PUT IT (ink-trails-further-on-intel-since-the-screen-waits-for-the-gpu,
/// 관제 2026-11-13 「한 번 만들고 계획마다 이름만」): a frame is planned
/// again at each write a pen makes, and each plan copied the kept picture
/// to the engine twice — 🔬25–40 ms of a write's 33 planned on the Surface
/// Pro 11. The plans name the tiles the step made, in the engine's pool
/// since 2026-11-15 (a-plugin-step-goes-through-the-cpu-and-back) — ↩️a
/// picture moved there once till then (`GpuPutPicture`).
///
/// ⚠️A file of its own: [EngineTileLedger.slotCount] counts the process's
/// tiles, and another test's would be collected under this one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const side = 128;
  late GpuComposite composite;
  late EngineLetters letters;

  setUpAll(() async {
    composite = GpuComposite(appGpuEngine);
    letters = await EngineLetters.open(composite);
  });
  tearDownAll(() {
    composite.free();
  });

  test('plans that put a kept step name the tiles it made: stored in the '
      'pool once', () async {
    final cel = BitmapSurface(
      canvasSize: const CanvasSize(width: side, height: side),
      tileSize: side,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          size: side,
          pixels: Uint8List(side * side * 4)
            ..setAll((3 * side + 3) * 4, const [200, 10, 10, 255]),
        ),
      },
    );
    // Moving nothing, it reaches nothing past the cel: its picture is the
    // cel's size.
    final runner = ShiftingFxPlugin(by: 0);
    final effects = [
      ResolvedLayerEffect(
        kind: EffectKind.plugin,
        plugin: shiftingFxPluginDescription,
        values: const [],
        run: fxPluginRunOf(runner),
      ),
    ];
    // The first plans store the cel's tiles and what its step made; the
    // ones after name them.
    await aRowLaidOnTheEngine(composite, letters, cel, effects);
    final stored = EngineTileLedger.instance.slotCount;

    for (var plans = 1; plans < 4; plans += 1) {
      await aRowLaidOnTheEngine(composite, letters, cel, effects);
    }

    expect(runner.renders, 1, reason: '⛔premise: kept, not run again');
    expect(EngineTileLedger.instance.slotCount, stored);
    // Held to here: what its step kept goes when it does.
    expect(cel.tiles, hasLength(1));
  });
}
