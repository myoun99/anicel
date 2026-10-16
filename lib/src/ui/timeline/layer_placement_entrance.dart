import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../media/media_asset_drop_target.dart';
import 'axis_turn.dart' show partAlong;
import 'layer_drop_policy.dart' show layerRowsOf, nearestLayerGap;
import 'property_lane_model.dart' show TimelineDisplayRow;
import 'timeline_row_edges.dart';

/// The layer area as a place entrance: a file from the pool let go between
/// two rows becomes a new layer at that gap (유저 2026-09-11, 미디어 배치
/// 라운드: 「레이어 영역(가로선) → 새 레이어」).
///
/// While it hovers, the rows' OWN caret shows the gap: the host hands the
/// gap to the row drag's channel, so the code that draws a moved row's line
/// draws this one too — there is no second line widget to drift from it.
///
/// It reports and stops there, like every entrance: which gap, among which
/// layers, carrying which file. Whether a row may go there is the
/// session's answer, and so is what the drop opens.
class LayerPlacementEntrance extends StatelessWidget {
  const LayerPlacementEntrance({
    super.key,
    required this.rowAxis,
    required this.rows,
    required this.onDrop,
    this.onHover,
    this.onLeave,
    this.accepts,
  });

  /// The axis the rows run along: down the rail, across the sheet.
  final Axis rowAxis;

  /// The rows as drawn and where they sit along [rowAxis], read when the
  /// drag moves rather than when this built: the gap is counted in what is
  /// on screen (F-31).
  final ({List<TimelineDisplayRow> rows, TimelineRowEdges edges}) Function()
  rows;

  final void Function(List<Layer> displayLayers, int slot, String path)
  onDrop;
  final void Function(List<Layer> displayLayers, int slot, String path)?
  onHover;
  final VoidCallback? onLeave;

  /// Whether that file can land at that gap — the chip's answer; null is
  /// yes.
  final bool Function(List<Layer> displayLayers, int slot, String path)?
  accepts;

  @override
  Widget build(BuildContext context) => MediaAssetDropTarget(
    framed: false,
    accepts: accepts == null
        ? null
        : (data, globalPosition) {
            final gap = _gapAt(context, globalPosition);
            return accepts!(gap.layers, gap.slot, data.path);
          },
    onHover: (data, globalPosition) {
      final gap = _gapAt(context, globalPosition);
      onHover?.call(gap.layers, gap.slot, data.path);
    },
    onLeave: onLeave,
    onDrop: (data, globalPosition) {
      final gap = _gapAt(context, globalPosition);
      onDrop(gap.layers, gap.slot, data.path);
    },
  );

  /// This widget's box IS the strip, row 0 at its start — the window's
  /// spacers stand for whole rows — so a local offset along [rowAxis] is
  /// the strip position [nearestLayerGap] counts in.
  ({List<Layer> layers, int slot}) _gapAt(
    BuildContext context,
    Offset globalPosition,
  ) {
    final drawn = rows();
    final box = context.findRenderObject();
    final local = box is RenderBox && box.hasSize
        ? box.globalToLocal(globalPosition)
        : Offset.zero;
    return (
      layers: [for (final row in layerRowsOf(drawn.rows)) row.layer],
      slot: nearestLayerGap(drawn.rows, partAlong(rowAxis, local), drawn.edges),
    );
  }
}
