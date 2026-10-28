import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_row_span_resolver.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// R27 #14 잔여: a cell drag reaching DOWN into the layer's own property
/// lanes selects cell → lane → lane and stops where the pointer is
/// ("A셀부터 오파시티까지만"), instead of stepping over the whole lane
/// group to the next layer's cells — as ONE band (유저 2026-10-25,
/// conte-sweep-leaves-the-lanes-out-Q1: 「띠 하나로 — 레인 선택을 따로
/// 세우지 않는다(타임라인도)」).
void main() {
  const a = LayerId('layer-a');

  group('the span a cell drag sweeps into its own lanes', () {
    /// Layer A with its transform lanes expanded, then layer B.
    List<TimelineDisplayRow> rowsWithLanes() {
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
                    keyMarks: const {},
                  ),
              ]
            : const [],
      );
    }

    test('stepping into the layer\'s OWN lane rows takes them, in order, '
        'up to the hovered one — the walk that used to skip straight past '
        'them', () {
      final rows = rowsWithLanes();
      for (var step = 1; step <= transformLaneDisplayOrder.length; step += 1) {
        expect(
          resolveSelectionSpanRows(
            rows: rows,
            anchor: const LayerRowAddress(a),
            rowDelta: step,
          ),
          [
            const LayerRowAddress(a),
            for (final laneId in transformLaneDisplayOrder.take(step))
              LaneRowAddress(a, laneId),
          ],
          reason: 'step $step stops on that lane',
        );
      }
    });

    test('past the lane group the span reaches the next LAYER row', () {
      final span = resolveSelectionSpanRows(
        rows: rowsWithLanes(),
        anchor: const LayerRowAddress(a),
        rowDelta: transformLaneDisplayOrder.length + 1,
      );
      expect(span.last, const LayerRowAddress(LayerId('layer-b')));
    });
  });

  group('the session stands ONE band', () {
    EditorSessionManager fixture() {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.createDrawingAtCurrentFrame();
      return s;
    }

    List<TimelineRowAddress> cellsToScale(LayerId layerId) => [
      LayerRowAddress(layerId),
      LaneRowAddress(layerId, 'anchor-point'),
      LaneRowAddress(layerId, 'position'),
      LaneRowAddress(layerId, 'scale'),
    ];

    test('a cell drag ending on a LANE row stands one band whose rows are '
        'the cells row and the lanes it crossed — and no lane selection '
        'beside it', () {
      final s = fixture();
      final layerId = s.activeLayer!.id;

      s.updateFrameRangeSelectionDrag(
        layerId: layerId,
        anchorIndex: 0,
        headIndex: 0,
        spanRows: cellsToScale(layerId),
      );

      expect(s.frameRangeSelection.value!.rows, cellsToScale(layerId));
      expect(
        s.laneRangeSelection.value,
        isNull,
        reason:
            'one band — ↩️a lane selection stood beside it, from the first '
            'transform lane to the hovered one, and the lane verbs read '
            'that and left the band\'s cells',
      );
    });

    test('a lane selection standing before the sweep goes with it — one '
        'selection at a time', () {
      final s = fixture();
      final layerId = s.activeLayer!.id;
      s.updateLaneRangeSelectionDrag(
        layerId: layerId,
        laneId: 'position',
        anchorIndex: 0,
        headIndex: 2,
        spanLaneIds: const ['position'],
      );
      expect(s.laneRangeSelection.value, isNotNull, reason: 'fixture');

      s.updateFrameRangeSelectionDrag(
        layerId: layerId,
        anchorIndex: 0,
        headIndex: 0,
        spanRows: cellsToScale(layerId),
      );

      expect(s.laneRangeSelection.value, isNull);
      expect(s.frameRangeSelection.value, isNotNull);
    });
  });

  // R5 #10 — an fx declares its own manipulators, and the canvas shows
  // exactly what the standing lane declares.
  group('what the canvas can be driven with', () {
    test('the transform group header declares everything its members do', () {
      expect(canvasManipulatorsForLane(transformGroupHeaderLane.laneId), {
        CanvasManipulator.transformBox,
        CanvasManipulator.anchorPoint,
      });
    });

    test('position, scale and rotation are one box — they are what a '
        'transform box IS', () {
      for (final laneId in ['position', 'scale', 'rotation']) {
        expect(
          canvasManipulatorsForLane(laneId),
          {CanvasManipulator.transformBox},
          reason: '$laneId is grabbed through the box, not a handle of its own',
        );
      }
    });

    test('the anchor point is placed WITHOUT the box, because the box turns '
        'about it', () {
      expect(canvasManipulatorsForLane('anchor-point'), {
        CanvasManipulator.anchorPoint,
      });
    });

    test('a lane with nothing to grab declares nothing — opacity, and every '
        'effect parameter', () {
      expect(canvasManipulatorsForLane('opacity'), isEmpty);
      expect(canvasManipulatorsForLane('fx:blur-1:radius'), isEmpty);
      expect(canvasManipulatorsForLane('fx-group:blur-1'), isEmpty);
      expect(canvasManipulatorsForLane(null), isEmpty);
      expect(
        canvasManipulatorsForLane('se-audio'),
        isEmpty,
        reason: 'a lane the transform order never heard of answers nothing '
            'rather than guessing',
      );
    });

    test('every lane the transform group shows is accounted for', () {
      for (final laneId in [
        transformGroupHeaderLane.laneId,
        ...transformLaneDisplayOrder,
      ]) {
        // No lane may fall through unconsidered: the set is the answer,
        // and "empty" is one of the answers.
        expect(canvasManipulatorsForLane(laneId), isNotNull);
      }
      // …and exactly one of them is the anchor's.
      expect(
        [
          for (final laneId in transformLaneDisplayOrder)
            if (canvasManipulatorsForLane(
              laneId,
            ).contains(CanvasManipulator.anchorPoint))
              laneId,
        ],
        ['anchor-point'],
      );
    });
  });
}
