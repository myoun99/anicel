import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:anicel/src/models/layer_effect.dart' show EffectId;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectLaneId;
import 'package:anicel/src/ui/timeline/lane_graph.dart';
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_coordinate_policy.dart'
    show timelineFrameEdge;
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart'
    show TimelineFrameGeometry;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';

/// **I-89 ③ — where a header graph puts a line**: along the frames as the
/// lanes' own rows lay them, and across the graph fitted to that line's
/// own range (the mock's, 5판: 「곡선마다 제 범위로 맞춰 겹침」 — AE's
/// normalised view, a 12% spare, a 16px padding).
void main() {
  const frames = TimelineFrameGeometry(
    frameCellExtent: 24,
    frameStartIndex: 4,
    frameEndIndexExclusive: 10,
    leadingFrameSpacerWidth: 30,
  );
  const window = (startIndex: 4, endIndexExclusive: 10);

  group('along the frames', () {
    test('a frame stands in the middle of its cell, where its key is '
        'marked', () {
      expect(laneGraphAlong(4, frames), 30 + 12);
      expect(laneGraphAlong(7, frames), 30 + 3 * 24 + 12);
    });

    test('a time between two frames stands between their middles', () {
      expect(laneGraphAlong(5.25, frames), 30 + 24 + 12 + 6);
    });

    test('a cell the frame law rounds is followed to its middle', () {
      const odd = TimelineFrameGeometry(
        frameCellExtent: 10.4,
        frameStartIndex: 0,
        frameEndIndexExclusive: 4,
      );
      expect(
        laneGraphAlong(1, odd),
        (timelineFrameEdge(1, 10.4) + timelineFrameEdge(2, 10.4)) / 2,
      );
    });
  });

  group('the times a line is read at', () {
    test('from the first frame\'s leading edge to the last\'s trailing one, '
        'every frame among them, an eighth of a frame apart at 24px', () {
      final times = laneGraphTimes(window, 24).toList();
      expect(times.first, 3.5);
      expect(times.last, 9.5);
      for (var frame = 4; frame < 10; frame += 1) {
        expect(times, contains(frame.toDouble()));
      }
      for (var index = 1; index < times.length; index += 1) {
        expect(times[index] - times[index - 1], closeTo(0.125, 1e-9));
      }
    });

    test('never before frame 0', () {
      final times = laneGraphTimes((
        startIndex: 0,
        endIndexExclusive: 3,
      ), 24).toList();
      expect(times.first, 0);
      expect(times.where((time) => time < 0), isEmpty);
    });

    test('no closer than two pixels on a narrow cell', () {
      final times = laneGraphTimes((
        startIndex: 0,
        endIndexExclusive: 10,
      ), 6).toList();
      expect(times[2] - times[1], closeTo(1 / 3, 1e-9));
    });

    test('none over a window with no frames', () {
      expect(
        laneGraphTimes((startIndex: 6, endIndexExclusive: 6), 24),
        isEmpty,
      );
    });
  });

  group('each line is fitted to its own range', () {
    LaneCurve line(List<double> Function(double time) at) =>
        (parts: const [Color(0xFF000000), Color(0xFFFFFFFF)], at: at);

    test('from its lowest to its highest, 12% of that beyond either', () {
      final range = laneGraphRange(
        line((time) => [10 + 50 * time / 8, 0]),
        [0, 8],
        0,
      );
      expect(range.low, closeTo(10 - 50 * 0.12, 1e-9));
      expect(range.high, closeTo(60 + 50 * 0.12, 1e-9));
    });

    test('and what an eased stretch passes beyond its keys', () {
      final range = laneGraphRange(
        line(
          (time) => [10 + 50 * time / 8 + 30 * math.sin(math.pi * time / 8)],
        ),
        [0, 8],
        0,
      );
      // Its middle stands at 65, over both keys (10 and 60): the range
      // reaches that with its spare. ↩️Asked only to pass the keys' own 66,
      // it passed with nothing read between them — the sine's rounding at 8
      // put the keys' range a hair over 66.
      expect(range.high, greaterThanOrEqualTo(65 + (65 - 10) * 0.12));
    });

    test('a line that never moves is given one either way first', () {
      final range = laneGraphRange(line((_) => [5]), [0, 8], 0);
      expect(range.low, closeTo(4 - 2 * 0.12, 1e-9));
      expect(range.high, closeTo(6 + 2 * 0.12, 1e-9));
    });

    test('each number by itself — a point\'s across and its down', () {
      final point = line((time) => [100 + time, -5 * time]);
      expect(laneGraphRange(point, [0, 8], 0).low, greaterThan(90));
      expect(laneGraphRange(point, [0, 8], 1).high, lessThan(10));
    });
  });

  group('across the graph', () {
    const range = (low: 0.0, high: 100.0);

    test('on the timeline higher is up, its padding kept clear', () {
      expect(laneGraphAcross(0, range, 196, Axis.horizontal), 196 - 16);
      expect(laneGraphAcross(100, range, 196, Axis.horizontal), 16);
      expect(laneGraphAcross(50, range, 196, Axis.horizontal), 98);
    });

    test('on the sheet, the timeline turned a quarter clockwise, higher is '
        'further right', () {
      expect(laneGraphAcross(0, range, 196, Axis.vertical), 16);
      expect(laneGraphAcross(100, range, 196, Axis.vertical), 196 - 16);
    });
  });

  test('a graph\'s guests are the pins of every other group, in the order '
      'they were pinned', () {
    const a = LayerId('a');
    const b = LayerId('b');
    final transform = laneGroupKey(a, transformGroupHeaderLane.laneId);
    final blur = laneGroupKey(a, effectLaneId(const EffectId('blur'), 'blurX'));
    final seat = TimelineGraphSeat(
      groupKey: transform,
      graph: const LaneGraph(),
      lanes: const ['position'],
      picked: const [],
      pinned: const ['position'],
    );
    expect(
      laneGraphGuests(seat, {
        blur,
        laneGroupKey(a, 'position'),
        laneGroupKey(b, 'position'),
      }),
      [blur, laneGroupKey(b, 'position')],
    );
  });
}
