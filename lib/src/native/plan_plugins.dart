import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart';

import '../models/layer_effect.dart';

/// The picture a plug-in's step runs over, held until it is run.
///
/// 🚨STRAIGHT, AS THE PLUG-IN READS AND DRAWS (float-warp-resamples-in-the-
/// c-engine (2) ⓐ, 관제 2026-11-11). ↩️It answered premultiplied and the
/// step's picture went back premultiplied: the engine's chain, which reads
/// and puts straight, was premultiplied for the plug-in and straightened
/// again each way, and a low alpha's colour was rounded away on the way —
/// the head of a cel's chain read the cel's own bytes, a plug-in past it
/// their round trip.
abstract interface class PluginStepInput {
  /// Its pixels, straight RGBA row after row; null where there are none to
  /// read.
  Future<Uint8List?> straight();

  void free();
}

/// The plug-ins' steps a plan meets, in the order it meets them: run over
/// the picture the chain had come to, a round of the plan each
/// (`FxPluginStages`, 🗣️I-132-Q34 a).
abstract interface class PluginSteps {
  /// What [effect]'s plugin made of [input], [width] × [height] with
  /// [paper] where the paper lies in its pixels, straight RGBA row after
  /// row: `ran` false where it is still to be run, [input] kept until it
  /// is; `straight` null where it ran and failed — drawn as if off.
  ({bool ran, Uint8List? straight}) stepOf(
    ResolvedLayerEffect effect,
    PluginStepInput input, {
    required int width,
    required int height,
    required ui.Rect paper,
  });
}

/// The steps a plan's plug-ins are run through, and the engine what they
/// read is read back on.
typedef PlanPlugins = ({PluginSteps steps, GpuEngine engine});
