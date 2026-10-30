import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/lane_graph.dart' show LaneGraphMode;
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart'
    show LaneGraphLine;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/property_lanes_for_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeight;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// **I-89 ① — a cut's lane is drawn on its track over its own frames.**
///
/// The storyboard's projection rows draw each cut's keys over the cut's own
/// frames, its frame 0 where they begin on the track, and nothing past them
/// (유저 2026-10-08: 「컷 클램핑만 되도록」); a header graph draws a cut's
/// lane there the same way ([LaneGraphLine.reach]) — and a key past them
/// still bends what is drawn, as it moves the cut's camera.
void main() {
  /// The cut's own frames: 24 of them, from the track's frame 24.
  const reach = (start: 24, end: 48);
  const cell = 10.0;
  const size = Size(76 * cell, 196);
  late ValueNotifier<TimelineFrameGeometry> geometry;
  setUp(() {
    // From frame 20: a window the cut's own frames miss, laid on the track
    // as they are counted.
    geometry = ValueNotifier(
      const TimelineFrameGeometry(
        viewExtentPx: 76 * cell,
        frameCellExtent: cell,
        frameStartIndex: 20,
        frameEndIndexExclusive: 96,
      ),
    );
  });
  tearDown(() => geometry.dispose());

  LaneGraphLine lineOf(PropertyTrack<double> rotation) {
    final layer = Layer(
      id: const LayerId('cam'),
      name: 'Camera',
      frames: const [],
      transformTrack: TransformTrack.empty().copyWith(rotation: rotation),
    );
    final lanes = propertyLanesForRow(
      layer: layer,
      rows: [layer],
      expandedGroupKeys: {
        laneGroupKey(layer.id, transformGroupHeaderLane.laneId),
      },
      valueSourceAt: (frame) => (layer: layer, frame: frame),
      poseCentre: const CanvasSize(width: 400, height: 300),
      hasPlugin: null,
    );
    return (
      layer: layer,
      lane: lanes.firstWhere((lane) => lane.laneId == 'rotation'),
      reach: reach,
    );
  }

  TimelineLaneGraphPainter painterOf(
    LaneGraphLine line, {
    LaneGraphMode mode = LaneGraphMode.value,
  }) => TimelineLaneGraphPainter(
    own: [line],
    guests: const [],
    mode: mode,
    frameAxis: (
      geometry: geometry,
      windowBucket: null,
      axis: Axis.horizontal,
      laneExtent: timelineLayerRowHeight,
      playhead: null,
      frameCount: 0,
    ),
  );

  LaneGraphFit fitOf(TimelineLaneGraphPainter painter, LaneGraphLine line) =>
      painter.fits[laneGroupKey(line.layer.id, 'rotation')]!;

  /// The middle of the track's [frame], where a key on it stands.
  double middle(int frame) =>
      (geometry.value.edgeAt(frame) + geometry.value.edgeAt(frame + 1)) / 2;

  /// What [painter] draws in [style], painted now.
  List<Path> drawn(TimelineLaneGraphPainter painter, PaintingStyle style) {
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, size);
    return [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawPath &&
            (call.invocation.positionalArguments[1] as Paint).style == style)
          call.invocation.positionalArguments[0] as Path,
    ];
  }

  /// Rotation: 0 eases to 30 on 8, which eases on toward 1000 on 60 — past
  /// the cut's own frames.
  final past = PropertyTrack<double>()
      .withKey(0, 0, incoming: const EaseSide(), outgoing: const EaseSide())
      .withKey(8, 30, incoming: const EaseSide(), outgoing: const EaseSide())
      .withKey(
        60,
        1000,
        incoming: const EaseSide(),
        outgoing: const EaseSide(),
      );

  test('it is drawn from its frame 0, where its own frames begin on the '
      'track, to the last of them, and its keys there are marked', () {
    final painter = painterOf(lineOf(past));
    final line = drawn(painter, PaintingStyle.stroke).single.getBounds();
    expect(line.left, closeTo(middle(24), 1e-3));
    expect(line.right, closeTo(middle(47), 1e-3));
    expect(
      [
        for (final mark in drawn(painter, PaintingStyle.fill))
          mark.getBounds().center.dx,
      ],
      [closeTo(middle(24), 1e-3), closeTo(middle(32), 1e-3)],
      reason: 'its keys on its own 0 and 8, and not the one on 60',
    );
  });

  test('it is fitted to what is drawn of it: on to the last of its own '
      'frames, where a key past them bends it, and no further', () {
    final line = lineOf(past);
    final fit = fitOf(painterOf(line), line);
    expect(fit.keyed, [0, 8, 60], reason: 'its keys, every one');
    final (:low, :high) = fit.ranges.single;
    expect(low, lessThan(0));
    expect(
      high,
      greaterThan(line.lane.curve!.at(23).single),
      reason: 'the last of its own frames',
    );
    expect(high, lessThan(1000), reason: 'and not the key past them');
  });

  test('a speed graph draws it moving by the last of its own frames as the '
      'key past them moves it — not still', () {
    final line = lineOf(past);
    final painter = painterOf(line, mode: LaneGraphMode.speed);
    final metric = drawn(
      painter,
      PaintingStyle.stroke,
    ).single.computeMetrics().single;
    final end = metric.getTangentForOffset(metric.length)!.position;
    final speed = laneGraphSpeedAt(line.lane.curve!, 23, from: 8, to: 60);
    expect(speed, greaterThan(0), reason: '⛔전제');
    expect(
      end,
      offsetMoreOrLessEquals(
        Offset(
          middle(47),
          laneGraphAcross(
            speed,
            fitOf(painter, line).ranges.single,
            size.height,
            Axis.horizontal,
          ),
        ),
        epsilon: 1e-3,
      ),
    );
  });

  test('it takes the handles of its keys there, laid where they are drawn, '
      'where they stand on its own frames — none of a key past them', () {
    /// 8 leaves toward 40, past the cut's own frames, at the [influence]
    /// given; 40 arrives at nine tenths' — its handle stands on the cut's
    /// own frames, its key past them.
    PropertyTrack<double> leaving8At(double influence) =>
        PropertyTrack<double>()
            .withKey(0, 0, outgoing: const EaseSide())
            .withKey(
              8,
              30,
              incoming: const EaseSide(),
              outgoing: EaseSide(influence: influence),
            )
            .withKey(40, 100, incoming: const EaseSide(influence: 0.9));
    List<(int, bool, ({int from, int to}))> handlesOf(
      List<LaneGraphHandle> handles,
    ) => [
      for (final handle in handles)
        (handle.frame, handle.leaving, handle.frames),
    ];

    final rotation = leaving8At(0.25);
    final handles = painterOf(lineOf(rotation)).handlesIn(size);
    expect(handlesOf(handles), [
      (0, true, (from: 24, to: 32)),
      (8, false, (from: 24, to: 32)),
      (8, true, (from: 32, to: 64)),
    ]);
    for (final handle in handles) {
      final edit = laneGraphPull(
        handle,
        handle.at,
        frames: geometry.value,
        axis: Axis.horizontal,
      );
      final key = rotation.keyAt(handle.frame)!;
      final side = (handle.leaving ? key.outgoing : key.incoming) as EaseSide;
      expect(
        (handle.leaving ? edit.outgoing : edit.incoming)!.influence,
        closeTo(side.influence, 1e-9),
        reason: 'pulled where it is drawn, it reads back its own side',
      );
    }

    expect(
      handlesOf(painterOf(lineOf(leaving8At(0.75))).handlesIn(size)),
      [(0, true, (from: 24, to: 32)), (8, false, (from: 24, to: 32))],
      reason: '8\'s leaving handle stands past the cut\'s own frames',
    );
  });
}
