import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import 'layer_rail_columns.dart' show layerRailEyeIsOn;

/// What every rail row's EYE shows, handed down past the row memo — so an
/// eye can change without the row it stands in being built again.
///
/// 🔬an-eye-rebuilds-its-whole-row (measured 2026-09-23, 24 inked rows): a
/// solo toggle flips most rows' eyes at once, and the row memo compared the
/// eye with everything else the row shows — so every row whose eye changed
/// rebuilt all twelve slots, 3,051 elements in one frame (`RowControlSurface`
/// 91 · tooltips 98 · `ControlPressClaim` 151). On the user's machine that
/// frame's UI thread was 55 ms on and 66 ms off (I-19, 「솔로 버벅임」).
///
/// ⛔Aspect-scoped ([InheritedModel]): a reader hears its OWN row's eye and
/// nothing else, which is the whole saving. A plain inherited widget would
/// rebuild every reader on every flip — the rows again, one level down.
class RailEyes extends InheritedModel<LayerId> {
  const RailEyes({super.key, required this.eyeOn, required super.child});

  /// The eyes of [layers], each as its own row answers it.
  RailEyes.forLayers(
    Iterable<Layer> layers, {
    super.key,
    required super.child,
  }) : eyeOn = {for (final layer in layers) layer.id: layerRailEyeIsOn(layer)};

  final Map<LayerId, bool> eyeOn;

  /// What [layer]'s eye shows where a rail hands the eyes down, and the
  /// row's own answer ([layerRailEyeIsOn]) where none does.
  static bool of(BuildContext context, Layer layer) =>
      InheritedModel.inheritFrom<RailEyes>(
        context,
        aspect: layer.id,
      )?.eyeOn[layer.id] ??
      layerRailEyeIsOn(layer);

  @override
  bool updateShouldNotify(RailEyes oldWidget) =>
      !mapEquals(eyeOn, oldWidget.eyeOn);

  @override
  bool updateShouldNotifyDependent(
    RailEyes oldWidget,
    Set<LayerId> dependencies,
  ) => dependencies.any((id) => eyeOn[id] != oldWidget.eyeOn[id]);
}

/// Builds from [layer]'s eye as [RailEyes] shows it — the part of a row that
/// a flip of the eye rebuilds, and the only part.
class RailEyeBuilder extends StatelessWidget {
  const RailEyeBuilder({super.key, required this.layer, required this.builder});

  final Layer layer;
  final Widget Function(BuildContext context, bool eyeOn) builder;

  @override
  Widget build(BuildContext context) =>
      builder(context, RailEyes.of(context, layer));
}
