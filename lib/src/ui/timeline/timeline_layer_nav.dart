import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_row_address.dart';
import 'layer_timeline_display_adapter.dart';
import 'property_lane_model.dart';
import 'timeline_row_filter.dart';
import 'timeline_section_policy.dart';

/// The DISPLAYED-layer step target for the ↑/↓ layer nav (UI-R20 #14,
/// TVP-style): walks the rows exactly as the timeline stacks them — the
/// horizontal display order (camera section on top, drawing cels at the
/// bottom), with hidden sections, the row filter and folded attach
/// groups dropping layers here exactly like they drop rows there (an
/// open attach group walks, a folded one skips — #14's attach clause). A
/// filtered view navigates only what's on screen; on the X-sheet the
/// same walk reads right-to-left (its columns are the row stack
/// rotated).
///
/// [direction] -1 = the row visually ABOVE (screen-up = earlier in
/// horizontal display order, the moveSelectionToFilteredLayer rule).
/// Steps clamp at the ends. When the active layer itself isn't displayed
/// (its whole section is folded), the step enters the visible rows from
/// the matching end: ↓ lands on the top displayed row, ↑ on the bottom.
/// Null = no move.
/// R10 #19: the walk stops on PROPERTY rows too, so ↑/↓ can land on one —
/// the user's "화살표는 프로퍼티가 인식범위에 들어가서 프로퍼티 이동되도
/// 괜찮은데". They were not merely skipped before: the rows were built with
/// no lane provider at all, so lane rows never existed and the two
/// `!row.isLane` guards below were dead code.
///
/// Returns the row's ADDRESS, because a lane row is not a layer — but it
/// always names its owner, so the caller can keep the drawing target on
/// the layer the property belongs to. Pass [lanesForLayer] and
/// [expandedLayerIds] to include lanes; omit them and the walk is exactly
/// the layer-row walk it always was.
TimelineRowAddress? adjacentDisplayedRow({
  required List<Layer> layers,
  required LayerId? activeLayerId,
  required int direction,
  TimelineRowAddress? currentRow,
  Set<TimelineSection> hiddenSections = const {},
  TimelineRowFilter rowFilter = TimelineRowFilter.none,
  Set<LayerId> collapsedAttachBaseIds = const {},
  Set<LayerId> expandedLayerIds = const {},
  List<PropertyLaneRow> Function(Layer layer)? lanesForLayer,
  bool Function(LayerId layerId)? fxEnabledOf,
}) {
  // R27 #27: a collapsed folder's members are not on screen, so the walk
  // must not stop on them ("접혀져있으면 표시된거만 선택하는 룰") — the row
  // builder already drops them. FOLDER rows themselves are ordinary stops:
  // they are layers, so the old "step OVER the header, it only carries a
  // representative member" special case is gone.
  final rows = buildTimelineDisplayRows(
    layers: horizontalLayerDisplayOrder(layers),
    expandedLayerIds: expandedLayerIds,
    lanesForLayer: lanesForLayer ?? (_) => const [],
    hiddenSections: hiddenSections,
    rowFilter: rowFilter,
    collapsedAttachBaseIds: collapsedAttachBaseIds,
    activeLayerId: activeLayerId,
    fxEnabledOf: fxEnabledOf,
    stack: layers,
  );
  if (rows.isEmpty || direction == 0) {
    return null;
  }

  TimelineRowAddress addressOf(TimelineDisplayRow row) => row.isLane
      ? LaneRowAddress(row.layer.id, row.lane!.laneId)
      : LayerRowAddress(row.layer.id);

  // Where we are: the row the caller says it is on, falling back to the
  // active layer's own row for callers that have no row notion yet.
  var activeIndex = -1;
  for (var index = 0; index < rows.length; index += 1) {
    final address = addressOf(rows[index]);
    if (currentRow != null ? address == currentRow : address == LayerRowAddress(activeLayerId ?? const LayerId(''))) {
      activeIndex = index;
      break;
    }
  }
  if (activeIndex == -1) {
    for (var index = 0; index < rows.length; index += 1) {
      if (!rows[index].isLane && rows[index].layer.id == activeLayerId) {
        activeIndex = index;
        break;
      }
    }
  }

  final int targetIndex;
  if (activeIndex == -1) {
    targetIndex = direction > 0 ? 0 : rows.length - 1;
  } else {
    final next = (activeIndex + direction).clamp(0, rows.length - 1);
    if (next == activeIndex) {
      return null;
    }
    targetIndex = next;
  }
  final target = addressOf(rows[targetIndex]);
  return target == currentRow ? null : target;
}

/// The imperative layer-nav channel (UI-R20 #14): the app-level ↑/↓
/// shortcuts call in from the dispatch; the workspace binds the handler
/// (it owns the row filter / hidden-section view state the walk needs).
/// Unbound calls are no-ops — the CanvasSelectionCommands idiom.
class TimelineLayerNavCommands {
  void Function(int direction)? _step;

  void bind(void Function(int direction) step) {
    _step = step;
  }

  void unbind() {
    _step = null;
  }

  /// Moves the active layer [direction] displayed rows (-1 = up).
  void step(int direction) => _step?.call(direction);
}
