import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../widgets/field_slider.dart';

/// A layer row's opacity slider, live-following the session's drag preview
/// when it targets this layer (the master bar sweep, UI-R6 #2).
///
/// 🚨ONE widget for the timeline row and the storyboard's SE row — each
/// built the same slider and preview follow by hand (the audit's clone
/// scan, 2026-09-03).
Widget layerOpacityField({
  required Layer layer,
  required String keyPrefix,
  Axis axis = Axis.horizontal,
  ValueListenable<double>? override,
  ValueListenable<({Set<LayerId> layerIds, double opacity})?>? dragPreview,
  required void Function(LayerId layerId, double opacity) onChanged,
  void Function(LayerId layerId, double opacity)? onChangeEnd,
}) {
  // 18 at 1×, and its digits' growth where it is shown ([FieldSlider
  // .growthIn], text-scale-rail-rows).
  Widget slider(double value) => Builder(
    builder: (context) => FieldSlider.opacity(
      key: ValueKey<String>('$keyPrefix-layer-opacity-${layer.id}'),
      axis: axis,
      value: value,
      height: 18 + FieldSlider.growthIn(context),
      onChanged: (opacity) => onChanged(layer.id, opacity),
      onChangeEnd: onChangeEnd == null
          ? null
          : (opacity) => onChangeEnd(layer.id, opacity),
    ),
  );

  // R27 #9: a row whose opacity IS a view notifier (the camera row)
  // reads it here — the slider follows the drag by itself, no host
  // rebuild in the loop.
  if (override != null) {
    return ValueListenableBuilder<double>(
      valueListenable: override,
      builder: (context, value, _) => slider(value.clamp(0.0, 1.0)),
    );
  }

  final resting = layer.opacity.clamp(0.0, 1.0).toDouble();
  if (dragPreview == null) {
    return slider(resting);
  }
  return ValueListenableBuilder<({Set<LayerId> layerIds, double opacity})?>(
    valueListenable: dragPreview,
    builder: (context, dragging, _) => slider(
      dragging != null && dragging.layerIds.contains(layer.id)
          ? dragging.opacity
          : resting,
    ),
  );
}
