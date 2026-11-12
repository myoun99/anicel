import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../helpers/a_plugin_that_shifts.dart';
import '../helpers/a_row_laid_through_its_plugins.dart';

/// 🚨★A KEPT PLUG-IN PICTURE MOVES TO THE ENGINE ONCE, HOWEVER MANY PLANS
/// PUT IT (ink-trails-further-on-intel-since-the-screen-waits-for-the-gpu,
/// 관제 2026-11-13 「한 번 만들고 계획마다 이름만」): a frame is planned
/// again at each write a pen makes, and each plan copied the kept picture
/// to the engine twice — 🔬25–40 ms of a write's 33 planned on the Surface
/// Pro 11. The plans name the one the step made ([GpuPutPicture]).
///
/// ⚠️A file of its own: [GpuPutPicture.liveBytes] counts the process's
/// pictures, and another test's would be collected under this one.
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

  test('plans that put a kept step name the picture it made: one moved to '
      'the engine', () async {
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
    final before = GpuPutPicture.liveBytes;

    for (var plans = 0; plans < 4; plans += 1) {
      await aRowLaidThroughItsPlugins(composite, letters, cel, effects);
    }

    expect(runner.renders, 1, reason: '⛔premise: kept, not run again');
    expect(GpuPutPicture.liveBytes - before, side * side * 4);
    // Held to here: what its step kept goes when it does.
    expect(cel.tiles, hasLength(1));
  });
}
