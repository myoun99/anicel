import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart';

import '../models/layer_effect.dart';

/// The picture a plug-in's step runs over, held until it is run.
abstract interface class PluginStepInput {
  /// Its pixels, premultiplied RGBA row after row; null where there are
  /// none to read.
  Future<Uint8List?> premultiplied();

  void free();
}

/// The plug-ins' steps a plan meets, in the order it meets them: run over
/// the picture the chain had come to, a round of the plan each
/// (`FxPluginStages`, 🗣️I-132-Q34 a).
abstract interface class PluginSteps {
  /// What [effect]'s plugin made of [input], [width] × [height] with
  /// [paper] where the paper lies in its pixels, premultiplied RGBA row
  /// after row: `ran` false where it is still to be run, [input] kept until
  /// it is; `premultiplied` null where it ran and failed — drawn as if off.
  ({bool ran, Uint8List? premultiplied}) stepOf(
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
