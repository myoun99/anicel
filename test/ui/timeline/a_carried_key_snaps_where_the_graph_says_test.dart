import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/key_range_shift.dart' show FrameStretch;
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart'
    show TimelineLaneSelection;
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/lane_graph.dart' show LaneGraphMode;
import 'package:anicel/src/ui/timeline/lane_graph_box_stretch.dart'
    show laneGraphBoxHandleAt;
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart'
    show LaneGraphLine;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/property_lanes_for_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeight;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// **graph-key-drag-snaps — a key carried snaps where the graph says.**
///
/// AE's graph editor's Snap: a key dragged snaps to the times and the
/// values of the keys about it, to the current time and to the comp's
/// start and end, an orange line drawn where it snaps — and Ctrl held once
/// the drag has begun (⌘ on a Mac) turns snapping the other way while it is
/// held.
///
/// The picture over the frames, six pixels a frame: zoomed out so far that
/// a snap's reach is more than half a frame — nearer, a key carried by
/// whole frames is on the frame a snap would put it on already. The key
/// carried is the Rotation's on 8, picked alone.
void main() {
  const draw = LayerId('draw');
  const cell = 6.0;
  const size = Size(60 * cell, 196);

  Layer layerOf(TransformTrack transform) => Layer(
    id: draw,
    name: 'draw',
    frames: const [],
    transformTrack: transform,
  );
  PropertyTrack<double> linear(Map<int, double> keys) {
    var track = PropertyTrack<double>();
    for (final MapEntry(key: frame, :value) in keys.entries) {
      track = track.withKey(
        frame,
        value,
        incoming: KeySide.linear,
        outgoing: KeySide.linear,
      );
    }
    return track;
  }

  List<LaneGraphLine> linesOf(Layer layer) {
    final lanes = propertyLanesForRow(
      layer: layer,
      rows: [layer],
      expandedGroupKeys: {
        laneGroupKey(layer.id, transformGroupHeaderLane.laneId),
      },
      valueSourceAt: (frame) => (layer: layer, frame: frame),
      poseCentre: const CanvasSize(width: 400, height: 300),
    );
    return [
      for (final laneId in ['rotation', 'opacity'])
        (
          layer: layer,
          lane: lanes.firstWhere((lane) => lane.laneId == laneId),
          reach: null,
        ),
    ];
  }

  /// The Rotation 30 on 8, 90 on 30 and 0 on 50; the Opacity 1 on 20,
  /// 0.25 on 44 and 0.75 on 52 — each line fitted to its own range, the
  /// key on 8 marked a third of the way up its line's, and no other key
  /// within a snap's reach of it across the graph.
  final keys = linesOf(
    layerOf(
      TransformTrack.empty().copyWith(
        rotation: linear({8: 30, 30: 90, 50: 0}),
        opacity: linear({20: 1, 44: 0.25, 52: 0.75}),
      ),
    ),
  );

  late ValueNotifier<TimelineFrameGeometry> geometry;
  late ValueNotifier<int> bucket;
  late ValueNotifier<int?> playhead;
  late ValueNotifier<TimelineLaneSelection?> selection;
  ({int frames, FrameStretch? stretch, LaneKeyValues? values})? told;
  setUp(() {
    geometry = ValueNotifier(
      const TimelineFrameGeometry(
        viewExtentPx: 60 * cell,
        frameCellExtent: cell,
        frameStartIndex: 0,
        frameEndIndexExclusive: 60,
      ),
    );
    bucket = ValueNotifier(0);
    playhead = ValueNotifier(null);
    selection = ValueNotifier(
      const TimelineLaneSelection(
        layerId: draw,
        laneId: 'rotation',
        startIndex: 8,
        endIndexExclusive: 9,
      ),
    );
    told = null;
  });
  tearDown(() {
    geometry.dispose();
    bucket.dispose();
    playhead.dispose();
    selection.dispose();
  });

  /// The picture drawing [own], its snap [snap], its frames ending
  /// [frameCount] on — what a carry tells its lanes kept in [told].
  Future<void> pump(
    WidgetTester tester, {
    bool snap = false,
    int frameCount = 0,
    List<LaneGraphLine>? own,
  }) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: size,
          child: LaneGraphPicture(
            own: own ?? keys,
            guests: const [],
            frameAxis: (
              geometry: geometry,
              windowBucket: bucket,
              axis: Axis.horizontal,
              laneExtent: timelineLayerRowHeight,
              playhead: playhead,
              frameCount: frameCount,
            ),
            edits: null,
            mode: LaneGraphMode.value,
            snap: snap,
            lanes: TimelineLaneRangeCallbacks(
              selection: selection,
              onSelectUpdate: (_, _, _, _, _) {},
              onTapAt: (_, _, _) {},
              onTapClear: () {},
              onMoveBegin: () => true,
              onMoveUpdate: (frames, {stretch, values, landings}) =>
                  told = (frames: frames, stretch: stretch, values: values),
              onMoveEnd: () {},
              onMoveCancel: () {},
            ),
          ),
        ),
      ),
    ),
  );

  Finder paint() => find.descendant(
    of: find.byType(LaneGraphPicture),
    matching: find.byType(CustomPaint),
  );

  TimelineLaneGraphPainter painterOf(WidgetTester tester) =>
      tester.widget<CustomPaint>(paint()).painter! as TimelineLaneGraphPainter;

  /// Where [laneId]'s key on [frame] is marked.
  Offset keyAt(WidgetTester tester, String laneId, int frame) =>
      painterOf(tester)
          .keysIn(size)
          .singleWhere(
            (key) => key.line.lane.laneId == laneId && key.frame == frame,
          )
          .at;

  /// A mouse's press on the Rotation's key on 8, carried [by] — still held.
  Future<TestGesture> carry(WidgetTester tester, Offset by) async {
    final gesture = await tester.startGesture(
      keyAt(tester, 'rotation', 8),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(by);
    await tester.pump();
    return gesture;
  }

  /// [carry], let go of — what it told the lanes last.
  Future<({int frames, FrameStretch? stretch, LaneKeyValues? values})>
  carried(WidgetTester tester, Offset by) async {
    final gesture = await carry(tester, by);
    await gesture.up();
    await tester.pump();
    return told!;
  }

  /// A line drawn in the snap's orange — from [from] to [to], where told.
  PaintPattern snapLine({Offset? from, Offset? to}) => paints
    ..something((method, arguments) {
      if (method != #drawLine) {
        return false;
      }
      final [start as Offset, end as Offset, ink as Paint] = arguments;
      bool at(Offset point, Offset? want) =>
          want == null || (point - want).distance < 1e-6;
      return ink.color.toARGB32() == AppColors.snapLine.toARGB32() &&
          at(start, from) &&
          at(end, to);
    });

  /// The middle of frame [frame]'s cell, where a key on it is marked.
  double along(int frame) => laneGraphAlong(frame.toDouble(), geometry.value);

  // The key on 8, carried twelve frames on less seven pixels: the hand
  // seven pixels short of the Opacity's key on 20 — nearer the cell of 19.
  const nearTwenty = Offset(12 * cell - 7, 0);

  testWidgets('with the snap off, a key carried near another key\'s frame '
      'goes where the hand is, by whole frames, and no line is drawn', (
    tester,
  ) async {
    await pump(tester);

    final gesture = await carry(tester, nearTwenty);
    expect(told!.frames, 11);
    expect(tester.renderObject(paint()), isNot(snapLine()));
    await gesture.up();
  });

  testWidgets('with the snap on, it lands on that key\'s frame — a line '
      'across the graph there while it holds, gone once it is let go', (
    tester,
  ) async {
    await pump(tester, snap: true);

    final gesture = await carry(tester, nearTwenty);
    expect(told!.frames, 12);
    expect(
      tester.renderObject(paint()),
      snapLine(
        from: Offset(along(20), 0),
        to: Offset(along(20), size.height),
      ),
    );

    await gesture.up();
    await tester.pump();
    expect(tester.renderObject(paint()), isNot(snapLine()));
  });

  testWidgets('it snaps to the frame the playhead stands on', (tester) async {
    await pump(tester, snap: true);
    // Seven pixels short of the playhead's 26.
    const nearTwentySix = Offset(18 * cell - 7, 0);
    expect(
      (await carried(tester, nearTwentySix)).frames,
      17,
      reason: '⛔전제: no playhead — where the hand is',
    );

    playhead.value = 26;
    expect((await carried(tester, nearTwentySix)).frames, 18);
  });

  testWidgets('it snaps to the start of the frames, and to their end', (
    tester,
  ) async {
    await pump(tester, snap: true);
    expect((await carried(tester, const Offset(-8 * cell + 7, 0))).frames, -8);
    // Seven pixels short of 56.
    const nearTheEnd = Offset(48 * cell - 7, 0);
    expect(
      (await carried(tester, nearTheEnd)).frames,
      47,
      reason: '⛔전제: frames with no end — where the hand is',
    );

    await pump(tester, snap: true, frameCount: 56);
    expect((await carried(tester, nearTheEnd)).frames, 48);
  });

  testWidgets('of two within its reach, the nearest', (tester) async {
    await pump(tester, snap: true);
    playhead.value = 22;

    // The hand on 21.2: 7.2 pixels past the Opacity's key on 20, the first
    // it is asked of, and 4.8 short of the playhead.
    expect((await carried(tester, const Offset(13.2 * cell, 0))).frames, 14);
  });

  testWidgets('across the graph it snaps to where another key is marked: its '
      'value raised as far as puts its mark level with that key\'s, a line '
      'along the graph there', (tester) async {
    await pump(tester, snap: true);
    final from = keyAt(tester, 'rotation', 8).dy;
    final to = keyAt(tester, 'opacity', 52).dy;
    expect(to - from, lessThan(-20), reason: '⛔전제: well above it');
    final range = painterOf(
      tester,
    ).fits[laneGroupKey(draw, 'rotation')]!.ranges.single;
    double markOf(LaneKeyValues? values) => laneGraphAcross(
      double.parse(values!.inputs['rotation']![8]!),
      range,
      size.height,
      Axis.horizontal,
    );
    // Four pixels short of it.
    final up = Offset(0, to - from + 4);

    final gesture = await carry(tester, up);
    expect(told!.frames, 0);
    expect(markOf(told!.values), closeTo(to, 1e-6));
    expect(
      tester.renderObject(paint()),
      snapLine(from: Offset(0, to), to: Offset(size.width, to)),
    );
    await gesture.up();
    await tester.pump();

    await pump(tester);
    expect(
      markOf((await carried(tester, up)).values),
      closeTo(to + 4, 1e-6),
      reason: 'the snap off: where the hand is',
    );
  });

  testWidgets('with Shift held, the way it keeps the hand off is not '
      'snapped: carried up beside the playhead, the key stays on its frame', (
    tester,
  ) async {
    await pump(tester, snap: true);
    playhead.value = 9;
    const up = Offset(2, -40);
    expect(
      (await carried(tester, up)).frames,
      1,
      reason: '⛔전제: the playhead a frame on is within its reach',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect((await carried(tester, up)).frames, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  testWidgets('…and carried along beside another key\'s mark, the key keeps '
      'its value', (tester) async {
    // The Opacity 0.53 on 36: marked a few pixels above the key on 8.
    await pump(
      tester,
      snap: true,
      own: linesOf(
        layerOf(
          TransformTrack.empty().copyWith(
            rotation: linear({8: 30, 30: 90, 50: 0}),
            opacity: linear({20: 1, 36: 0.53, 44: 0.25}),
          ),
        ),
      ),
    );
    final beside =
        keyAt(tester, 'opacity', 36).dy - keyAt(tester, 'rotation', 8).dy;
    expect(beside.abs(), inExclusiveRange(1, 6), reason: '⛔전제');
    const alongAndUp = Offset(5 * cell, -1);
    expect(
      (await carried(tester, alongAndUp)).values,
      isNotNull,
      reason: '⛔전제: free, it snaps up to the Opacity\'s mark',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final kept = await carried(tester, alongAndUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect((kept.frames, kept.values), (5, null));
  });

  testWidgets('Ctrl held turns the snap the other way: off where it is on, '
      'on where it is off', (tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await pump(tester, snap: true);
    expect((await carried(tester, nearTwenty)).frames, 11);

    await pump(tester);
    expect((await carried(tester, nearTwenty)).frames, 12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('Ctrl pressed once the carry has begun turns it from the next '
      'move on, for as long as it is held — its line with it', (tester) async {
    await pump(tester, snap: true);
    final gesture = await carry(tester, nearTwenty);
    expect(told!.frames, 12, reason: '⛔전제');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await gesture.moveBy(const Offset(0.5, 0));
    await tester.pump();
    expect(told!.frames, 11);
    expect(tester.renderObject(paint()), isNot(snapLine()));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await gesture.moveBy(const Offset(-0.5, 0));
    await tester.pump();
    expect(told!.frames, 12);
    expect(tester.renderObject(paint()), snapLine());
    await gesture.up();
  });

  testWidgets('a handle of the box round the keys picked stretches them '
      'unsnapped — Ctrl says something else there', (tester) async {
    selection.value = const TimelineLaneSelection(
      layerId: draw,
      laneId: 'rotation',
      startIndex: 8,
      endIndexExclusive: 31,
    );
    await pump(tester, snap: true);
    final round = painterOf(tester).pickedIn(size).box!;
    final gesture = await tester.startGesture(
      laneGraphBoxHandleAt((along: 1, across: 0), round, Axis.horizontal),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    // The box's end on 30 pulled to five pixels past the Opacity's key on
    // 20.
    await gesture.moveBy(const Offset(-10 * cell + 5, 0));
    await tester.pump();

    final pulled = laneGraphTimeAt(along(30) - 10 * cell + 5, geometry.value);
    expect(pulled, closeTo(20 + 5 / cell, 1e-9), reason: '⛔전제');
    final stretch = told!.stretch!;
    expect(stretch.anchor, 8);
    expect(stretch.factor, closeTo((pulled - 8) / (30 - 8), 1e-9));
    expect(tester.renderObject(paint()), isNot(snapLine()));
    await gesture.up();
  });
}
