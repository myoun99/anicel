import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../widgets/field_slider.dart';
import 'berth_row.dart';

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
  ValueListenable<({Set<LayerId> layerIds, double opacity})?>? dragPreview,
  required void Function(LayerId layerId, double opacity) onChanged,
  void Function(LayerId layerId, double opacity)? onChangeEnd,
}) {
  // 18 at 1×, and its digits' growth where it is shown ([FieldSlider
  // .growthIn], text-scale-rail-rows). Built under the context that holds
  // it — the preview's builder's, or a [Builder]'s where there is none.
  Widget slider(BuildContext context, double value) => FieldSlider.opacity(
    name: '$keyPrefix-layer-opacity-${layer.id}',
    axis: axis,
    value: value,
    height: 18 + FieldSlider.growthIn(context),
    onChanged: (opacity) => onChanged(layerIdNow(context, layer.id), opacity),
    onChangeEnd: onChangeEnd == null
        ? null
        : (opacity) => onChangeEnd(layerIdNow(context, layer.id), opacity),
  );

  // ↩️R27 #9 read the camera row's here, off the window's dim notifier,
  // until the dim became the row's own opacity (F-363).
  final resting = layer.opacity.clamp(0.0, 1.0).toDouble();
  if (dragPreview == null) {
    return Builder(builder: (context) => slider(context, resting));
  }
  return ValueListenableBuilder<({Set<LayerId> layerIds, double opacity})?>(
    valueListenable: dragPreview,
    builder: (context, dragging, _) => slider(
      context,
      dragging != null &&
              dragging.layerIds.contains((BerthRow.of(context) ?? layer).id)
          ? dragging.opacity
          : resting,
    ),
  );
}
