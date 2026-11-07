import 'dart:ui' show PictureRecorder;

import 'package:flutter/foundation.dart' show ValueListenable;
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
  const size = Size(48 * 24, 196);

  /// A graph of one Rotation keyed on 0 and 40, plotted as [mode] and
  /// fitted clear of tools reaching [toolsReach] in, painted again by
  /// [paints] — each read of its line counted.
  ({TimelineLaneGraphPainter painter, int Function() paints}) graph(
    LaneGraphMode mode, {
    ValueListenable<double>? toolsReach,
  }) {
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
        playhead: null,
        frameCount: 0,
      ),
      toolsReach: toolsReach,
    );
    int paints() {
      reads = 0;
      final recorder = PictureRecorder();
      painter.paint(Canvas(recorder), size);
      recorder.endRecording().dispose();
      return reads;
    }

    return (painter: painter, paints: paints);
  }

  for (final mode in LaneGraphMode.values) {
    test('a ${mode.name} graph painted again in the same window reads '
        'nothing', () {
      final (painter: _, :paints) = graph(mode);
      final first = paints();
      final again = paints();
      // Its lines, keys and handles are read once for its window: a mouse
      // asks for each on every move it makes over the picture (I-3 - the
      // key, the handle and the pen's line).
      expect(again, 0);
      expect(first, greaterThan(again), reason: 'the first read the fit');
    });
  }

  // graph-box-top-handle-under-the-toolbar-Q1: the tools say how far they
  // reach where they are laid, after the picture is.
  test('tools laid to reach further in paint it again, its keys read anew '
      'clear of them', () {
    final reach = ValueNotifier<double>(0);
    addTearDown(reach.dispose);
    final (:painter, :paints) = graph(
      LaneGraphMode.value,
      toolsReach: reach,
    );
    var repaints = 0;
    void repainted() => repaints += 1;
    painter.addListener(repainted);
    addTearDown(() => painter.removeListener(repainted));
    paints();
    final range = painter.fits.values.single.ranges.single;
    double fitted(double toolsReach) => laneGraphAcross(
      40,
      range,
      size.height,
      Axis.horizontal,
      toolsReach: toolsReach,
    );
    double top() =>
        painter.keysIn(size).singleWhere((key) => key.frame == 40).at.dy;
    expect(top(), fitted(0), reason: '⛔전제: no tools over it');
    expect(fitted(32), greaterThan(fitted(0)), reason: '⛔전제: lower');

    reach.value = 32;

    expect(repaints, 1);
    expect(paints(), greaterThan(0), reason: 'read anew');
    expect(top(), fitted(32));
  });
}
