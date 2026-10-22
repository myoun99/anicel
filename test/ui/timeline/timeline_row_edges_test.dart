import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart' show EffectId;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/lane_graph.dart';
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/reference_lane_policy.dart'
    show referenceGroupLaneId, referenceLaneDisplayOrder;
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart'
    show seNameTagGroupLaneId, seNameTagLaneDisplayOrder;
import 'package:anicel/src/ui/timeline/timeline_current_row.dart'
    show laneGroupOf;
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edges.dart';
import 'package:anicel/src/ui/timeline/timeline_section_runs.dart';
import 'package:anicel/src/ui/timeline/timeline_visible_range.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:flutter_test/flutter_test.dart';

/// I-89 ③ — where every drawn row sits is ONE answer.
///
/// A header graph stands taller than its lanes, and what it stands taller
/// is ROOM after its last lane: no row, nothing to stand on or select. So a
/// row's place stopped being `index × row height`, and the rail, the cells,
/// the sheet, the cursor and every drag read [TimelineRowEdges] instead.
void main() {
  group('rows of one height read exactly as the division did', () {
    test('the window is the uniform division anywhere inside the rows', () {
      for (final extent in [28.0, 20.5]) {
        for (final count in [0, 1, 5, 40]) {
          final edges = TimelineRowEdges.uniform(count, extent);
          final total = count * extent;
          for (final viewport in [0.0, 50.0, 196.0, 1000.0]) {
            for (final overscan in [0, 2, 3]) {
              for (var at = 0.0; at < total; at += extent / 3) {
                expect(
                  edges.window(
                    scrollOffset: at,
                    viewportExtent: viewport,
                    overscanBefore: overscan,
                    overscanAfter: overscan,
                  ),
                  calculateVisibleIndexRange(
                    scrollOffset: at,
                    viewportExtent: viewport,
                    itemExtent: extent,
                    itemCount: count,
                    overscanBefore: overscan,
                    overscanAfter: overscan,
                  ),
                  reason: 'extent $extent, $count rows, viewport $viewport, '
                      'overscan $overscan, at $at',
                );
              }
            }
          }
        }
      }
    });

    test('a pointer stands on the row the division floored to, clamped to '
        'the rows', () {
      final edges = TimelineRowEdges.uniform(10, 28);
      int from(int anchor, double offset) =>
          edges.rowFrom(anchor, offset) - anchor;

      expect(from(4, 0), 0);
      expect(from(4, 27.9), 0);
      expect(from(4, 28), 1);
      expect(from(4, -0.1), -1, reason: 'anything above this row is -1');
      expect(from(4, -28), -1);
      expect(from(4, -28.1), -2);
      expect(from(4, 1000), 5, reason: 'the last row, not past it');
      expect(from(4, -1000), -4, reason: 'the first row, not before it');
    });

    test('a pointer counts in rows from its row\'s start', () {
      final edges = TimelineRowEdges.uniform(10, 28);
      expect(edges.rowsAt(4, 14), 0.5);
      expect(edges.rowsAt(4, 42), 1.5);
      expect(edges.rowsAt(4, -14), -0.5);
      expect(edges.rowsAt(9, 56), 2, reason: 'past the end it carries on');
      expect(edges.rowsAt(0, -56), -2, reason: 'and before the start');
    });

    test('a stretch covers the rows it meets, ends included', () {
      final edges = TimelineRowEdges.uniform(10, 28);
      expect(edges.rowsIn(0, 0), (first: 0, last: 0));
      expect(edges.rowsIn(27, 29), (first: 0, last: 1));
      expect(edges.rowsIn(29, 27), (first: 0, last: 1), reason: 'any order');
      expect(edges.rowsIn(-50, -1), isNull);
      expect(edges.rowsIn(280, 300), isNull, reason: 'past the rows');
    });
  });

  group('room after a graph\'s last lane is no row', () {
    // Row 0, a graph of rows 1–2 with 140 of room after row 2, row 3.
    final edges = TimelineRowEdges([
      (extent: 28, room: 0, joinsNext: false),
      (extent: 28, room: 0, joinsNext: true),
      (extent: 28, room: 140, joinsNext: false),
      (extent: 28, room: 0, joinsNext: false),
    ]);

    test('rows sit after the room before them', () {
      expect([for (var i = 0; i <= 4; i += 1) edges.startOf(i)], [
        0,
        28,
        56,
        224,
        252,
      ]);
      expect(edges.total, 252);
      expect(edges.extentOf(2), 28, reason: 'its room is not its extent');
      expect(edges.endOf(2), 84);
      expect(edges.roomOf(2), 140);
      expect(edges.roomOf(1), 0);
    });

    test('joined rows draw as one unit, the room after it included', () {
      expect(edges.unitOf(1), (first: 1, last: 2));
      expect(edges.unitOf(2), (first: 1, last: 2));
      expect(edges.unitOf(0), (first: 0, last: 0));
      expect(edges.unitSpanOf(2), (start: 28.0, extent: 196.0));
      expect(edges.unitSpanOf(3), (start: 224.0, extent: 28.0));
      expect(edges.unitsIn(0, 4).toList(), [
        (first: 0, last: 0),
        (first: 1, last: 2),
        (first: 3, last: 3),
      ]);
      expect(edges.unitsIn(0, 2).toList(), [
        (first: 0, last: 0),
        (first: 1, last: 1),
      ], reason: 'a unit the stretch cuts ends where the stretch does');
    });

    test('nobody stands in the room', () {
      expect(edges.rowAt(83.9), 2);
      expect(edges.rowAt(84), isNull);
      expect(edges.rowAt(150), isNull);
      expect(edges.rowAt(224), 3);
      expect(edges.rowAt(-1), isNull);
      expect(edges.rowAt(252), isNull);
      expect(edges.slotAt(150), 2, reason: 'the slot is the row and room');
    });

    test('a drag that ends in the room reaches the row on its own side', () {
      expect(edges.rowFrom(0, 150), 2, reason: 'from above: the last lane');
      expect(edges.rowFrom(3, -74), 3, reason: 'from below: its own row');
      expect(edges.rowFrom(3, -200), 0);
      expect(edges.rowFrom(0, 1000), 3);
      expect(edges.rowFrom(3, -1000), 0);
    });

    test('across the room a pointer stands at one gap', () {
      expect(edges.rowsAt(0, 100), 3, reason: 'room: the next row\'s edge');
      expect(edges.rowsAt(0, 200), 3);
      expect(edges.rowsAt(0, 238), 3.5);
      expect(edges.rowsAt(3, -50), 0, reason: 'the same gap from below');
      expect(edges.rowsAt(0, 280), 5, reason: 'past the end, in row heights');
    });

    test('a stretch inside the room covers no row', () {
      expect(edges.rowsIn(90, 200), isNull);
      expect(edges.rowsIn(60, 90), (first: 2, last: 2));
      expect(edges.rowsIn(90, 230), (first: 3, last: 3));
    });

    test('a window never cuts a unit', () {
      expect(
        edges.window(
          scrollOffset: 100,
          viewportExtent: 50,
          overscanBefore: 0,
          overscanAfter: 0,
        ),
        const TimelineVisibleRange(startIndex: 1, endIndexExclusive: 3),
        reason: 'only the room is in view, and its unit is built whole',
      );
      expect(
        edges.window(
          scrollOffset: 30,
          viewportExtent: 10,
          overscanBefore: 0,
          overscanAfter: 0,
        ),
        const TimelineVisibleRange(startIndex: 1, endIndexExclusive: 3),
        reason: 'one lane in view builds the graph',
      );
      expect(
        edges.window(
          scrollOffset: 0,
          viewportExtent: 10,
          overscanBefore: 0,
          overscanAfter: 0,
        ),
        const TimelineVisibleRange(startIndex: 0, endIndexExclusive: 1),
      );
    });
  });

  group('a group\'s lanes are seated in its graph', () {
    const layerId = LayerId('a');
    final layer = Layer(id: layerId, name: 'A', frames: const []);
    const blur = EffectId('blur');
    TimelineDisplayRow lane(String laneId, {bool header = false}) =>
        TimelineDisplayRow.lane(
          layer,
          PropertyLaneRow(
            laneId: laneId,
            label: laneId,
            keyMarks: const {},
            isGroupHeader: header,
          ),
          layerIndex: 0,
        );
    final rows = [
      TimelineDisplayRow.layer(layer, layerIndex: 0),
      lane(transformGroupHeaderLane.laneId, header: true),
      lane('position'),
      lane('scale'),
      lane(effectGroupLaneId(blur), header: true),
      lane(effectLaneId(blur, 'radius')),
    ];
    final transformKey = laneGroupKey(layerId, 'transform-group');
    final blurKey = laneGroupKey(layerId, effectGroupLaneId(blur));
    const metrics = TimelineGridMetrics.defaults;
    const row = timelineLayerRowHeight;
    List<TimelineDisplayRow> seatOpen(Map<String, LaneGraph> open) =>
        seatLaneGraphs(rows, LaneGraphsView(open: open), selection: const {});

    test('a lane answers with its group; a header and a layer with none', () {
      expect(laneGroupOf('position'), 'transform-group');
      expect(laneGroupOf('opacity'), 'transform-group');
      expect(
        laneGroupOf(effectLaneId(blur, 'radius')),
        effectGroupLaneId(blur),
      );
      expect(laneGroupOf('transform-group'), isNull);
      expect(laneGroupOf(effectGroupLaneId(blur)), isNull);
      expect(laneGroupOf('se-audio'), isNull);
    });

    test('the two fixed groups\' lanes answer with their own header — the '
        'reference fx\'s Position is not the transform\'s (F-374)', () {
      for (final laneId in referenceLaneDisplayOrder) {
        expect(laneGroupOf(laneId), referenceGroupLaneId, reason: laneId);
      }
      for (final laneId in seNameTagLaneDisplayOrder) {
        expect(laneGroupOf(laneId), seNameTagGroupLaneId, reason: laneId);
      }
      expect(laneGroupOf(referenceGroupLaneId), isNull);
      expect(laneGroupOf(seNameTagGroupLaneId), isNull);
    });

    test('only the pressed group\'s lanes take a seat', () {
      const graph = LaneGraph(extent: 196);
      final seated = seatOpen({transformKey: graph});
      expect([for (final row in seated) row.graph?.groupKey], [
        null,
        null,
        transformKey,
        transformKey,
        null,
        null,
      ]);
      expect(seated[2].graph!.graph, graph);
      expect(
        seated[2].graph!.lanes,
        ['position', 'scale'],
        reason: 'a seat names the lanes drawn in it, as the rail draws them',
      );
      expect(
        [for (final row in seated) row.address],
        [for (final row in rows) row.address],
        reason: 'the rows are the same rows — 「서는곳 법 그대로」',
      );
      expect(seatOpen(const {}), same(rows));
    });

    test('each open graph is one block of its seated lanes', () {
      final seated = seatOpen({
        transformKey: const LaneGraph(),
        blurKey: const LaneGraph(extent: 100),
      });
      final blocks = timelineGraphBlocks(seated);
      expect([for (final b in blocks) (b.start, b.count, b.seat.groupKey)], [
        (2, 2, transformKey),
        (5, 1, blurKey),
      ]);
      expect(blocks.last.seat.lanes, [effectLaneId(blur, 'radius')]);
    });

    test('a graph stands its own extent: its lanes and the room after the '
        'last', () {
      final seated = seatOpen({
        transformKey: const LaneGraph(),
        blurKey: const LaneGraph(extent: 10),
      });
      final edges = timelineRowEdgesOf(seated, metrics);
      expect(edges.roomOf(2), 0);
      expect(
        edges.roomOf(3),
        (laneGraphOpeningRows - 2) * row,
        reason: 'opens seven rows tall',
      );
      expect(edges.unitOf(2), (first: 2, last: 3));
      expect(edges.roomOf(5), 0, reason: 'never shorter than its lanes');
      expect(edges.total, rows.length * row + edges.roomOf(3));
      expect(
        timelineRowEdgesOf(rows, metrics).total,
        rows.length * row,
        reason: 'no graph open, no room',
      );
    });

    test('a span\'s head is counted where the rows sit', () {
      final seated = seatOpen({transformKey: const LaneGraph()});
      final edges = timelineRowEdgesOf(seated, metrics);
      const anchor = LayerRowAddress(layerId);
      // Into the room after `scale`: the lane on the anchor's side.
      expect(timelineRowDeltaAt(seated, edges, anchor, 4 * row + 10), 3);
      // Past the room, on the Blur header.
      expect(timelineRowDeltaAt(seated, edges, anchor, edges.startOf(4)), 4);
      const stranger = LayerRowAddress(LayerId('x'));
      expect(
        timelineRowDeltaAt(seated, edges, stranger, 100),
        0,
        reason: 'an anchor that is not drawn reaches nothing',
      );
    });

    // I-89 ③D, the mock's 5판: 「크게 보기는 다른 행을 얇은 띠로 접어 패널
    // 대부분을 이 그래프에 줍니다」 — a shut group's lanes thinned one by
    // one, another open graph thinned whole, every header and layer row
    // left standing.
    group('an enlarged graph folds every other lane', () {
      /// [open], the graph of [enlarged] among them enlarged.
      List<TimelineDisplayRow> seatEnlarged(
        Map<String, LaneGraph> open,
        String enlarged,
      ) => seatOpen({
        ...open,
        enlarged: (open[enlarged] ?? const LaneGraph()).copyWith(
          enlarged: true,
        ),
      });
      const view = 400.0;
      final most = laneGraphMostExtent(view, row);

      test('its own lanes stand, every other lane folds, every header and '
          'layer row stands', () {
        final seated = seatEnlarged({
          transformKey: const LaneGraph(),
          blurKey: const LaneGraph(),
        }, transformKey);
        expect([for (final row in seated) row.folded], [
          false,
          false,
          false,
          false,
          false,
          true,
        ]);
        expect([for (final row in seated) row.graph?.graph.enlarged], [
          null,
          null,
          true,
          true,
          null,
          false,
        ], reason: 'the enlarged graph knows it is, the folded one too');
        final shut = seatEnlarged({
          transformKey: const LaneGraph(),
        }, transformKey);
        expect(
          [for (final row in shut) row.folded],
          [false, false, false, false, false, true],
          reason: 'a lane of a shut group folds as one of an open graph',
        );
      });

      test('a graph enlarged where it is not drawn folds nothing', () {
        // Open on a row these are not — another cut's.
        final elsewhere = laneGroupKey(const LayerId('x'), 'transform-group');
        final seated = seatEnlarged({
          transformKey: const LaneGraph(),
        }, elsewhere);
        expect([for (final row in seated) row.folded], everyElement(isFalse));
        expect([for (final row in seated) row.graph?.graph.enlarged], [
          null,
          null,
          false,
          false,
          null,
          null,
        ]);
      });

      test('it stands as far as the view lets one — the view less its '
          'header\'s row', () {
        expect(most, view - row);
        final edges = timelineRowEdgesOf(
          seatEnlarged({transformKey: const LaneGraph()}, transformKey),
          metrics,
          view: view,
        );
        expect(edges.extentOf(2) + edges.extentOf(3) + edges.roomOf(3), most);
        expect(edges.graphMost, most, reason: 'the grip\'s ceiling, carried');
        expect(
          timelineRowEdgesOf(
            seatEnlarged({transformKey: const LaneGraph()}, transformKey),
            metrics,
          ).roomOf(3),
          (laneGraphOpeningRows - 2) * row,
          reason: 'laid along no view, as its grip says',
        );
        expect(laneGraphMostExtent(row / 2, row), 0);
      });

      test('a folded lane is a thin strip; a folded graph ONE strip, its '
          'first lane\'s, and no room', () {
        final edges = timelineRowEdgesOf(
          seatEnlarged({
            transformKey: const LaneGraph(extent: 300),
            blurKey: const LaneGraph(),
          }, blurKey),
          metrics,
          view: view,
        );
        expect(edges.extentOf(2), laneGraphFoldedExtent);
        expect(edges.extentOf(3), 0);
        expect(edges.roomOf(3), 0);
        expect(edges.unitSpanOf(2).extent, laneGraphFoldedExtent);
        expect(edges.extentOf(1), row, reason: 'its header stands');
        expect(edges.extentOf(5) + edges.roomOf(5), most);
        final shut = timelineRowEdgesOf(
          seatEnlarged({blurKey: const LaneGraph()}, blurKey),
          metrics,
          view: view,
        );
        expect(
          [shut.extentOf(2), shut.extentOf(3)],
          [laneGraphFoldedExtent, laneGraphFoldedExtent],
          reason: 'a shut group\'s lanes, each its own strip',
        );
      });

      test('a graph kept taller than the view lets one stands at the most',
          () {
        final open = {transformKey: const LaneGraph(extent: 5000)};
        final seated = seatLaneGraphs(
          rows,
          LaneGraphsView(open: open),
          selection: const {},
        );
        final edges = timelineRowEdgesOf(seated, metrics, view: view);
        expect(edges.extentOf(2) + edges.extentOf(3) + edges.roomOf(3), most);
        expect(
          timelineRowEdgesOf(seated, metrics).roomOf(3),
          5000 - 2 * row,
          reason: 'laid along no view, nothing caps it',
        );
        expect(
          timelineRowEdgesOf(seated, metrics).graphMost,
          double.infinity,
        );
      });
    });
  });
}
