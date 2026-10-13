import 'package:flutter/widgets.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';

/// THE LAYER A KEPT ROW STANDS FOR NOW — handed down past the row's memo.
///
/// 🚨I-57 ㉣ (10-13): a cut switch builds the new cut's rows in the old
/// rows' elements ([RowBerths]), and a row whose FACE is the face the old
/// row showed — its name, kind, label, opacity, switches — is the same row
/// on screen, so its memo hands it back whole ([KeptLayerControlsRows]).
/// Only WHICH layer it stands for changed, and that is asked here, at the
/// moment it matters: a press acts on the layer the row stands for now
/// ([layerIdNow]), and an eye shows that layer's switch ([of]).
///
/// ⛔A kept row's own [Layer] is the one it was BUILT for: equal to this
/// one in its face, another layer by its id. Nothing in a kept row asks
/// that id for what it acts on. Its NAMES are spelled with it — a finder
/// reads them as the row stands.
class BerthRow extends InheritedWidget {
  const BerthRow({super.key, required this.layer, required super.child});

  final Layer layer;

  /// The layer the row at [context] stands for now — [context] rebuilt
  /// when the row stands for ANOTHER layer; null where no kept row stands
  /// above. What the row shows of the layer is its face, which the memo
  /// answers for: a reader takes the layer's identity from here.
  static Layer? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BerthRow>()?.layer;

  /// [of] at an event — a press, a drag's start — without depending on it.
  static Layer? at(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BerthRow>()?.layer;

  @override
  bool updateShouldNotify(BerthRow oldWidget) =>
      oldWidget.layer.id != layer.id;
}

/// The id of the layer the row at [context] stands for now — [builtFor],
/// where no kept row stands above, the row then being built for the layer
/// it shows. What every verb of a row hands its host.
LayerId layerIdNow(BuildContext context, LayerId builtFor) =>
    BerthRow.at(context)?.id ?? builtFor;
