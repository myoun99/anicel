import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_row_span_resolver.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// R27 #14 잔여: a cell drag reaching DOWN into the layer's own property
/// lanes selects cell → lane → lane and stops where the pointer is
/// ("A셀부터 오파시티까지만"), instead of stepping over the whole lane
/// group to the next layer's cells.
void main() {
  group('resolveSelectionSpanHead', () {
    /// Layer A with its transform lanes expanded, then layer B.
    List<TimelineDisplayRow> rowsWithLanes() {
      const a = LayerId('layer-a');
      final layerA = Layer(id: a, name: 'A', frames: const [], timeline: {});
      final layerB = Layer(
        id: const LayerId('layer-b'),
        name: 'B',
        frames: const [],
        timeline: {},
      );
      return buildTimelineDisplayRows(
        layers: [layerA, layerB],
        expandedLayerIds: {a},
        lanesForLayer: (layer) => layer.id == a
            ? [
                for (final laneId in transformLaneDisplayOrder)
                  PropertyLaneRow(
                    laneId: laneId,
                    label: laneId,
                    keyedFrames: const {},
                  ),
              ]
            : const [],
      );
    }

    test('row delta 0 stays on the anchor layer, with no lane', () {
      final head = resolveSelectionSpanHead(
        rows: rowsWithLanes(),
        sourceLayerId: const LayerId('layer-a'),
        rowDelta: 0,
      )!;
      expect(head.layerId, const LayerId('layer-a'));
      expect(head.laneId, isNull);
    });

    test('stepping into the layer\'s OWN lane rows reports the lane — this '
        'is the row walk that used to skip straight past them', () {
      final rows = rowsWithLanes();
      // The rows after A are A's lanes in display order.
      for (var step = 1; step <= transformLaneDisplayOrder.length; step += 1) {
        final head = resolveSelectionSpanHead(
          rows: rows,
          sourceLayerId: const LayerId('layer-a'),
          rowDelta: step,
        )!;
        expect(
          head.layerId,
          const LayerId('layer-a'),
          reason: 'lane rows belong to their own layer',
        );
        expect(
          head.laneId,
          transformLaneDisplayOrder[step - 1],
          reason: 'step $step lands on that lane',
        );
      }
    });

    test('past the lane group the next LAYER row reports no lane', () {
      final head = resolveSelectionSpanHead(
        rows: rowsWithLanes(),
        sourceLayerId: const LayerId('layer-a'),
        rowDelta: transformLaneDisplayOrder.length + 1,
      )!;
      expect(head.layerId, const LayerId('layer-b'));
      expect(head.laneId, isNull);
    });
  });

  group('the session publishes both halves of a mixed drag', () {
    EditorSessionManager fixture() {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      s.createDrawingAtCurrentFrame();
      return s;
    }

    test('a cell drag ending on a LANE row selects the cells AND the lane '
        'group down to that lane, over the same frame range', () {
      final s = fixture();
      final layerId = s.activeLayer!.id;

      s.updateFrameRangeSelectionDrag(
        layerId: layerId,
        anchorIndex: 0,
        headIndex: 0,
        headLayerId: layerId,
        headLaneId: 'scale',
      );

      final cells = s.frameRangeSelection.value!;
      final lanes = s.laneRangeSelection.value!;
      expect(cells.layerId, layerId);
      expect(lanes.layerId, layerId);
      // The lane rows the drag actually crossed: the group's FIRST lane
      // (the row directly under the cells) down to the hovered one.
      expect(lanes.spanLaneIds, ['anchor-point', 'position', 'scale']);
      expect(
        lanes.coversLane(layerId, 'rotation'),
        isFalse,
        reason: 'the drag stopped at scale',
      );
      // One rectangle: the lane half shares the cells' snapped range.
      expect(lanes.startIndex, cells.startIndex);
      expect(lanes.endIndexExclusive, cells.endIndexExclusive);
    });

    test('a plain cell drag still clears the lane selection (the domains '
        'stay exclusive unless ONE drag produced both)', () {
      final s = fixture();
      final layerId = s.activeLayer!.id;

      s.updateFrameRangeSelectionDrag(
        layerId: layerId,
        anchorIndex: 0,
        headIndex: 0,
        headLayerId: layerId,
        headLaneId: 'scale',
      );
      expect(s.laneRangeSelection.value, isNotNull);

      // Dragging again without reaching a lane row drops the lane half.
      s.updateFrameRangeSelectionDrag(
        layerId: layerId,
        anchorIndex: 0,
        headIndex: 0,
      );
      expect(s.laneRangeSelection.value, isNull);
      expect(s.frameRangeSelection.value, isNotNull);
    });

    test('a lane id from ANOTHER layer is not a tail — the lane domain is '
        'one layer\'s keys', () {
      final s = fixture();
      final layerId = s.activeLayer!.id;
      s.addLayer();
      final otherId = s.activeLayer!.id;
      s.selectLayer(layerId);

      s.updateFrameRangeSelectionDrag(
        layerId: layerId,
        anchorIndex: 0,
        headIndex: 0,
        headLayerId: otherId,
        headLaneId: 'scale',
      );
      expect(s.laneRangeSelection.value, isNull);
      expect(s.frameRangeSelection.value, isNotNull);
    });
  });
}
