import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/native/plan_plugins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'a_plugin_that_shifts.dart';
import 'a_row_laid_on_the_engine.dart';

/// What a plug-in's step at the head of [cel]'s chain is handed once the
/// plan has run through it — [cel] laid as a row ([aRowLaidOnce]), the
/// step's picture its content (its canvas and its tiles; a cel with no
/// tile is laid as none), [rows] the rows its layer values name, by slot:
/// what a test runs a device's plug-in over. Where [picture] is given, the
/// plug-in is asked over that part of it alone — from the paper's first
/// pixel, inside the cel's tiles, as a step's picture always is. Let go of
/// as the test ends.
EngineFxPluginInput aPluginStepsInput(
  GpuComposite composite,
  EngineLetters letters,
  BitmapSurface cel, {
  List<BitmapSurface?> rows = const [],
  ({int left, int top, int width, int height})? picture,
}) {
  final steps = _KeepsTheInput(rows);
  aRowLaidOnce(
    composite,
    letters,
    cel,
    [shiftingFxPluginEffect(by: 0)],
    plugins: (steps: steps, engine: appGpuEngine, ofThePensFrame: false),
  );
  final input = steps.input!;
  addTearDown(input.free);
  return switch (picture) {
    null => input,
    final picture => EngineFxPluginInput(
      input.read,
      picture: picture,
      paperOnTheGrid: input.paperOnTheGrid,
    ),
  };
}

/// Keeps the input of the one step it meets, which it leaves to be run.
final class _KeepsTheInput implements PluginSteps {
  _KeepsTheInput(this.rows);

  final List<BitmapSurface?> rows;
  EngineFxPluginInput? input;

  @override
  ({bool ran, FxPluginTiles? made}) stepOf(
    ResolvedLayerEffect effect,
    PluginStepInput input, {
    required int width,
    required int height,
    required ui.Rect paper,
    required bool ofThePensFrame,
    PluginStepSource? from,
  }) {
    this.input = input as EngineFxPluginInput;
    return (ran: false, made: null);
  }

  @override
  List<PluginStepRow> rowsOf(ResolvedLayerEffect effect) => [
    for (final (slot, row) in rows.indexed)
      (lineage: (_KeepsTheInput, slot), tiles: row?.tiles ?? const {}),
  ];
}
