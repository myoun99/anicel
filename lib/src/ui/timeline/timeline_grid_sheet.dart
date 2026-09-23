import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/layer_id.dart';
import '../../models/timeline_row_address.dart';
import 'property_lane_model.dart';
import 'timeline_beat_lines.dart';
import 'timeline_current_row.dart';

/// What a display row's ground is decided from — the same for every row of
/// one sheet, so the sheet reads it once and hands it to each: the host's
/// own colour, the active layer, the row the verbs stand on, and the scheme
/// the standing wash comes from.
typedef TimelineGridStand = ({
  Color hostGround,
  LayerId? activeLayerId,
  TimelineRowAddress? standing,
  ColorScheme colorScheme,
});

/// THE ground of one display row — what the grid sheet paints under it.
///
/// ⛔ONE answer for every row kind, and the sheet is its only reader (I-44).
/// It used to be three, each painted by the row itself: the cells row's
/// `surface` underlay plus its active wash (UI-R21 #2), the fx band's
/// composited wash ([timelineLaneGround], F-7 + F-25) and the SE audio
/// lane's raw 60% wash — which never lit at all while its rail half did,
/// F-25's own law broken on the one lane nobody had handed the standing row.
Color timelineRowGround(TimelineDisplayRow row, TimelineGridStand stand) {
  final (:hostGround, :activeLayerId, :standing, :colorScheme) = stand;
  final lane = row.lane;
  if (lane == null) {
    return row.layer.id == activeLayerId
        ? timelineStandingGround(hostGround, colorScheme)
        : hostGround;
  }
  final resting = timelineLaneGround(hostGround);
  // 🚨F-25 (유저 2026-08-24): 「레이어 영역은 fx멤버에 서있을경우 레이어/헤더/
  // 멤버 3군데가 바탕이 강조색되는데 프레임영역은 그러지 않으니 통일」 — the
  // rail's own test ([currentRowIsLane] / [currentRowIsInsideGroup]), so the
  // chain lights on both sides of the splitter.
  final lit =
      currentRowIsLane(standing, row.layer.id, lane.laneId) ||
      (lane.isGroupHeader &&
          currentRowIsInsideGroup(standing, row.layer.id, lane.laneId));
  return lit ? timelineStandingGround(resting, colorScheme) : resting;
}

/// The grid sheet of the two grids whose rows are DISPLAY rows — the
/// timeline and the X-sheet — every row at the one pitch, each on its
/// [timelineRowGround].
///
/// [rows] is the list the rows body draws from (the silhouette row
/// included), so the sheet's row k and the body's row k are the same row.
class TimelineRowsGridSheet extends StatelessWidget {
  const TimelineRowsGridSheet({
    super.key,
    required this.rows,
    required this.rowExtent,
    required this.frameCellExtent,
    required this.activeLayerId,
    this.standing,
    this.axis = Axis.horizontal,
  });

  final List<TimelineDisplayRow> rows;

  /// The rows' one pitch across the cross axis — the timeline's row height,
  /// the X-sheet's column width.
  final double rowExtent;
  final double frameCellExtent;
  final LayerId? activeLayerId;

  /// The row the verbs act on; the fx lanes light with it. Null leaves
  /// every lane unlit (harnesses that mount a grid with no session).
  final ValueListenable<TimelineRowAddress?>? standing;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final standing = this.standing;
    if (standing == null) {
      return _sheet(context, null);
    }
    return ValueListenableBuilder<TimelineRowAddress?>(
      valueListenable: standing,
      builder: (context, row, _) => _sheet(context, row),
    );
  }

  Widget _sheet(BuildContext context, TimelineRowAddress? standing) {
    final hostGround = TimelineGridLaw.maybeOf(context)?.ground;
    return TimelineGridSheet(
      frameCellExtent: frameCellExtent,
      axis: axis,
      // No ground = rows lying on the artwork: nothing to paint under them
      // and, by the same law, no seam between them.
      rows: hostGround == null
          ? TimelineGridRows.none
          : _rowsOn((
              hostGround: hostGround,
              activeLayerId: activeLayerId,
              standing: standing,
              colorScheme: Theme.of(context).colorScheme,
            )),
    );
  }

  TimelineGridRows _rowsOn(TimelineGridStand stand) => TimelineGridRows([
    for (final row in rows)
      (extent: rowExtent, ground: timelineRowGround(row, stand)),
  ]);
}
