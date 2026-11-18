import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';

/// [kind] sampled at its defaults but for [lanes] — a value by its
/// parameter's id —, standing on [points] and reading the rows [layers]
/// name.
ResolvedLayerEffect fx(
  EffectKind kind,
  Map<String, double> lanes, {
  Map<String, CanvasPoint?> points = const {},
  Map<String, LayerId?> layers = const {},
}) => ResolvedLayerEffect(
  kind: kind,
  values: [
    for (final spec in kind.parameters) lanes[spec.id] ?? spec.defaultValue,
  ],
  points: points,
  layers: layers,
);
