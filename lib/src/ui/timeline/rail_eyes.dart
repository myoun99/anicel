import 'package:flutter/foundation.dart' show mapEquals, setEquals;
import 'package:flutter/widgets.dart';
import '../../models/attached_layer_resolve.dart' show AttachGroups;
import '../../models/attached_placement.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart' show LayerFolderIndex;
import '../../models/layer_id.dart';
import 'berth_row.dart';
import 'layer_rail_columns.dart' show layerRailEyeIsOn;
import 'memo_token.dart' show Kept, keptWhileSame;

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

/// Whether the row is SHOWN — its own eye on, and no folder above hiding it.
/// The ONE answer everything on the row that dims with the eye wears: the
/// colour label (F-56, F-185) and the name (I-62).
extension RailEyeShown on RailEye {
  bool get shown => on && !hiddenAbove;
}

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
  const RailEyes({
    super.key,
    required this.eyes,
    this.sidesShown = const {},
    required super.child,
  });

  /// The eyes of [layers], each as its own row answers it and as the folders
  /// of [stack] — the cut's whole stack — gate it; and the sides of each
  /// base among them that show anything ([railSidesShownOf]).
  RailEyes.forLayers(
    Iterable<Layer> layers, {
    required List<Layer> stack,
    required AttachGroups groups,
    super.key,
    required super.child,
  }) : eyes = railEyesOf(layers, stack: stack),
       sidesShown = railSidesShownOf(layers, stack: stack, groups: groups);

  final Map<LayerId, RailEye> eyes;

  /// The sides of each base whose attach rows show anything — what the
  /// halves of its fold twirl say in colour (I-175). A base this rail
  /// answered for has its entry, an empty set where nothing shows.
  final Map<LayerId, Set<AttachedPlacement>> sidesShown;

  /// What [layer]'s eye shows where a rail hands the eyes down, and the
  /// row's own answer ([layerRailEyeIsOn]) where none does.
  static RailEye of(BuildContext context, Layer layer) =>
      InheritedModel.inheritFrom<RailEyes>(
        context,
        aspect: layer.id,
      )?.eyes[layer.id] ??
      (on: layerRailEyeIsOn(layer), hiddenAbove: false);

  /// Whether [base]'s attach rows on [side] show anything where a rail
  /// hands the eyes down ([sidesShown]) — hearing [base]'s own aspect. True
  /// where the rail answered nothing for [base]: nothing says the side is
  /// dark.
  static bool sideShown(
    BuildContext context,
    Layer base,
    AttachedPlacement side,
  ) =>
      InheritedModel.inheritFrom<RailEyes>(
        context,
        aspect: base.id,
      )?.sidesShown[base.id]?.contains(side) ??
      true;

  @override
  bool updateShouldNotify(RailEyes oldWidget) =>
      !mapEquals(eyes, oldWidget.eyes) ||
      oldWidget.sidesShown.length != sidesShown.length ||
      sidesShown.keys.any((id) => _sidesChanged(oldWidget, id));

  @override
  bool updateShouldNotifyDependent(
    RailEyes oldWidget,
    Set<LayerId> dependencies,
  ) => dependencies.any(
    (id) => eyes[id] != oldWidget.eyes[id] || _sidesChanged(oldWidget, id),
  );

  bool _sidesChanged(RailEyes oldWidget, LayerId id) =>
      !setEquals(sidesShown[id], oldWidget.sidesShown[id]);
}

/// The eye of each of [layers] over [stack] — see [RailEye].
Map<LayerId, RailEye> railEyesOf(
  Iterable<Layer> layers, {
  required List<Layer> stack,
}) {
  final folders = LayerFolderIndex(stack);
  return {for (final layer in layers) layer.id: _eyeOf(layer, folders)};
}

/// The sides of each base among [layers] whose attach rows — [groups], the
/// stack's, worked out in the model order — show anything over [stack]: a
/// row of the side SHOWN ([RailEyeShown]), the answer the eye and the label
/// dim by.
///
/// 🗣️I-175 (유저 2026-11-15): 「내부의 위쪽 어태치레이어가 비지블on인상태면
/// 위쪽 어태치 접기/펼치기버튼이 활성화색. 위쪽 내부 레이어든 뭐든 다
/// 비지블off라서 진짜 아무것도 안보이는 상황일때 … 비활성화색」. The base's
/// own eye is not asked: it hides no rider (UI-R24 #5), which is what made
/// a group read as dark while a row of it still showed.
Map<LayerId, Set<AttachedPlacement>> railSidesShownOf(
  Iterable<Layer> layers, {
  required List<Layer> stack,
  required AttachGroups groups,
}) {
  final folders = LayerFolderIndex(stack);
  return {
    for (final layer in layers)
      if (groups[layer.id] case final sides?)
        layer.id: {
          for (final MapEntry(key: side, value: rows) in sides.entries)
            if (rows.any((row) => _eyeOf(row, folders).shown)) side,
        },
  };
}

RailEye _eyeOf(Layer layer, LayerFolderIndex folders) => (
  on: layerRailEyeIsOn(layer),
  hiddenAbove: !folders.subtreeVisible(layer.folderId),
);

/// Builds from what [RailEyes] shows of [layer] — the part of a row that a
/// flip of an eye rebuilds, and the only part: the row's own eye
/// ([RailEyeBuilder]), or whether a row on one side of its attach group
/// shows ([RailSideBuilder]).
///
/// ↩️One keep read two ways since I-175: a fold twirl's colour asks its
/// folder's eye or the rows on its half's side, and a twirl that read them
/// past the keep was built again on every cut crossed (the kept row's pin,
/// `a_kept_row_acts_on_the_layer_it_stands_for_test`).
abstract class RailEyesReader<T extends Object> extends StatefulWidget {
  const RailEyesReader({super.key, required this.layer});

  final Layer layer;

  /// What this reads of [standsFor] off [RailEyes].
  T readOf(BuildContext context, Layer standsFor);

  /// What it shows of [reading].
  Widget buildOf(BuildContext context, T reading);

  @override
  State<RailEyesReader<T>> createState() => _RailEyesReaderState<T>();
}

class _RailEyesReaderState<T extends Object>
    extends State<RailEyesReader<T>> {
  /// What was built, and from which reading ([keptWhileSame]).
  final Map<Type, Kept<T>> _held = {};

  @override
  void didUpdateWidget(RailEyesReader<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _held.clear();
  }

  /// What [RailEyes] shows of the layer the row stands for NOW ([BerthRow])
  /// — a kept row's [RailEyesReader.layer] is the one it was built for.
  ///
  /// 🚨I-57 ㉣ (10-13, measured on the user's project): a cut switch hands a
  /// kept row another layer, and every eye in it must ask that layer's eye
  /// — but it is mostly the same eye, and building it again built what it
  /// shows again: 108 of a crossing's rebuilds, six rows. What it shows is
  /// handed back while the eye is the same. It is built in a [Builder] of
  /// its own, so what else it reads (the theme) rebuilds it there, never
  /// through this; the words are every keep's fact. ↩️They were said to
  /// rebuild it there too, which a static read never does.
  @override
  Widget build(BuildContext context) {
    final reading = widget.readOf(
      context,
      BerthRow.of(context) ?? widget.layer,
    );
    return keptWhileSame(
      _held,
      RailEyesReader,
      reading,
      () => Builder(builder: (context) => widget.buildOf(context, reading)),
    );
  }
}

/// Builds from [layer]'s eye as [RailEyes] shows it ([RailEyesReader]).
class RailEyeBuilder extends RailEyesReader<RailEye> {
  const RailEyeBuilder({
    super.key,
    required super.layer,
    required this.builder,
  });

  final Widget Function(BuildContext context, RailEye eye) builder;

  @override
  RailEye readOf(BuildContext context, Layer standsFor) =>
      RailEyes.of(context, standsFor);

  @override
  Widget buildOf(BuildContext context, RailEye reading) =>
      builder(context, reading);
}

/// Builds from whether a row on [side] of the attach group riding [layer]
/// shows ([RailEyes.sideShown]) — a half of the base's fold (I-175).
class RailSideBuilder extends RailEyesReader<bool> {
  const RailSideBuilder({
    super.key,
    required super.layer,
    required this.side,
    required this.builder,
  });

  final AttachedPlacement side;
  final Widget Function(BuildContext context, bool shown) builder;

  @override
  bool readOf(BuildContext context, Layer standsFor) =>
      RailEyes.sideShown(context, standsFor, side);

  @override
  Widget buildOf(BuildContext context, bool reading) =>
      builder(context, reading);
}
