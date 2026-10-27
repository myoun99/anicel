import 'package:flutter/foundation.dart' show ValueChanged;

import '../../models/attached_layer_resolve.dart'
    show attachRowWearsBaseComposite;
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import 'lane_graph.dart' show LaneGraphVerbs, LaneGraphsView;
import 'lane_graph_seats.dart' show laneGraphHeadedBy, lanePinOf;
import 'layer_label_controls.dart';
import 'layer_rail_columns.dart';
import 'property_lane_model.dart';
import 'rail_column_swipe.dart';
import 'timeline_grid_hooks.dart';
import 'timeline_lane_rows.dart' show laneRowFrame;
import 'timeline_layer_controls_row.dart'
    show TimelineGroupFold, timelineGroupFoldFor;

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
/// until the row widget was shared. ONE list over the display row now.
///
/// 🚨THE SUBJECT IS THE ROW, NOT ITS LAYER, because a rail stacks two kinds
/// and they do not share one. A layer row's fx switch is the LAYER's; a lane
/// row's is that LANE GROUP's. Every other column belongs to layer rows only
/// and answers null on a lane, which is already what
/// [RailToggleColumn.valueOf]'s null means. The sheet's columns are these
/// rows stood up, so a lane COLUMN answers exactly as a lane ROW does —
/// and which column a press is in, its button says on either grid.
List<RailToggleColumn<TimelineDisplayRow>> timelineSwipeColumns({
  required RailSwipeHooks hooks,
}) => railSwipeColumns<TimelineDisplayRow>(
  visibility: _visibility(hooks),
  onion: _onion(hooks),
  fx: _fx(hooks),
  clip: _clip(hooks),
  timesheet: _timesheet(hooks),
  laneToggle: _laneToggle(hooks),
  graph: _graph(hooks),
  lanePin: _lanePin(hooks),
  groupFold: _groupFold(hooks),
  laneGroupToggle: _laneGroupToggle(hooks),
  laneKey: _laneKey(hooks),
  laneFlag: _laneFlag(hooks),
);

/// What a lane row is handed to key and set its lane with: the verbs its
/// label calls and the frame it stands on ([laneRowFrame]).
typedef LaneRowHand = ({PropertyLaneEditCallbacks edit, int frame});

/// What a rail's column sweep reads of its host: the verbs its rows'
/// buttons call, and the reads it paints by — live where the host can read
/// the value a press just set, which a row built last frame still reports
/// stale.
///
/// I-89 ①ⓒ: the sweep's share of a host, narrowed from a grid's whole
/// hooks ([timelineRailSwipeHooks]) so a rail that is no grid hands the
/// same list the same reads (유저 2026-10-13: 「다시 말하지만 이런건 다
/// 콘티패널에도 동일하게 있어야해. 같은 법으로」) — as the header graph was
/// narrowed to what it reads (`LaneGraphGrid`).
typedef RailSwipeHooks = ({
  ValueChanged<LayerId>? onToggleLayerVisibility,
  bool Function(LayerId layerId)? layerEyeOnOf,
  ValueChanged<LayerId>? onToggleLayerOnionSkin,
  bool Function(LayerId layerId)? layerOnionSkinEnabledOf,
  ValueChanged<LayerId>? onToggleLayerFx,
  LayerFxState Function(LayerId layerId)? layerFxStateOf,
  // Whether a row wears its base's composite, as its row is told
  // ([layerRowWearsFxSwitch]).
  bool Function(Layer layer) wearsBaseComposite,
  void Function(Layer layer, PropertyLaneRow lane)? onToggleLaneGroupEnabled,
  bool? Function(LayerId layerId, String headerLaneId)? laneGroupOnOf,
  ValueChanged<LayerId>? onToggleLayerClip,
  bool Function(LayerId layerId)? layerClipsOf,
  ValueChanged<LayerId>? onToggleLayerTimesheet,
  bool Function(LayerId layerId)? layerOnTimesheetOf,
  ValueChanged<LayerId>? onToggleLayerLanes,
  List<PropertyLaneRow> Function(Layer layer)? lanesForLayer,
  bool Function(LayerId layerId) laneOpenOf,
  LaneGraphVerbs? laneGraphVerbs,
  LaneGraphsView Function() laneGraphsNow,
  RailRowHands hands,
  // A row's group fold as its label is told (`timelineGroupFoldFor`):
  // whether it folds rows of its own, open or shut, and what its twirl
  // presses.
  TimelineGroupFold Function(TimelineDisplayRow row) foldOf,
  bool Function(LayerId layerId)? groupFoldOpenOf,
  void Function(Layer layer, PropertyLaneRow lane)? onToggleLaneGroup,
  bool Function(LayerId layerId, String headerLaneId)? laneGroupOpenOf,
  // What a lane row's ◆ and its flag's ring are pressed with, as its label
  // is handed them — null on a row handed none (F-475).
  LaneRowHand? Function(TimelineDisplayRow row) laneHandOf,
});

/// Which of a rail's verbs a ROW is handed, as its label is — what the row
/// mounts a button by beside what its kind says (I-89 ①ⓒ). A grid hands
/// every row every verb ([handsEveryRow]), its row widget mounting by kind;
/// the conte rail hands its rows by family — its V row no eye and no sheet
/// toggle, and the TRACK's fx switch (I-73), its projection heads no sheet
/// toggle (I-89-Q22), a projection row's lane its group's switch only while
/// a cut is stood in.
typedef RailRowHands = ({
  bool Function(TimelineDisplayRow row) eye,
  bool Function(TimelineDisplayRow row) fx,
  bool Function(TimelineDisplayRow row) timesheet,
  bool Function(TimelineDisplayRow row) groupSwitch,
});

/// A grid's rows, each handed every verb.
const RailRowHands handsEveryRow = (
  eye: _handed,
  fx: _handed,
  timesheet: _handed,
  groupSwitch: _handed,
);

bool _handed(TimelineDisplayRow row) => true;

/// What a grid's [hooks] hand its sweep over its [layers] — the stack an
/// attach row's base is found in, as the grid's rows are told
/// (`layerControlsRowFacts`).
///
/// 🚨The twirl's state is the LIVE read when the grid has one
/// ([TimelineGridHooks.laneOpenOf]): the set is a widget property, a frame
/// too late for a bulk-drag that started on the twirl itself (the button
/// fires on the down — 유저 2026-08-30 — and the sweep spreads what it set).
/// The rail read the stale set while the sheet read the live one; one list
/// reads one thing. The header graphs likewise
/// ([TimelineGridHooks.laneGraphsNow]).
RailSwipeHooks timelineRailSwipeHooks(
  TimelineGridHooks hooks,
  List<Layer> layers,
) => (
  onToggleLayerVisibility: hooks.onToggleLayerVisibility,
  layerEyeOnOf: hooks.layerEyeOnOf,
  onToggleLayerOnionSkin: hooks.onToggleLayerOnionSkin,
  layerOnionSkinEnabledOf: hooks.layerOnionSkinEnabledOf,
  onToggleLayerFx: hooks.onToggleLayerFx,
  layerFxStateOf: hooks.layerFxStateOf,
  wearsBaseComposite: (layer) => attachRowWearsBaseComposite(layer, layers),
  onToggleLaneGroupEnabled: hooks.onToggleLaneGroupEnabled,
  laneGroupOnOf: hooks.laneGroupOnOf,
  onToggleLayerClip: hooks.onToggleLayerClip,
  layerClipsOf: hooks.layerClipsOf,
  onToggleLayerTimesheet: hooks.onToggleLayerTimesheet,
  layerOnTimesheetOf: hooks.layerOnTimesheetOf,
  onToggleLayerLanes: hooks.onToggleLayerLanes,
  lanesForLayer: hooks.lanesForLayer,
  laneOpenOf: (layerId) =>
      hooks.laneOpenOf?.call(layerId) ??
      hooks.expandedLaneLayerIds.contains(layerId),
  laneGraphVerbs: hooks.laneGraphVerbs,
  laneGraphsNow: () => hooks.laneGraphsNow?.call() ?? hooks.laneGraphs,
  hands: handsEveryRow,
  foldOf: (row) => timelineGroupFoldFor(
    row: row,
    layers: layers,
    collapsedAttachBaseIds: hooks.collapsedAttachBaseIds,
    onToggleLayerCollapsed: hooks.onToggleLayerCollapsed,
    onToggleAttachGroup: hooks.onToggleAttachGroup,
  ),
  groupFoldOpenOf: hooks.groupFoldOpenOf,
  onToggleLaneGroup: hooks.onToggleLaneGroup,
  laneGroupOpenOf: hooks.laneGroupOpenOf,
  // A grid hands every lane row its one set of verbs, at its cursor.
  laneHandOf: (_) => switch (hooks.laneEdit) {
    final edit? => (edit: edit, frame: laneRowFrame(hooks.frameCursor)),
    null => null,
  },
);

/// I-89 ③: a header graph's button, on each row that heads one — a
/// Transform or effect header, the camera row ([laneGraphHeadedBy]) —
/// swept as it is pressed, and read LIVE where the host gives the read.
RailToggle<TimelineDisplayRow>? _graph(RailSwipeHooks hooks) {
  final verbs = hooks.laneGraphVerbs;
  if (verbs == null) return null;
  return (
    valueOf: (row) => switch (laneGraphHeadedBy(row.layer, row.lane)) {
      final key? => hooks.laneGraphsNow().open.containsKey(key),
      null => null,
    },
    toggle: (row) {
      if (laneGraphHeadedBy(row.layer, row.lane) case final key?) {
        verbs.toggle(key);
      }
    },
  );
}

/// I-89 ③: a member lane's pin, on each lane that wears one ([lanePinOf]),
/// swept as it is pressed and read live, as the graph's button is.
RailToggle<TimelineDisplayRow>? _lanePin(RailSwipeHooks hooks) {
  final verbs = hooks.laneGraphVerbs;
  if (verbs == null) return null;
  return (
    valueOf: (row) => switch (lanePinOf(row.layer, row.lane)) {
      final key? => hooks.laneGraphsNow().pinned.contains(key),
      null => null,
    },
    toggle: (row) {
      if (lanePinOf(row.layer, row.lane) case final key?) {
        verbs.togglePin(key);
      }
    },
  );
}

RailToggle<TimelineDisplayRow>? _visibility(RailSwipeHooks hooks) {
  final onToggle = hooks.onToggleLayerVisibility;
  if (onToggle == null) return null;
  return (
    valueOf: (row) => row.isLane || !hooks.hands.eye(row)
        ? null
        : layerRailEyeIsOn(row.layer, live: hooks.layerEyeOnOf),
    toggle: (row) => onToggle(row.layer.id),
  );
}

/// Only brush-holding rows carry the button (the row builder's rule), and a
/// swipe paints what a tap could.
RailToggle<TimelineDisplayRow>? _onion(RailSwipeHooks hooks) {
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
RailToggle<TimelineDisplayRow> _fx(RailSwipeHooks hooks) => (
  valueOf: (row) => _fxValue(hooks, row),
  toggle: (row) => _fxToggle(hooks, row),
);

bool? _fxValue(RailSwipeHooks hooks, TimelineDisplayRow row) {
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
  RailSwipeHooks hooks,
  TimelineDisplayRow row,
  PropertyLaneRow lane,
) {
  final drawn = lane.groupEnabled;
  if (hooks.onToggleLaneGroupEnabled == null ||
      drawn == null ||
      !hooks.hands.groupSwitch(row)) {
    return null;
  }
  return hooks.laneGroupOnOf?.call(row.layer.id, lane.laneId) ?? drawn;
}

/// A layer row's fx is tri-state, read as the tap flips it: a MIXED row
/// is on. It was read "on, or not on" — so a sweep turning rows on met a
/// mixed row, called it off, and toggled it, which the tap resolves OFF;
/// and a press spread across a row selection reads it this way too.
///
/// A row wearing its base's switch reads null ([layerRowWearsFxSwitch]).
bool? _layerFxValue(RailSwipeHooks hooks, TimelineDisplayRow row) {
  final fxStateOf = hooks.layerFxStateOf;
  if (hooks.onToggleLayerFx == null ||
      fxStateOf == null ||
      !hooks.hands.fx(row) ||
      !layerRowWearsFxSwitch(
        row.layer.kind,
        wearsBaseComposite: hooks.wearsBaseComposite(row.layer),
      )) {
    return null;
  }
  return fxEnabledFromState(fxStateOf(row.layer.id));
}

void _fxToggle(RailSwipeHooks hooks, TimelineDisplayRow row) {
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
///
/// Read LIVE where the host reads it, as every other column is. ↩️It read
/// the row as it was built — the one column of the list that did: a fast
/// swipe, its down and first move in one frame, spread the flag its press
/// had just turned over (I-89 ①ⓒ).
RailToggle<TimelineDisplayRow>? _timesheet(RailSwipeHooks hooks) {
  final onToggle = hooks.onToggleLayerTimesheet;
  if (onToggle == null) return null;
  return (
    valueOf: (row) =>
        !row.isLane &&
            hooks.hands.timesheet(row) &&
            layerCarriesTimesheetToggle(row.layer)
        ? hooks.layerOnTimesheetOf?.call(row.layer.id) ??
              row.layer.onTimesheet
        : null,
    toggle: (row) => onToggle(row.layer.id),
  );
}

/// 🗣️F-475 (유저 2026-10-26): 「클리핑버튼도 위아래 드래그로 여러 버튼
/// 동시조작 가능하게」. A row of a kind that cannot clip carries no button
/// ([LayerKind.takesClipping], the row's own rule) and a lane row's slot is
/// its group's reset — both null.
///
/// Read LIVE where the host reads it, as every column is.
RailToggle<TimelineDisplayRow>? _clip(RailSwipeHooks hooks) {
  final onToggle = hooks.onToggleLayerClip;
  if (onToggle == null) return null;
  return (
    valueOf: (row) => !row.isLane && row.layer.kind.takesClipping
        ? hooks.layerClipsOf?.call(row.layer.id) ?? row.layer.clipsToBelow
        : null,
    toggle: (row) => onToggle(row.layer.id),
  );
}

/// A row with no lanes draws no twirl.
RailToggle<TimelineDisplayRow>? _laneToggle(RailSwipeHooks hooks) {
  final onToggle = hooks.onToggleLayerLanes;
  if (onToggle == null) return null;
  return (
    valueOf: (row) => _laneOpen(hooks, row),
    toggle: (row) => onToggle(row.layer.id),
  );
}

bool? _laneOpen(RailSwipeHooks hooks, TimelineDisplayRow row) {
  if (row.isLane) return null;
  final lanes =
      hooks.lanesForLayer?.call(row.layer) ?? const <PropertyLaneRow>[];
  if (lanes.isEmpty) return null;
  return hooks.laneOpenOf(row.layer.id);
}

/// 🗣️F-475 (유저 2026-10-26): 「다른버튼도 조사」 — and a button I-32 named
/// among a layer's (09-14: 「그룹펼치기」): a folder's fold, or the attach
/// group's riding a base, one twirl at the end of the name
/// ([timelineGroupFoldFor]) on each row that folds rows of its own.
///
/// Read LIVE where the host reads it, as every column is: a row the sweep
/// crosses may have been folded a moment ago by the press, spread across
/// the selection.
RailToggle<TimelineDisplayRow> _groupFold(RailSwipeHooks hooks) => (
  valueOf: (row) {
    if (row.isLane) return null;
    final fold = hooks.foldOf(row);
    if (!fold.has || fold.onToggle == null) return null;
    return hooks.groupFoldOpenOf?.call(row.layer.id) ?? fold.expanded;
  },
  toggle: (row) => hooks.foldOf(row).onToggle?.call(row.layer.id),
);

/// A LANE GROUP's twirl — Transform, an effect — worn by the group's
/// header alone. Read LIVE where the host reads it: the group's open state
/// is its row's (`Layer.expandedLaneGroups`, F-360).
RailToggle<TimelineDisplayRow>? _laneGroupToggle(RailSwipeHooks hooks) {
  final onToggle = hooks.onToggleLaneGroup;
  if (onToggle == null) return null;
  return (
    valueOf: (row) => switch (row.lane) {
      final lane? when lane.isGroupHeader =>
        hooks.laneGroupOpenOf?.call(row.layer.id, lane.laneId) ??
            lane.groupExpanded,
      _ => null,
    },
    toggle: (row) {
      if (row.lane case final lane?) {
        onToggle(row.layer, lane);
      }
    },
  );
}

/// 🗣️F-475 (유저 2026-10-26): 「다른버튼도 조사」 — a lane's ◆: a key at the
/// frame its row stands on, made or taken away, on each member lane that
/// shows one ([PropertyLaneRow.showsKeyNavigator]) and is handed its verbs.
///
/// Read LIVE ([PropertyLaneEditCallbacks.keyedNow]), as every column is: the
/// press keys its row before the sweep can read it.
RailToggle<TimelineDisplayRow> _laneKey(RailSwipeHooks hooks) => (
  valueOf: (row) => switch (_laneInHand(hooks, row)) {
    (:final lane, :final hand)?
        when !lane.isGroupHeader && lane.showsKeyNavigator =>
      hand.edit.keyedNow?.call(row.layer, lane, hand.frame),
    _ => null,
  },
  toggle: (row) {
    if (_laneInHand(hooks, row) case (:final lane, :final hand)?) {
      hand.edit.onToggleKeyAt(row.layer, lane, hand.frame);
    }
  },
);

/// A FLAG lane's ring ([PropertyLaneValueKind.boolean]) — its value at the
/// frame its row stands on, on each lane whose value the row is handed a
/// way to set — read LIVE ([PropertyLaneEditCallbacks.valueNow]) as the ◆
/// is.
RailToggle<TimelineDisplayRow> _laneFlag(RailSwipeHooks hooks) => (
  valueOf: (row) => switch (_flagNow(hooks, row)) {
    final word? => word == flagLaneWord(true),
    null => null,
  },
  toggle: (row) {
    if ((_laneInHand(hooks, row), _flagNow(hooks, row))
        case ((:final lane, :final hand)?, final word?)) {
      hand.edit.onSetValue?.call(
        row.layer,
        lane,
        hand.frame,
        flagLaneWord(word != flagLaneWord(true)),
      );
    }
  },
);

/// [row]'s flag as its ring shows it now — null on a row that wears none.
String? _flagNow(RailSwipeHooks hooks, TimelineDisplayRow row) =>
    switch (_laneInHand(hooks, row)) {
      (:final lane, :final hand)?
          when lane.valueKind == PropertyLaneValueKind.boolean &&
              hand.edit.onSetValue != null =>
        hand.edit.valueNow?.call(row.layer, lane, hand.frame),
      _ => null,
    };

/// [row]'s lane and what it is handed, or null for a layer row or a lane
/// handed nothing.
({PropertyLaneRow lane, LaneRowHand hand})? _laneInHand(
  RailSwipeHooks hooks,
  TimelineDisplayRow row,
) => switch ((row.lane, hooks.laneHandOf(row))) {
  (final lane?, final hand?) => (lane: lane, hand: hand),
  _ => null,
};
