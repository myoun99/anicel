import 'package:flutter/widgets.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_mark.dart';
import 'property_lane_model.dart';
import 'rail_column_swipe.dart' show RailSweepHistory;
import 'timeline_grid_hooks.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_layer_controls_header.dart';
import 'timeline_legend_menus.dart';

/// A timeline grid as its legend reads it — the timeline's and the
/// x-sheet's alike.
abstract interface class TimelineLegendHost {
  /// What a sweep is written through ([RailSweepHistory]).
  BuildContext get context;

  /// What the panel tells the grid — its legend among the rest
  /// ([TimelineGridHooks.legend]).
  TimelineGridHooks get hooks;

  List<Layer> get layers;

  /// The rows the latest pass drew.
  List<TimelineDisplayRow> get drawnRows;
}

/// The legend over a timeline grid's rail, made by one hand for both grids
/// — so the x-sheet's corner opens every flyout the timeline's header does,
/// on the rows the x-sheet draws (F-408 ②).
///
/// One per grid, kept for its life: the header is kept while what it shows
/// holds (I-57), so what it reads when a flyout opens or a verb is pressed,
/// and what it sweeps, is asked of [_grid] then — through the same
/// tear-offs from build to build.
final class TimelineGridLegendRail {
  TimelineGridLegendRail(this._grid);

  final TimelineLegendHost _grid;

  /// The header, [axis] being the rail's own direction — its menus told to
  /// the panel (I-40): the very menus it opens, counted on this grid's rows.
  TimelineLayerControlsHeader header({
    required TimelineGridMetrics metrics,
    Axis axis = Axis.horizontal,
    double? railExtent,
  }) {
    final hooks = _grid.hooks;
    final legend = hooks.legend;
    final twirls = hooks.onToggleLayerLanes != null;
    final header = TimelineLayerControlsHeader(
      axis: axis,
      railExtent: railExtent,
      metrics: metrics,
      optionalColumns: hooks.optionalRailColumns,
      legend: legend.verbs,
      hiddenSections: hooks.hiddenSections,
      onToggleSection: legend.onToggleSection,
      rowFilter: hooks.rowFilter,
      marksInUse: _marksInUse,
      kinds: timelineRailKinds,
      visibilitySoloEnabled: legend.visibilitySoloEnabled,
      anyLanesExpanded: hooks.expandedLaneLayerIds.isNotEmpty,
      // The set a bulk verb ACTS on, read at the press — of the rows the
      // latest pass drew. 🚨I-57 ㉢-2 (10-13, measured on the user's
      // project): captured here and kept fresh by the token, it changed at
      // every cut switch and built the whole header again — 223 widgets of
      // a crossing's 855, for a set no cell of the header shows.
      displayedLayerIds: _displayedLayerIds,
      displayedOpacity: legend.displayedOpacity,
      displayedOnionSkinOn: legend.displayedOnionSkinOn,
      onExpandAllLanes: twirls ? _expandAllLanes : null,
      onCollapseAllLanes: twirls ? _collapseAllLanes : null,
    );
    legend.onMenus?.call(header.legend == null ? null : header.menus);
    return header;
  }

  /// Marks assigned across the grid's layers — the mark-solo menu's
  /// "solo color X" list is built from these.
  Set<LayerMark> _marksInUse() => {
    for (final layer in _grid.layers)
      if (layer.mark != LayerMark.none) layer.mark,
  };

  /// The rows the rail currently DISPLAYS (layer rows only, camera
  /// excluded) — the master opacity bar's target set (R4 #6).
  Set<LayerId> _displayedLayerIds() => {
    for (final row in _grid.drawnRows)
      if (!row.isLane && row.layer.kind.hasPictureOpacity) row.layer.id,
  };

  /// Legend LAYER-cell sweeps: the grid owns the lane knowledge (which
  /// layers HAVE lanes, which are expanded), so the all-lane fold rides its
  /// existing per-layer toggle — as ONE undo step, a twirl being the row's
  /// and written through history (F-360) ([RailSweepHistory.asOneStep]).
  void _expandAllLanes() {
    final onToggle = _grid.hooks.onToggleLayerLanes;
    if (onToggle == null) {
      return;
    }
    RailSweepHistory.asOneStep(_grid.context, 'Expand all lanes', () {
      for (final layer in _grid.layers) {
        if (_grid.hooks.lanesOf(layer).isNotEmpty && !_laneOpen(layer.id)) {
          onToggle(layer.id);
        }
      }
    });
  }

  void _collapseAllLanes() {
    final onToggle = _grid.hooks.onToggleLayerLanes;
    if (onToggle == null) {
      return;
    }
    final open = _grid.hooks.expandedLaneLayerIds.toList();
    RailSweepHistory.asOneStep(_grid.context, 'Collapse all lanes', () {
      for (final layerId in open) {
        if (_laneOpen(layerId)) {
          onToggle(layerId);
        }
      }
    });
  }

  /// Read LIVE before every turn: a twirl pressed inside the row selection
  /// turns every selected row (I-32), so a row the sweeps above reach may
  /// already have been turned by an earlier one — and toggling it again
  /// would turn it back.
  bool _laneOpen(LayerId id) {
    final hooks = _grid.hooks;
    return hooks.laneOpenOf?.call(id) ??
        hooks.expandedLaneLayerIds.contains(id);
  }
}
