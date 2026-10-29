import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/lane_graph.dart' show LaneGraphMode;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeight;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';

/// **I-89 ③ — a header graph reads what its lines are fitted to once.**
///
/// A scroll paints a graph again with the painter it has. 🔬When every
/// paint read each line's range again, 200 keys cost 10.7ms a paint to the
/// values and 19.8ms to the speeds (two lanes, the test VM) — the range is
/// the whole line's, and only the window moves.
void main() {
  for (final mode in LaneGraphMode.values) {
    test('a ${mode.name} graph painted again in the same window reads '
        'nothing', () {
      var reads = 0;
      final lane = PropertyLaneRow(
        laneId: 'rotation',
        label: 'Rotation',
        keyMarks: const {0: KeyMark.linear, 40: KeyMark.linear},
        curve: (
          parts: const [Color(0xFF000000)],
          at: (time) {
            reads += 1;
            return [time];
          },
          sides: const {},
          way: null,
        ),
      );
      final geometry = ValueNotifier(
        const TimelineFrameGeometry(
          viewExtentPx: 240.0,
          frameCellExtent: 24,
          frameStartIndex: 0,
          frameEndIndexExclusive: 48,
        ),
      );
      addTearDown(geometry.dispose);
      final bucket = ValueNotifier<int>(0);
      addTearDown(bucket.dispose);
      final painter = TimelineLaneGraphPainter(
        own: [
          (
            layer: Layer(id: const LayerId('a'), name: 'A', frames: const []),
            lane: lane,
            reach: null,
          ),
        ],
        guests: const [],
        mode: mode,
        frameAxis: (
          geometry: geometry,
          windowBucket: bucket,
          axis: Axis.horizontal,
          laneExtent: timelineLayerRowHeight,
        ),
      );
      int readsOfAPaint() {
        reads = 0;
        final recorder = PictureRecorder();
        painter.paint(Canvas(recorder), const Size(48 * 24, 196));
        recorder.endRecording().dispose();
        return reads;
      }

      final first = readsOfAPaint();
      final again = readsOfAPaint();
      // Its lines, keys and handles are read once for its window: a mouse
      // asks for each on every move it makes over the picture (I-3 - the
      // key, the handle and the pen's line).
      expect(again, 0);
      expect(first, greaterThan(again), reason: 'the first read the fit');
    });
  }
}
