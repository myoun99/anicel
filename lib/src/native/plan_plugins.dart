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

/// What a step's input is made of, where a plan can say: [source] — the
/// row's own surface, or what the plug-in before it made — and the
/// effects run over it since, [before].
///
/// 🚨★WHAT LETS A STEP BE KEPT PAST ITS RECORDING (float-warp-resamples-in-
/// the-c-engine (2) ⓒ, 관제 2026-11-11): a frame is recorded again at every
/// write a pen's step makes, and a plug-in met in it was run again each
/// time — on a row the pen was not on as well (🔬4 steps elsewhere, 4 runs
/// more, 11-11). The same source under the same effects is the same
/// input: the step it made is kept on the source (`FxPluginStages`).
typedef PluginStepSource = ({
  Object source,
  List<ResolvedLayerEffect> before,
});

/// The plug-ins' steps a plan meets, in the order it meets them: run over
/// the picture the chain had come to, a round of the plan each
/// (`FxPluginStages`, 🗣️I-132-Q34 a).
abstract interface class PluginSteps {
  /// What [effect]'s plugin made of [input], [width] × [height] with
  /// [paper] where the paper lies in its pixels, straight RGBA row after
  /// row, on the engine: `ran` false where it is still to be run, [input]
  /// kept until it is; `made` null where it ran and failed — drawn as if
  /// off. [from] says what [input] is made of, where the plan can say —
  /// and what the step makes is kept on that past the plan where the plan
  /// is [ofThePensFrame] ([PlanPlugins]), by no other.
  ({bool ran, GpuPutPicture? made}) stepOf(
    ResolvedLayerEffect effect,
    PluginStepInput input, {
    required int width,
    required int height,
    required ui.Rect paper,
    required bool ofThePensFrame,
    PluginStepSource? from,
  });
}

/// The steps a plan's plug-ins are run through, the engine what they read
/// is read back on, and whether the plan is of the frame a canvas stands
/// on to draw — its chains laid into that frame's holds
/// (`EngineChainHolds.ofThePensFrame`).
typedef PlanPlugins = ({
  PluginSteps steps,
  GpuEngine engine,
  bool ofThePensFrame,
});
