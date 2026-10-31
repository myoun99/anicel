import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../../models/layer_id.dart';
import 'berth_row.dart';

/// THE LAYER STOOD ON, FOR THE ROWS OF A GRID — heard once, above them.
///
/// 🔬I-22-rest (11-01, S5_BA 컷352, 디버그): a stand changes one colour on
/// two rows, and no grid is built again for it. So a row asks here whether
/// it is the one stood on ([standsOnRow]), by the layer it stands for now,
/// and only the plates of the two rows the stand moved between hear it.
///
/// ⛔One listener, above the rows: one on each row would be a State in
/// every row, which the row body may not have (`RowPlate`'s chain,
/// a_row_body_is_light_boxes_test).
class RailStand extends StatelessWidget {
  const RailStand({super.key, required this.activeLayer, required this.child});

  final ValueListenable<LayerId?> activeLayer;
  final Widget child;

  /// Whether the row at [context] is the one stood on — [context] rebuilt
  /// when it stops or starts being; null where no kept row stands above or
  /// no grid does (a row told by what builds it).
  static bool? standsOnRow(BuildContext context) {
    final layerId = BerthRow.of(context)?.id;
    if (layerId == null) {
      return null;
    }
    final stand = InheritedModel.inheritFrom<_StoodLayer>(
      context,
      aspect: layerId,
    );
    return stand == null ? null : stand.layerId == layerId;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LayerId?>(
    valueListenable: activeLayer,
    builder: (context, layerId, child) =>
        _StoodLayer(layerId: layerId, child: child!),
    child: child,
  );
}

/// The stand as its dependents ask it: each by the layer its row stands for,
/// so a stand wakes the row it left and the row it reached.
class _StoodLayer extends InheritedModel<LayerId> {
  const _StoodLayer({required this.layerId, required super.child});

  final LayerId? layerId;

  @override
  bool updateShouldNotify(_StoodLayer oldWidget) =>
      oldWidget.layerId != layerId;

  @override
  bool updateShouldNotifyDependent(
    _StoodLayer oldWidget,
    Set<LayerId> dependencies,
  ) =>
      dependencies.contains(oldWidget.layerId) ||
      dependencies.contains(layerId);
}
