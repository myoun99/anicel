import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/composite_tree_plan.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/ui/canvas/fx_plugin_stages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

/// The straight pixels a row of [surface] lays through [effects], what a
/// hand holds over it [held], over its canvas — laid by [composite] as a
/// route that waits for its plug-ins lays it: a round of the plan each,
/// till every step has run. [recorded] hears each round's end.
///
/// Laid as the frame a canvas stands on to draw is — what its steps make
/// kept on the cel — or, [ofThePensFrame] false, as a frame made ahead is
/// (`PlanPlugins`).
Future<Uint8List> aRowLaidThroughItsPlugins(
  GpuComposite composite,
  EngineLetters letters,
  BitmapSurface surface,
  List<ResolvedLayerEffect> effects, {
  List<EngineHeld> held = const [],
  void Function()? recorded,
  bool ofThePensFrame = true,
}) async {
  final canvas = surface.canvasSize;
  final ledger = EngineTileLedger(appGpuEngine);
  addTearDown(ledger.pool.free);
  late Uint8List pixels;
  await FxPluginStages.recordedThrough<void>(() {
    final stages = FxPluginStages.recording!;
    pixels = ledger.held((hold) {
      final plan = GpuPlan();
      try {
        planCompositeTree(
          plan,
          [
            CompositeLeaf<EngineRow>(
              EngineTiles(
                lineage: surface,
                surface: surface,
                effects: effects,
                held: held,
              ),
            ),
          ],
          hold: hold,
          paper: canvas.canvasRect,
          letters: letters,
          plugins: (
            steps: stages,
            engine: appGpuEngine,
            ofThePensFrame: ofThePensFrame,
          ),
        );
        final out = composite.run(
          ledger.pool,
          plan,
          const [(0, 0)],
          (0, 0, canvas.width, canvas.height),
        );
        try {
          return out.read();
        } finally {
          out.free();
          recorded?.call();
        }
      } finally {
        plan.free();
      }
    });
  }, discard: (_) {});
  return pixels;
}
