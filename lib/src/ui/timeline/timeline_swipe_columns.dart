import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import 'layer_label_controls.dart';
import 'layer_rail_columns.dart';
import 'property_lane_model.dart';
import 'rail_column_swipe.dart';
import 'timeline_grid_hooks.dart';

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
/// so a slot's WIDTH is its height there.
List<RailToggleColumn<TimelineDisplayRow>> timelineSwipeColumns({
  required TimelineGridHooks hooks,
  required double crossExtent,
  required double leadingOrigin,
  required LayerRailColumnWidths columns,
}) => railSwipeColumns<TimelineDisplayRow>(
  crossExtent: crossExtent,
  leadingOrigin: leadingOrigin,
  columns: columns,
  hasOnionColumn: hooks.onToggleLayerOnionSkin != null,
  hasBlendColumn: hooks.onLayerBlendModeSelected != null,
  visibility: _visibility(hooks),
  onion: _onion(hooks),
  fx: _fx(hooks),
  timesheet: _timesheet(hooks),
  laneToggle: _laneToggle(hooks),
);

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

/// A lane row's switch is its group's bypass — live when the host reads it.
bool? _laneFxValue(
  TimelineGridHooks hooks,
  TimelineDisplayRow row,
  PropertyLaneRow lane,
) {
  if (hooks.onToggleLaneGroupEnabled == null) return null;
  return hooks.laneGroupOnOf?.call(row.layer.id) ?? lane.groupEnabled;
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

/// A row with no lanes draws no twirl — and its cell is what the nesting
/// indent pushes, so this is also the column most likely to be crossed at
/// two different depths in one drag.
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
