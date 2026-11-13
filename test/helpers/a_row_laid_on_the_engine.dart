import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart' show PasteboardBounds;
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/composite_tree_plan.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/native/plan_plugins.dart' show PlanPlugins;
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show LayerPlacement;
import 'package:anicel/src/ui/canvas/fx_plugin_stages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

/// The straight pixels a row of [surface] lays through [effects] — at
/// [placement] where one is named, what a hand holds over it [held] — over
/// its canvas, one tile of it, laid by [composite] as a route that waits
/// for its plug-ins lays it: a round of the plan each, till every step has
/// run. [recorded] hears each round's end — the one a build still to come
/// stops too —, [waitsForKernels] each wait for that build.
///
/// Laid as the frame a canvas stands on to draw is — what its steps make
/// kept on the cel — or, [ofThePensFrame] false, as a frame made ahead is
/// (`PlanPlugins`).
///
/// The one way a test lays a row on the engine, a plug-in on it or not.
/// ↩️`aRowLaidThroughItsPlugins` while a row without one was laid through
/// the Flutter chain, till it went (the-flutter-fx-chain-is-a-second-chain).
Future<Uint8List> aRowLaidOnTheEngine(
  GpuComposite composite,
  EngineLetters letters,
  BitmapSurface surface,
  List<ResolvedLayerEffect> effects, {
  LayerPlacement? placement,
  List<EngineHeld> held = const [],
  void Function()? recorded,
  void Function(bool waits)? waitsForKernels,
  bool ofThePensFrame = true,
}) async {
  final ledger = EngineTileLedger(appGpuEngine);
  addTearDown(ledger.pool.free);
  late Uint8List pixels;
  await FxPluginStages.recordedThrough<void>(
    () {
      try {
        pixels = aRowLaidOnce(
          composite,
          letters,
          surface,
          effects,
          placement: placement,
          held: held,
          plugins: (
            steps: FxPluginStages.recording!,
            engine: appGpuEngine,
            ofThePensFrame: ofThePensFrame,
          ),
          ledger: ledger,
        );
      } finally {
        recorded?.call();
      }
    },
    discard: (_) {},
    waitsForKernels: waitsForKernels,
  );
  return pixels;
}

/// One round of [aRowLaidOnTheEngine]: [surface]'s row through [effects]
/// laid once, its plug-ins' steps those [plugins] hold — as if off where
/// it names none, as a route that cannot wait lays them — its tiles on the
/// engine through [ledger], one of its own where it is given none.
Uint8List aRowLaidOnce(
  GpuComposite composite,
  EngineLetters letters,
  BitmapSurface surface,
  List<ResolvedLayerEffect> effects, {
  LayerPlacement? placement,
  List<EngineHeld> held = const [],
  PlanPlugins? plugins,
  EngineTileLedger? ledger,
}) {
  final canvas = surface.canvasSize;
  final tiles = ledger ?? EngineTileLedger(appGpuEngine);
  if (ledger == null) {
    addTearDown(tiles.pool.free);
  }
  return tiles.held((hold) {
    final plan = GpuPlan();
    try {
      planCompositeTree(
        plan,
        [
          CompositeLeaf<EngineRow>(
            EngineTiles(
              lineage: surface,
              surface: surface,
              placement: placement,
              effects: effects,
              held: held,
            ),
          ),
        ],
        hold: hold,
        paper: canvas.canvasRect,
        letters: letters,
        plugins: plugins,
      );
      final out = composite.run(
        tiles.pool,
        plan,
        const [(0, 0)],
        (0, 0, canvas.width, canvas.height),
      );
      try {
        return out.read();
      } finally {
        out.free();
      }
    } finally {
      plan.free();
    }
  });
}
