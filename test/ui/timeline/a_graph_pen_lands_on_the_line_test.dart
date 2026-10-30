import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart'
    show TimelineLaneSelection;
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/lane_graph.dart' show LaneGraphMode;
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart'
    show LaneGraphLine, LaneGraphReach;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/property_lanes_for_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart'
    show TimelineLaneRangeCallbacks;
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeight;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// **I-3 ④ — where a graph's pen lands: on the line as it is drawn.**
///
/// 🗣️I-3-Q2 (유저 2026-10-21): 「곡선 선 위만 (AE · 보이는 만큼)」 — a pen
/// press, or a Ctrl+click, puts a key only where it lands on a line's
/// stroke (F-262: 「보이는 만큼 존재하도록」), and on the frame whose cell it
/// is in. What it is asked against is what was painted.
void main() {
  Layer layerOf(String id, PropertyTrack<double> rotation) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    transformTrack: TransformTrack.empty().copyWith(rotation: rotation),
  );
  LaneGraphLine lineOf(Layer layer, {LaneGraphReach? reach}) {
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

  final turning = layerOf('a', PropertyTrack<double>().withKey(0, 0));
  final rising = layerOf(
    'b',
    PropertyTrack<double>()
        .withKey(0, 0, outgoing: KeySide.linear)
        .withKey(8, 40, incoming: KeySide.linear),
  );

  /// A cell no whole number of pixels, as a zoom makes it.
  const cell = 13.7;
  late ValueNotifier<TimelineFrameGeometry> geometry;
  late ValueNotifier<int> bucket;
  setUp(() {
    geometry = ValueNotifier(
      const TimelineFrameGeometry(
        viewExtentPx: 48 * cell,
        frameCellExtent: cell,
        frameStartIndex: 0,
        frameEndIndexExclusive: 48,
      ),
    );
    bucket = ValueNotifier(0);
  });
  tearDown(() {
    geometry.dispose();
    bucket.dispose();
  });

  TimelineLaneGraphPainter painterOf({
    List<LaneGraphLine> own = const [],
    List<LaneGraphLine> guests = const [],
  }) => TimelineLaneGraphPainter(
    own: own,
    guests: guests,
    mode: LaneGraphMode.value,
    frameAxis: (
      geometry: geometry,
      windowBucket: bucket,
      axis: Axis.horizontal,
      laneExtent: timelineLayerRowHeight,
      playhead: null,
      frameCount: 0,
    ),
  );

  const size = Size(48 * cell, 196);

  /// Where [painter] draws [line]'s value at [time] — a time of the line's
  /// own, laid [shift] frames on.
  Offset onTheLine(
    TimelineLaneGraphPainter painter,
    LaneGraphLine line,
    double time, {
    int shift = 0,
  }) {
    final key = laneGroupKey(line.layer.id, line.lane.laneId);
    return Offset(
      laneGraphAlong(time + shift, geometry.value),
      laneGraphAcross(
        line.lane.curve!.at(time).single,
        painter.fits[key]!.ranges.single,
        size.height,
        Axis.horizontal,
      ),
    );
  }

  test('a press on the stroke lands on its line, on the frame pressed; '
      'half its width off it, on nothing', () {
    final line = lineOf(rising);
    final painter = painterOf(own: [line]);
    final at = onTheLine(painter, line, 4);
    final across = onTheLine(painter, line, 5) - onTheLine(painter, line, 3);
    final normal = Offset(-across.dy, across.dx) / across.distance;
    expect(
      (onTheLine(painter, line, 4.5) - at).direction,
      closeTo(across.direction, 0.02),
      reason: '⛔전제: a straight line here — but for the pixels its cells '
          'are laid on — so its normal is one',
    );

    expect(painter.curveAt(at, size), (line: line, frame: 4));
    expect(painter.curveAt(at + normal * 0.6, size), (line: line, frame: 4));
    expect(painter.curveAt(at - normal * 0.6, size), (line: line, frame: 4));
    expect(painter.curveAt(at + normal * 1.4, size), isNull);
    expect(painter.curveAt(at - normal * 1.4, size), isNull);
  });

  test('the frame is the one whose cell the press is in — not the key\'s '
      'nearest middle', () {
    final line = lineOf(rising);
    final painter = painterOf(own: [line]);
    final cells = geometry.value;

    final late4 = onTheLine(painter, line, 4.45);
    expect(cells.cellAt(late4.dx), 4, reason: '⛔전제');
    expect(painter.curveAt(late4, size)?.frame, 4);

    final early5 = onTheLine(painter, line, 4.55);
    expect(cells.cellAt(early5.dx), 5, reason: '⛔전제');
    expect(painter.curveAt(early5, size)?.frame, 5);
  });

  test('a guest\'s line takes the pen on its dashes, and nowhere between '
      'them — as it is drawn', () {
    final line = lineOf(turning);
    final painter = painterOf(guests: [line]);
    final start = onTheLine(painter, line, 0);
    Offset along(double by) => start + Offset(by, 0);

    // Dashes six on and four off from the line's start (the mock's, 5판).
    expect(painter.curveAt(along(3), size)?.line, line);
    expect(painter.curveAt(along(5.5), size)?.line, line);
    expect(painter.curveAt(along(8), size), isNull, reason: 'a gap');
    expect(painter.curveAt(along(13), size)?.line, line);
    expect(painter.curveAt(along(18), size), isNull, reason: 'a gap');

    expect(
      painterOf(own: [line]).curveAt(along(8), size)?.line,
      line,
      reason: 'drawn whole as one of its own',
    );
  });

  test('a cut\'s line lands on its own frame, and on none past the frames '
      'it has', () {
    final line = lineOf(rising, reach: (start: 10, end: 20));
    final painter = painterOf(own: [line]);

    expect(
      painter.curveAt(onTheLine(painter, line, 2, shift: 10), size),
      (line: line, frame: 2),
    );
    final last = onTheLine(painter, line, 9, shift: 10);
    expect(
      painter.curveAt(last + const Offset(cell * 0.4, 0), size),
      isNull,
      reason: 'not drawn past its last frame\'s middle, though that cell is '
          'its own',
    );

    // So far out that a pixel past its last frame's middle is the next
    // frame's cell: the cut has none there.
    geometry.value = const TimelineFrameGeometry(
      viewExtentPx: 48 * cell,
      frameCellExtent: 1.5,
      frameStartIndex: 0,
      frameEndIndexExclusive: 48,
    );
    final zoomedOut = painterOf(own: [line]);
    final end = onTheLine(zoomedOut, line, 9, shift: 10);
    expect(zoomedOut.curveAt(end, size), (line: line, frame: 9));
    final past = end + const Offset(0.9, 0);
    expect(geometry.value.cellAt(past.dx), 20, reason: '⛔전제');
    expect(zoomedOut.curveAt(past, size), isNull);
  });

  test('a press past the last frame there is lands on nothing, though the '
      'line\'s end is within reach', () {
    final line = lineOf(turning);
    final painter = painterOf(own: [line]);
    final end = Offset(
      geometry.value.edgeAt(48),
      onTheLine(painter, line, 47).dy,
    );

    expect(
      painter.curveAt(end - const Offset(0.5, 0), size),
      (line: line, frame: 47),
    );
    expect(painter.curveAt(end + const Offset(0.5, 0), size), isNull);
  });

  group('a press where the pen lands', () {
    final selection = ValueNotifier<TimelineLaneSelection?>(null);
    tearDownAll(selection.dispose);

    /// The picture over [rising]'s line, its pen up or down, its lanes'
    /// verbs — the ＋ among them where [plus] — heard into [heard].
    Future<void> pump(
      WidgetTester tester,
      List<String> heard, {
      required bool pen,
      bool plus = true,
    }) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: LaneGraphPicture(
              own: [lineOf(rising)],
              guests: const [],
              frameAxis: (
                geometry: geometry,
                windowBucket: bucket,
                axis: Axis.horizontal,
                laneExtent: timelineLayerRowHeight,
                playhead: null,
                frameCount: 0,
              ),
              edits: null,
              mode: LaneGraphMode.value,
              pen: pen,
              lanes: TimelineLaneRangeCallbacks(
                selection: selection,
                onSelectUpdate: (layer, lane, anchor, head, across) => heard
                    .add('pick ${layer.value} $lane $anchor-$head $across'),
                onTapAt: (_, _, _) => heard.add('stand'),
                onTapClear: () => heard.add('clear'),
                onMoveBegin: () => false,
                onMoveUpdate: (_, {stretch, values, landings}) {},
                onMoveEnd: () {},
                onMoveCancel: () {},
                onCreateKeys: plus ? () => heard.add('＋') : null,
              ),
            ),
          ),
        ),
      ),
    );

    /// Where the picture draws the line at [time], and [off] across it.
    Offset at(double time, {double off = 0}) {
      final line = lineOf(rising);
      return onTheLine(painterOf(own: [line]), line, time) + Offset(0, off);
    }

    testWidgets('with the pen up, the cell pressed is picked and the ＋ '
        'pressed on it — and off the line, nothing', (tester) async {
      final heard = <String>[];
      await pump(tester, heard, pen: true);

      await tester.tapAt(at(4), kind: PointerDeviceKind.touch);
      expect(heard, ['pick b rotation 4-4 0.0', '＋']);

      heard.clear();
      await tester.tapAt(at(4, off: 6), kind: PointerDeviceKind.touch);
      expect(heard, isEmpty);
    });

    testWidgets('with it down, a press on the line puts nothing — Ctrl held '
        'puts the key', (tester) async {
      final heard = <String>[];
      await pump(tester, heard, pen: false);

      await tester.tapAt(at(4), kind: PointerDeviceKind.mouse);
      expect(heard, isEmpty);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tapAt(at(6), kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(heard, ['pick b rotation 6-6 0.0', '＋']);
    });

    testWidgets('where the host takes no ＋, the pen puts nothing and picks '
        'nothing', (tester) async {
      final heard = <String>[];
      await pump(tester, heard, pen: true, plus: false);

      await tester.tapAt(at(4), kind: PointerDeviceKind.touch);
      expect(heard, isEmpty);
    });
  });
}
