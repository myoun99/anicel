import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart';

/// The display-row plumbing both grids ran through the SAME hooks fields —
/// expanded lanes, hidden sections, the row filter, folded attach groups,
/// the active layer and the fx-enabled predicate — is one query on the
/// bundle now (the audit's clone scan, 2026-09-06). What differed between
/// the grids is a VALUE: the x-sheet's lanes open leftward (R9 #23).
void main() {
  Layer layer(String id, {LayerKind kind = LayerKind.animation}) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: const [],
    timeline: const {},
  );

  const lane = PropertyLaneRow(
    laneId: 'transform',
    label: 'Transform',
    keyedFrames: {},
  );

  List<PropertyLaneRow> lanesFor(Layer layer) => [lane];

  TimelineGridHooks hooks({
    Set<LayerId> expandedLaneLayerIds = const {},
    Set<TimelineSection> hiddenSections = const {},
    TimelineRowFilter rowFilter = TimelineRowFilter.none,
    LayerFxState Function(LayerId layerId)? layerFxStateOf,
    LayerId? activeLayerId,
  }) => TimelineGridHooks(
    activeLayerId: activeLayerId,
    frameCursor: ValueNotifier<int>(0),
    playbackFrameCount: 24,
    exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
    onSelectLayer: (_) {},
    onSelectFrame: (_) {},
    onToggleLayerVisibility: (_) {},
    onLayerOpacityChanged: (_, _) {},
    onToggleLayerTimesheet: (_) {},
    onLayerMarkSelected: (_, _) {},
    expandedLaneLayerIds: expandedLaneLayerIds,
    hiddenSections: hiddenSections,
    rowFilter: rowFilter,
    layerFxStateOf: layerFxStateOf,
  );

  List<String> names(List<TimelineDisplayRow> rows) => [
    for (final row in rows)
      if (row.isLane)
        '${row.layer.id.value}/${row.lane!.laneId}'
      else
        row.layer.id.value,
  ];

  test('an open twirl puts the lanes AFTER the layer on the rail and '
      'BEFORE it on the sheet (R9 #23 is a value, not a flag)', () {
    final layers = [layer('A'), layer('B')];
    final open = hooks(expandedLaneLayerIds: {const LayerId('A')});
    expect(names(open.displayRows(layers, lanesForLayer: lanesFor)), [
      'A',
      'A/transform',
      'B',
    ]);
    expect(
      names(
        open.displayRows(
          layers,
          lanesForLayer: lanesFor,
          lanesPrecedeLayer: true,
        ),
      ),
      ['A/transform', 'A', 'B'],
    );
  });

  test('hidden sections and the fx filter reach the rows through the '
      'hooks, exactly as the builder would be told directly', () {
    final layers = [layer('A'), layer('B'), layer('S', kind: LayerKind.se)];
    final filtered = hooks(
      hiddenSections: {TimelineSection.se},
      rowFilter: const TimelineRowFilter(fxOnly: true),
      layerFxStateOf: (id) =>
          id == const LayerId('B') ? LayerFxState.off : LayerFxState.on,
    );
    final viaHooks = filtered.displayRows(layers, lanesForLayer: lanesFor);
    expect(names(viaHooks), ['A']);
    expect(
      names(viaHooks),
      names(
        buildTimelineDisplayRows(
          layers: layers,
          expandedLayerIds: const {},
          lanesForLayer: lanesFor,
          hiddenSections: {TimelineSection.se},
          rowFilter: const TimelineRowFilter(fxOnly: true),
          fxEnabledOf: filtered.isLayerFxEnabled,
        ),
      ),
    );
  });

  test('isLayerFxEnabled: off is the only "no", and no resolver means on', () {
    final off = hooks(layerFxStateOf: (_) => LayerFxState.off);
    expect(off.isLayerFxEnabled(const LayerId('A')), isFalse);
    final mixed = hooks(layerFxStateOf: (_) => LayerFxState.mixed);
    expect(mixed.isLayerFxEnabled(const LayerId('A')), isTrue);
    expect(hooks().isLayerFxEnabled(const LayerId('A')), isTrue);
  });
}
