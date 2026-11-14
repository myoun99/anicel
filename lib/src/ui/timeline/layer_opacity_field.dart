import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/se_sound.dart';
import '../widgets/field_slider.dart';
import 'berth_row.dart';

/// How thick a rail row's bar stands where [context] shows it: 18 at 1×,
/// and its digits' growth ([FieldSlider.growthIn], text-scale-rail-rows).
/// The opacity bar's and the S row's Total's — one bar, one size (F-577).
double layerRailBarHeightIn(BuildContext context) =>
    18 + FieldSlider.growthIn(context);

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
  // Built under the context that holds it — the preview's builder's, or a
  // [Builder]'s where there is none.
  Widget slider(BuildContext context, double value) => FieldSlider.opacity(
    name: '$keyPrefix-layer-opacity-${layer.id}',
    axis: axis,
    value: value,
    height: layerRailBarHeightIn(context),
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

/// An S row's Total — the opacity bar to 200 % ([SeSound.maxVolume]).
///
/// 🗣️F-577 (유저 2026-11-10): 「총 볼륨 막대 둠. 연필이나 +, -버튼은
/// 필요없음. 불투명도막대랑 완전 동일한 디자인/크기」. ↩️It was the speaker
/// window's bar (I-145-Q1 「따로 한 값 — 두 입구」); the row holds it now, and
/// its 「오디오」 group's lane is still the other door.
///
/// It writes on RELEASE, as the window's did: a write is an undo step and
/// re-uploads the whole live audio schedule. The bar shows the drag
/// itself meanwhile ([FieldSlider] echoes an active gesture).
Widget layerTotalVolumeField({
  required Layer layer,
  required String keyPrefix,
  Axis axis = Axis.horizontal,
  required void Function(LayerId layerId, double share) onChangeEnd,
}) => Builder(
  builder: (context) => FieldSlider.opacity(
    name: '$keyPrefix-layer-total-volume-${layer.id}',
    axis: axis,
    value: layer.seSound.totalVolume.clamp(0.0, SeSound.maxVolume).toDouble(),
    height: layerRailBarHeightIn(context),
    percents: (SeSound.maxVolume * 100).round(),
    onChanged: (_) {},
    onChangeEnd: (share) => onChangeEnd(layerIdNow(context, layer.id), share),
  ),
);
