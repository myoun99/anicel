import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart' show LayerFolderIndex;
import '../../models/layer_id.dart';
import 'layer_rail_columns.dart' show layerRailEyeIsOn;

/// What a rail row's eye shows: its own switch ([on]), and whether a folder
/// above it has hidden the row anyway ([hiddenAbove]).
///
/// 🚨F-185 (유저 2026-09-26): 「폴더에 대한 비지블버튼 조작시, 지금 로직은
/// 맘에드는데, 비지블off일때 내부 레이어의 비지블이 on에다가 활성화색인데 그림
/// 사라지는게 직관적이지 않으니, on인채로 두되, 색만 비활성화색으로. 반대도
/// 마찬가지. 폴더니까 어태치폴더든 뭐든 법 통일해서 적용」 + 「색라벨도 동일하게
/// 비활성화색 하는거 잊지말고」. The switch keeps its own value; what dims is
/// the colour, and the question is the composite's own folder gate — the
/// row's folder chain, attach folders included ([LayerFolderIndex
/// .subtreeVisible]). A base's eye hides no rider (UI-R24 #5), so a rider
/// of a hidden base is not dimmed.
typedef RailEye = ({bool on, bool hiddenAbove});

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
/// A folder's flip reaches its members this way too: their
/// `RailEye.hiddenAbove` changes, and only their eyes and labels are built
/// again.
class RailEyes extends InheritedModel<LayerId> {
  const RailEyes({super.key, required this.eyes, required super.child});

  /// The eyes of [layers], each as its own row answers it and as the folders
  /// of [stack] — the cut's whole stack — gate it.
  RailEyes.forLayers(
    Iterable<Layer> layers, {
    required List<Layer> stack,
    super.key,
    required super.child,
  }) : eyes = railEyesOf(layers, stack: stack);

  final Map<LayerId, RailEye> eyes;

  /// What [layer]'s eye shows where a rail hands the eyes down, and the
  /// row's own answer ([layerRailEyeIsOn]) where none does.
  static RailEye of(BuildContext context, Layer layer) =>
      InheritedModel.inheritFrom<RailEyes>(
        context,
        aspect: layer.id,
      )?.eyes[layer.id] ??
      (on: layerRailEyeIsOn(layer), hiddenAbove: false);

  @override
  bool updateShouldNotify(RailEyes oldWidget) =>
      !mapEquals(eyes, oldWidget.eyes);

  @override
  bool updateShouldNotifyDependent(
    RailEyes oldWidget,
    Set<LayerId> dependencies,
  ) => dependencies.any((id) => eyes[id] != oldWidget.eyes[id]);
}

/// The eye of each of [layers] over [stack] — see [RailEye].
Map<LayerId, RailEye> railEyesOf(
  Iterable<Layer> layers, {
  required List<Layer> stack,
}) {
  final folders = LayerFolderIndex(stack);
  return {
    for (final layer in layers)
      layer.id: (
        on: layerRailEyeIsOn(layer),
        hiddenAbove: !folders.subtreeVisible(layer.folderId),
      ),
  };
}

/// Builds from [layer]'s eye as [RailEyes] shows it — the part of a row that
/// a flip of the eye rebuilds, and the only part.
class RailEyeBuilder extends StatelessWidget {
  const RailEyeBuilder({super.key, required this.layer, required this.builder});

  final Layer layer;
  final Widget Function(BuildContext context, RailEye eye) builder;

  @override
  Widget build(BuildContext context) =>
      builder(context, RailEyes.of(context, layer));
}
