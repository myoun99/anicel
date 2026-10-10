import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/timeline/lane_graph.dart';
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:flutter_test/flutter_test.dart';

/// **I-89 ③ — what a header graph draws as its own.**
///
/// 🗣️The mock's law (5판, 유저 2026-10-10 「서는곳 법 그대로」): the group's
/// selected lanes; none selected, the lane stood on, where it is the
/// group's; stood outside the group, all of it — and every lane of the
/// group pinned to every graph, besides.
void main() {
  const a = LayerId('a');
  const b = LayerId('b');
  final transform = transformGroupHeaderLane.laneId;
  final key = laneGroupKey(a, transform);

  TimelineDisplayRow lane(LayerId id, String laneId, {bool header = false}) =>
      TimelineDisplayRow.lane(
        Layer(id: id, name: id.value, frames: const []),
        PropertyLaneRow(
          laneId: laneId,
          label: laneId,
          keyMarks: const {},
          isGroupHeader: header,
        ),
        layerIndex: id == a ? 0 : 1,
      );

  final rows = [
    lane(a, transform, header: true),
    lane(a, 'position'),
    lane(a, 'scale'),
    lane(a, 'rotation'),
    lane(b, transform, header: true),
    lane(b, 'position'),
  ];

  TimelineGraphSeat seatOf({
    Set<TimelineRowAddress> selection = const {},
    Set<String> pinned = const {},
  }) =>
      seatLaneGraphs(
        rows,
        LaneGraphsView(open: {key: const LaneGraph()}, pinned: pinned),
        selection: selection,
      )[1].graph!;

  group('a seat is told which of its lanes are picked and pinned', () {
    test('the selection\'s lanes of THIS group, in the rail\'s order', () {
      final seat = seatOf(
        selection: {
          const LaneRowAddress(a, 'rotation'),
          const LaneRowAddress(a, 'position'),
          // The same lane on another row, the group's own header and its
          // layer's row: none is one of this graph's lanes.
          const LaneRowAddress(b, 'position'),
          LaneRowAddress(a, transform),
          const LayerRowAddress(a),
        },
      );
      expect(seat.lanes, ['position', 'scale', 'rotation']);
      expect(seat.picked, ['position', 'rotation']);
      expect(seat.pinned, isEmpty);
    });

    test('the group\'s pinned lanes, and no other row\'s', () {
      final seat = seatOf(
        pinned: {laneGroupKey(a, 'scale'), laneGroupKey(b, 'position')},
      );
      expect(seat.pinned, ['scale']);
      expect(seat.picked, isEmpty);
    });
  });

  group('what the graph draws as its own', () {
    test('the picked lanes, wherever you stand', () {
      final seat = seatOf(
        selection: {
          const LaneRowAddress(a, 'scale'),
          const LaneRowAddress(a, 'rotation'),
        },
      );
      expect(
        laneGraphDrawnLanes(seat, const LaneRowAddress(a, 'position')),
        ['scale', 'rotation'],
      );
    });

    test('none picked: the lane stood on, when it is the group\'s', () {
      expect(
        laneGraphDrawnLanes(seatOf(), const LaneRowAddress(a, 'scale')),
        ['scale'],
      );
    });

    test('stood outside the group — its header, its layer, another row\'s '
        'lane of the same name, nowhere — all of it', () {
      final seat = seatOf();
      for (final standing in <TimelineRowAddress?>[
        LaneRowAddress(a, transform),
        const LayerRowAddress(a),
        const LaneRowAddress(b, 'position'),
        null,
      ]) {
        expect(
          laneGraphDrawnLanes(seat, standing),
          ['position', 'scale', 'rotation'],
          reason: 'standing on $standing',
        );
      }
    });

    test('and the group\'s pinned lanes besides, in the rail\'s order', () {
      final seat = seatOf(pinned: {laneGroupKey(a, 'position')});
      expect(
        laneGraphDrawnLanes(seat, const LaneRowAddress(a, 'rotation')),
        ['position', 'rotation'],
      );
    });
  });
}
