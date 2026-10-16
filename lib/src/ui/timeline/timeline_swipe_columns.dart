import 'package:flutter/painting.dart' show Axis;

import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import 'lane_graph.dart' show LaneGraphsView;
import 'lane_graph_seats.dart' show laneGraphHeadedBy, lanePinOf;
import 'layer_label_controls.dart';
import 'layer_rail_columns.dart';
import 'property_lane_model.dart';
import 'rail_column_swipe.dart';
import 'timeline_grid_hooks.dart';
import 'timeline_lane_rows.dart' show laneMemberPinInset;

/// The toggle columns a rail's bulk-drag can sweep, for BOTH grids.
///
/// 🚨I-1 (유저 2026-08-24): 「레이어의 버튼 조작하는거 **일괄조작** 넣고싶어 …
/// 탭 다운 한 채로 아래로 드래그하면 해당 다른 레이어들도 같은 버튼이
/// 눌리도록」 — and 2026-08-29: 「버튼이면 다 가능하도록」·「로직적으로
/// 다른규칙 두지말고 통일」. The rail and the x-sheet each kept a list of
/// their own — the same five columns, the sheet's written over `Layer` and
/// the rail's over the display row — and the two had drifted: the rail read
/// the twirl state a frame stale (its own doc said not to), the sheet could
/// not sweep a lane group's fx switch, the sheet had no sheet-toggle column
/// until the row widget was shared. ONE list over the display row now; the
/// geometry stays [railSwipeColumns]'s.
///
/// 🚨THE SUBJECT IS THE ROW, NOT ITS LAYER, because a rail stacks two kinds
/// and they do not share one. A layer row's fx switch is the LAYER's; a lane
/// row's is that LANE GROUP's. Every other column belongs to layer rows only
/// and answers null on a lane, which is already what
/// [RailToggleColumn.valueOf]'s null means. The sheet's columns are these
/// rows stood up, so a lane COLUMN answers exactly as a lane ROW does.
///
/// [crossExtent] is the strip's extent across the sweep — the rail's row
/// width, or the sheet's header height, which is that width turned on its
/// side: the slot skeleton lays the sheet's cells with `axis: Axis.vertical`,
/// so a slot's WIDTH is its height there. [axis] is the grid's: a member
/// lane's pin is laid by its cell, not by the skeleton, and the cell lays
/// its value a different length on each.
List<RailToggleColumn<TimelineDisplayRow>> timelineSwipeColumns({
  required TimelineGridHooks hooks,
  required Axis axis,
  required double crossExtent,
  required double leadingOrigin,
  required LayerRailColumnWidths columns,
}) => railSwipeColumns<TimelineDisplayRow>(
  crossExtent: crossExtent,
  leadingOrigin: leadingOrigin,
  columns: columns,
  optionalColumns: hooks.optionalRailColumns,
  graph: switch (_graph(hooks)) {
    final toggle? => (toggle: toggle, after: _pastTheGraph),
    null => null,
  },
  visibility: _visibility(hooks),
  onion: _onion(hooks),
  fx: _fx(hooks),
  timesheet: _timesheet(hooks),
  laneToggle: _laneToggle(hooks),
  lanePin: switch (_lanePin(hooks)) {
    final toggle? => (
      toggle: toggle,
      inset: laneMemberPinInset(axis, columns),
    ),
    null => null,
  },
);

/// I-89 ③: a header graph's button, on each row that heads one — a
/// Transform or effect header, the camera row ([laneGraphHeadedBy]) —
/// swept as it is pressed, and read LIVE where the host gives the read.
RailToggle<TimelineDisplayRow>? _graph(TimelineGridHooks hooks) {
  final verbs = hooks.laneGraphVerbs;
  if (verbs == null) return null;
  return (
    valueOf: (row) => switch (laneGraphHeadedBy(row.layer, row.lane)) {
      final key? => _laneGraphsOf(hooks).open.containsKey(key),
      null => null,
    },
    toggle: (row) {
      if (laneGraphHeadedBy(row.layer, row.lane) case final key?) {
        verbs.toggle(key);
      }
    },
  );
}

/// What a row lays past its graph button at the end of its name (I-89 Q1):
/// a layer row its fold slot, which always ends its name (F-29); a header
/// nothing.
double _pastTheGraph(TimelineDisplayRow row) =>
    row.isLane ? 0 : layerLaneToggleSlotWidth;

/// I-89 ③: a member lane's pin, on each lane that wears one ([lanePinOf]),
/// swept as it is pressed and read live, as the graph's button is.
RailToggle<TimelineDisplayRow>? _lanePin(TimelineGridHooks hooks) {
  final verbs = hooks.laneGraphVerbs;
  if (verbs == null) return null;
  return (
    valueOf: (row) => switch (lanePinOf(row.layer, row.lane)) {
      final key? => _laneGraphsOf(hooks).pinned.contains(key),
      null => null,
    },
    toggle: (row) {
      if (lanePinOf(row.layer, row.lane) case final key?) {
        verbs.togglePin(key);
      }
    },
  );
}

LaneGraphsView _laneGraphsOf(TimelineGridHooks hooks) =>
    hooks.laneGraphsNow?.call() ?? hooks.laneGraphs;

RailToggle<TimelineDisplayRow> _visibility(TimelineGridHooks hooks) => (
  valueOf: (row) =>
      row.isLane ? null : layerRailEyeIsOn(row.layer, live: hooks.layerEyeOnOf),
  toggle: (row) => hooks.onToggleLayerVisibility(row.layer.id),
);

/// Only brush-holding rows carry the button (the row builder's rule), and a
/// swipe paints what a tap could.
RailToggle<TimelineDisplayRow>? _onion(TimelineGridHooks hooks) {
  final onToggle = hooks.onToggleLayerOnionSkin;
  final enabledOf = hooks.layerOnionSkinEnabledOf;
  if (onToggle == null || enabledOf == null) return null;
  return (
    valueOf: (row) => !row.isLane && row.layer.kind.takesOnionSkin
        ? enabledOf(row.layer.id)
        : null,
    toggle: (row) => onToggle(row.layer.id),
  );
}

/// 🚨THE COLUMN WITH TWO VERBS. A layer row's fx is tri-state and the swipe
/// paints the one thing a tap paints — on, or not on. A LANE row's is its
/// group's own bypass switch, in the same column and painted by the same
/// sweep (유저: 「버튼이면 다 가능하도록」).
RailToggle<TimelineDisplayRow> _fx(TimelineGridHooks hooks) => (
  valueOf: (row) => _fxValue(hooks, row),
  toggle: (row) => _fxToggle(hooks, row),
);

bool? _fxValue(TimelineGridHooks hooks, TimelineDisplayRow row) {
  final lane = row.lane;
  return lane == null
      ? _layerFxValue(hooks, row)
      : _laneFxValue(hooks, row, lane);
}

/// A lane row's switch is its GROUP's bypass, worn by the group's header
/// alone ([PropertyLaneRow.groupEnabled], what the rail mounts its fx
/// button by) — read live when the host reads it.
///
/// 🚨A MEMBER WEARS NO SWITCH: it reads null, and the sweep holds it without
/// a press. ↩️Every lane row read the host's one live switch, the TRANSFORM
/// flag: an effect header spread the transform's state, and a member was
/// pressed — its lane id names its effect, so each member crossed flipped
/// that effect once more (I-89 ①ⓒ).
bool? _laneFxValue(
  TimelineGridHooks hooks,
  TimelineDisplayRow row,
  PropertyLaneRow lane,
) {
  final drawn = lane.groupEnabled;
  if (hooks.onToggleLaneGroupEnabled == null || drawn == null) return null;
  return hooks.laneGroupOnOf?.call(row.layer.id, lane.laneId) ?? drawn;
}

/// A layer row's fx is tri-state, read as the tap flips it: a MIXED row
/// is on. It was read "on, or not on" — so a sweep turning rows on met a
/// mixed row, called it off, and toggled it, which the tap resolves OFF;
/// and a press spread across a row selection reads it this way too.
bool? _layerFxValue(TimelineGridHooks hooks, TimelineDisplayRow row) {
  final fxStateOf = hooks.layerFxStateOf;
  if (hooks.onToggleLayerFx == null ||
      fxStateOf == null ||
      !layerKindShowsFxToggle(row.layer.kind)) {
    return null;
  }
  return fxEnabledFromState(fxStateOf(row.layer.id));
}

void _fxToggle(TimelineGridHooks hooks, TimelineDisplayRow row) {
  final lane = row.lane;
  if (lane != null) {
    hooks.onToggleLaneGroupEnabled?.call(row.layer, lane);
    return;
  }
  hooks.onToggleLayerFx?.call(row.layer.id);
}

/// 🚨I-1 (유저 2026-08-24): 「**타임시트버튼이든 뭐 그런것들**」 — the report
/// named this column, and it is the one the geometry was first written for.
///
/// An ATTACH row is null rather than false: its sheet slot holds the
/// placement arrow (R10 R3), so there is no toggle under the swipe.
RailToggle<TimelineDisplayRow> _timesheet(TimelineGridHooks hooks) => (
  valueOf: (row) => !row.isLane && layerCarriesTimesheetToggle(row.layer)
      ? row.layer.onTimesheet
      : null,
  toggle: (row) => hooks.onToggleLayerTimesheet(row.layer.id),
);

/// A row with no lanes draws no twirl.
///
/// 🚨The twirl's state is the LIVE read when the host gives one
/// ([TimelineGridHooks.laneOpenOf]): the set is a widget property, a frame
/// too late for a bulk-drag that started on the twirl itself (the button
/// fires on the down — 유저 2026-08-30 — and the sweep spreads what it set).
/// The rail read the stale set while the sheet read the live one; one list
/// reads one thing.
RailToggle<TimelineDisplayRow>? _laneToggle(TimelineGridHooks hooks) {
  final onToggle = hooks.onToggleLayerLanes;
  if (onToggle == null) return null;
  return (
    valueOf: (row) => _laneOpen(hooks, row),
    toggle: (row) => onToggle(row.layer.id),
  );
}

bool? _laneOpen(TimelineGridHooks hooks, TimelineDisplayRow row) {
  if (row.isLane) return null;
  final lanes =
      hooks.lanesForLayer?.call(row.layer) ?? const <PropertyLaneRow>[];
  if (lanes.isEmpty) return null;
  return hooks.laneOpenOf?.call(row.layer.id) ??
      hooks.expandedLaneLayerIds.contains(row.layer.id);
}
