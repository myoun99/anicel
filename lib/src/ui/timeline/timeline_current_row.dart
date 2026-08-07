import 'package:flutter/foundation.dart' show ValueListenable;

import '../../models/layer_id.dart';
import '../../models/timeline_row_address.dart';

/// The rail's half of R10 #19: WHICH row the frame-axis verbs act on, and
/// how to move it by pressing a label.
///
/// Standing on a row has worked since R10 R2 — the address type, the verb
/// routing and the ↑/↓ nav all landed there — but only through the FRAME
/// side: you could press a lane's band and nothing else. The two halves
/// this bundle adds are what makes it a thing you can see and aim:
///
/// * [currentRow] is drawn. A [ValueListenable] rather than session state
///   read at build time, because the claim that moves the row fires on
///   pointer-DOWN inside gestures whose contract is silence until release
///   — so the rows subscribe and the small cells repaint themselves.
/// * [onStandOnLane] makes the LABEL a place you can stand, the way the
///   layer row's label already selects its layer. It carries no frame:
///   standing is not seeking, and the two surfaces that host these rows
///   count frames differently (the timeline locally, the storyboard
///   globally) — a frame in this signature is a trap, not a feature.
class TimelineCurrentRowHooks {
  const TimelineCurrentRowHooks({required this.currentRow, this.onStandOnLane});

  final ValueListenable<TimelineRowAddress?> currentRow;

  /// Null leaves labels inert (passive hosts, and the test harnesses that
  /// mount a grid without a session).
  final void Function(LayerId layerId, String laneId)? onStandOnLane;
}

/// Whether [row] IS the (layer, lane) property row — the one test every
/// rail surface asks, stated once so a surface cannot invent its own.
bool currentRowIsLane(TimelineRowAddress? row, LayerId layerId, String laneId) {
  return row is LaneRowAddress &&
      row.layerId == layerId &&
      row.laneId == laneId;
}
