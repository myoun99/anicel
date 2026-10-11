import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/lane_graph.dart' show LaneGraphMode;
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart'
    show LaneGraphLine;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/property_lanes_for_row.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// **I-89 ③ — a header graph draws its handles (the mock's 5판).**
///
/// A value graph puts a handle on each side of a key that eases toward the
/// key beside it, on a line of one number (I-89-Q-a), where that side bends
/// their segment; a press takes one on what is drawn of it (F-262); and a
/// handle pulled reads its side back off the point the picture draws.
void main() {
  /// Rotation: 0 leaves at Easy Ease (and arrives at one from nowhere), 6
  /// arrives at a half-way ease and leaves straight, 12 arrives smooth and
  /// holds, 18 arrives at a quick ease after the hold and leaves at one
  /// toward nowhere. Position eases both ways.
  final track = TransformTrack.empty().copyWith(
    rotation: PropertyTrack<double>()
        .withKey(0, 0, incoming: const EaseSide(), outgoing: const EaseSide())
        .withKey(6, 30, incoming: const EaseSide(influence: 0.5, speed: 1))
        .withKey(12, 10, incoming: KeySide.auto, outgoing: KeyExit.hold)
        .withKey(
          18,
          40,
          incoming: const EaseSide(influence: 0.25, speed: 2),
          outgoing: const EaseSide(),
        ),
    position: PropertyTrack<CanvasPoint>()
        .withKey(0, CanvasPoint(x: 0, y: 0), outgoing: const EaseSide())
        .withKey(8, CanvasPoint(x: 40, y: 20), incoming: const EaseSide()),
  );
  final layer = Layer(
    id: const LayerId('a'),
    name: 'A',
    frames: const [],
    transformTrack: track,
  );
  LaneGraphLine lineOf(String laneId, {Layer? on}) {
    final row = on ?? layer;
    final lanes = propertyLanesForRow(
      layer: row,
      rows: [row],
      expandedGroupKeys: {
        laneGroupKey(row.id, transformGroupHeaderLane.laneId),
      },
      valueSourceAt: (frame) => (layer: row, frame: frame),
      poseCentre: const CanvasSize(width: 400, height: 300),
    );
    return (
      layer: row,
      lane: lanes.firstWhere((lane) => lane.laneId == laneId),
    );
  }

  /// A cell no whole number of pixels, so the middles the keys stand on are
  /// not a cell apart everywhere.
  const cell = 13.7;
  late ValueNotifier<TimelineFrameGeometry> geometry;
  late ValueNotifier<int> cursor;
  late ValueNotifier<int> bucket;
  setUp(() {
    geometry = ValueNotifier(
      const TimelineFrameGeometry(
        frameCellExtent: cell,
        frameStartIndex: 0,
        frameEndIndexExclusive: 48,
      ),
    );
    cursor = ValueNotifier(0);
    bucket = ValueNotifier(0);
  });
  tearDown(() {
    geometry.dispose();
    cursor.dispose();
    bucket.dispose();
  });

  TimelineLaneGraphPainter painterOf(
    List<LaneGraphLine> own, {
    List<LaneGraphLine> guests = const [],
    LaneGraphMode mode = LaneGraphMode.value,
    Axis axis = Axis.horizontal,
    Map<String, LaneGraphFit> held = const {},
  }) => TimelineLaneGraphPainter(
    own: own,
    guests: guests,
    mode: mode,
    held: held,
    grid: (
      hooks: TimelineGridHooks(
        activeLayerId: null,
        frameCursor: cursor,
        playbackFrameCount: 48,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
        onSelectLayer: (_) {},
        onSelectFrame: (_) {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
      ),
      metrics: TimelineGridMetrics.defaults,
      geometry: geometry,
      windowBucket: bucket,
      viewportMainExtent: 48 * cell,
      frameAxisController: null,
      rangeGesture: null,
      axis: axis,
      keyPrefix: 'timeline',
    ),
  );

  Size sizeFor(Axis axis) => axis == Axis.horizontal
      ? const Size(48 * cell, 196)
      : const Size(196, 48 * cell);

  /// [at] read back along and across the graph.
  ({double time, double across}) readOf(Offset at, Axis axis) => (
    time: laneGraphTimeAt(
      axis == Axis.horizontal ? at.dx : at.dy,
      geometry.value,
    ),
    across: axis == Axis.horizontal ? at.dy : at.dx,
  );

  EaseSide sideOf(LaneGraphHandle handle) {
    final key = track.rotation.keyAt(handle.frame)!;
    return (handle.leaving ? key.outgoing : key.incoming) as EaseSide;
  }

  test('a value graph draws a handle on each side of a key that eases toward '
      'the key beside it — a hold\'s arriving ease too — and on no other '
      'side', () {
    final handles = painterOf([
      lineOf('rotation'),
    ]).handlesIn(sizeFor(Axis.horizontal));

    expect(
      [for (final handle in handles) (handle.frame, handle.leaving)],
      [(0, true), (6, false), (18, false)],
      reason: 'no handle toward nowhere, none on a straight, smooth or held '
          'side',
    );
  });

  test('a handle stands where its side bends the segment, its stem from the '
      'key\'s mark', () {
    final handles = painterOf([
      lineOf('rotation'),
    ]).handlesIn(sizeFor(Axis.horizontal));
    final (leaving, arriving, afterTheHold) = (
      handles[0],
      handles[1],
      handles[2],
    );

    final easy = readOf(leaving.at, Axis.horizontal);
    expect(easy.time, closeTo(2, 1e-9), reason: 'a third of 0 to 6');
    expect(easy.across, closeTo(leaving.across.from, 1e-9), reason: 'still');
    expect(readOf(leaving.key, Axis.horizontal).time, closeTo(0, 1e-9));
    expect(leaving.key.dy, closeTo(leaving.across.from, 1e-9));

    final half = readOf(arriving.at, Axis.horizontal);
    expect(half.time, closeTo(3, 1e-9), reason: 'half of 0 to 6, from 6');
    expect(
      half.across,
      closeTo(
        arriving.across.to - 0.5 * (arriving.across.to - arriving.across.from),
        1e-9,
      ),
      reason: 'arriving at the average speed',
    );
    expect(readOf(arriving.key, Axis.horizontal).time, closeTo(6, 1e-9));

    final quick = readOf(afterTheHold.at, Axis.horizontal);
    expect(quick.time, closeTo(18 - 0.25 * 6, 1e-9));
    expect(
      quick.across,
      closeTo(
        afterTheHold.across.to -
            0.25 * 2 * (afterTheHold.across.to - afterTheHold.across.from),
        1e-9,
      ),
      reason: 'at twice the average',
    );
  });

  List<(int, bool)> drawnSides() => [
    for (final handle in painterOf([
      lineOf('rotation'),
    ]).handlesIn(sizeFor(Axis.horizontal)))
      (handle.frame, handle.leaving),
  ];

  test('a segment the window shows some of keeps its handles, though a key '
      'of it stands outside the window', () {
    // Eight frames to a window's step at this zoom, two cells overscan.
    bucket.value = 2;
    expect(
      painterOf([lineOf('rotation')]).visibleFrameWindow().startIndex,
      14,
      reason: '⛔전제',
    );
    expect(
      drawnSides(),
      [(18, false)],
      reason: '12 to 18 shows; 0 to 6 and 6 to 12 do not',
    );

    bucket.value = 0;
    geometry.value = const TimelineFrameGeometry(
      frameCellExtent: cell,
      frameStartIndex: 0,
      frameEndIndexExclusive: 15,
    );
    expect(
      drawnSides(),
      [(0, true), (6, false), (18, false)],
      reason: 'the window ends at 15, inside 12 to 18',
    );
  });

  test('a zoom, a scroll or a taller graph reads its handles again — each '
      'of them alone', () {
    final size = sizeFor(Axis.horizontal);
    final painter = painterOf([lineOf('rotation')]);
    List<Offset> drawn(TimelineLaneGraphPainter painter, Size size) => [
      for (final handle in painter.handlesIn(size)) handle.at,
    ];
    const all = (startIndex: 0, endIndexExclusive: 48);
    final before = drawn(painter, size);
    expect(painter.visibleFrameWindow(), all, reason: '⛔전제');

    // A zoom the window does not see: the cut's 48 frames bound it at
    // either zoom.
    geometry.value = const TimelineFrameGeometry(
      frameCellExtent: 14,
      frameStartIndex: 0,
      frameEndIndexExclusive: 48,
    );
    expect(painter.visibleFrameWindow(), all, reason: '⛔전제');
    expect(drawn(painterOf([lineOf('rotation')]), size), isNot(before));
    expect(drawn(painter, size), drawn(painterOf([lineOf('rotation')]), size));

    final taller = Size(size.width, size.height + 40);
    expect(
      drawn(painter, taller),
      drawn(painterOf([lineOf('rotation')]), taller),
    );

    expect(drawn(painter, size), isNotEmpty, reason: '⛔전제');
    // Seven frames to a step at this zoom: the window from 33 on.
    bucket.value = 5;
    expect(painter.handlesIn(size), isEmpty, reason: 'past every segment');
  });

  test('no handle on a line of two numbers, nor in a speed graph', () {
    expect(
      painterOf([lineOf('position')]).handlesIn(sizeFor(Axis.horizontal)),
      isEmpty,
      reason: 'I-89-Q-a: a point\'s two numbers share one side',
    );
    expect(
      painterOf([
        lineOf('rotation'),
      ], mode: LaneGraphMode.speed).handlesIn(sizeFor(Axis.horizontal)),
      isEmpty,
    );
  });

  test('a press takes a handle on what is drawn of it and nowhere round it — '
      'and where two stand as one, the one drawn last', () {
    final size = sizeFor(Axis.horizontal);
    final own = lineOf('rotation');
    final guest = lineOf(
      'rotation',
      on: layer.copyWith(id: const LayerId('b')),
    );
    final painter = painterOf([own], guests: [guest]);
    final handle = painter.handlesIn(size).first;
    // The mock's circle, 4.5 round, and half its 1.6 ink outside it.
    const reach = 4.5 + 0.8;

    expect(painter.handleAt(handle.at, size)?.line, guest);
    expect(
      painter.handleAt(handle.at + const Offset(0, reach - 0.05), size),
      isNotNull,
    );
    expect(
      painter.handleAt(handle.at + const Offset(0, reach + 0.05), size),
      isNull,
      reason: 'F-262: 「보이는 만큼 존재하도록」',
    );
    expect(
      painterOf([own]).handleAt(handle.at, size)?.line,
      own,
      reason: '⛔전제: the own line takes it alone',
    );
  });

  test('handles are drawn over the marks as the mock draws them — a stem '
      'from the key, a circle of the surface ringed in the accent — inside '
      'the graph\'s own box', () {
    final size = sizeFor(Axis.horizontal);
    final painter = painterOf([lineOf('rotation')]);
    final handle = painter.handlesIn(size).first;

    expect(
      (Canvas canvas) => painter.paint(canvas, size),
      paints
        ..clipRect(rect: Offset.zero & size)
        ..line(
          p1: handle.key,
          p2: handle.at,
          strokeWidth: 1,
          color: AppColors.textDim,
        )
        ..circle(
          x: handle.at.dx,
          y: handle.at.dy,
          radius: 4.5,
          color: AppColors.surface,
        )
        ..circle(
          x: handle.at.dx,
          y: handle.at.dy,
          radius: 4.5,
          // 1.6, as a paint holds it.
          strokeWidth: (Paint()..strokeWidth = 1.6).strokeWidth,
          style: PaintingStyle.stroke,
          color: AppColors.accent,
        ),
    );
  });

  for (final axis in Axis.values) {
    test('pulled to where it stands, a handle writes what it is — on the '
        '${axis.name} graph, at a zoom whose cells are no whole pixels', () {
      final size = sizeFor(axis);
      final handles = painterOf([
        lineOf('rotation'),
      ], axis: axis).handlesIn(size);
      expect(handles, hasLength(3), reason: '⛔전제');
      for (final handle in handles) {
        final edit = laneGraphPull(
          handle,
          handle.at,
          frames: geometry.value,
          axis: axis,
        );
        final written = handle.leaving ? edit.outgoing : edit.incoming;
        final side = sideOf(handle);
        final reason = '${handle.frame} ${handle.leaving ? 'out' : 'in'}';
        expect(
          written!.influence,
          closeTo(side.influence, 1e-9),
          reason: reason,
        );
        expect(written.speed, closeTo(side.speed, 1e-9), reason: reason);
        expect(
          handle.leaving ? edit.incoming : edit.outgoing,
          isNull,
          reason: 'the other side is not this handle\'s',
        );
        expect(written.side, isNull, reason: 'it makes no kind');
      }
    });
  }

  test('the time read off a point of the picture is the time the picture '
      'draws there — though its cells, no whole pixels, are each a pixel '
      'off their zoom\'s width here and there', () {
    final frames = geometry.value;
    final end = laneGraphAlong(48, frames);
    final off = [
      for (var along = -10.0; along < end; along += 0.05)
        if ((laneGraphAlong(laneGraphTimeAt(along, frames), frames) - along)
                .abs() >
            1e-9)
          along,
    ];
    expect(off, isEmpty);
  });

  test('a pull reads the time along and the height across off the picture '
      '— held to the segment\'s own reach', () {
    final size = sizeFor(Axis.horizontal);
    final handle = painterOf([lineOf('rotation')]).handlesIn(size).first;
    final rise = handle.across.to - handle.across.from;
    final edit = laneGraphPull(
      handle,
      Offset(
        laneGraphAlong(3, geometry.value),
        handle.across.from + 0.25 * rise,
      ),
      frames: geometry.value,
      axis: Axis.horizontal,
    );
    expect(edit.outgoing!.influence, closeTo(0.5, 1e-9));
    expect(edit.outgoing!.speed, closeTo(0.5, 1e-9));

    final past = laneGraphPull(
      handle,
      Offset(laneGraphAlong(9, geometry.value), handle.across.from),
      frames: geometry.value,
      axis: Axis.horizontal,
    );
    expect(past.outgoing!.influence, 1, reason: 'never past the next key');
    final back = laneGraphPull(
      handle,
      Offset(laneGraphAlong(-2, geometry.value), handle.across.from),
      frames: geometry.value,
      axis: Axis.horizontal,
    );
    expect(back.outgoing!.influence, EaseSide.leastInfluence);
  });

  test('a segment between two keys of one value has no height to read a '
      'speed off: its pull takes the influence alone', () {
    final level = layer.copyWith(
      transformTrack: TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>()
            .withKey(
              0,
              10,
              outgoing: const EaseSide(influence: 0.4, speed: 2),
            )
            .withKey(6, 10),
      ),
    );
    final size = sizeFor(Axis.horizontal);
    final handle = painterOf([
      lineOf('rotation', on: level),
    ]).handlesIn(size).single;
    final edit = laneGraphPull(
      handle,
      handle.at + const Offset(0, -40),
      frames: geometry.value,
      axis: Axis.horizontal,
    );
    expect(edit.outgoing!.influence, closeTo(0.4, 1e-9));
    expect(edit.outgoing!.speed, isNull);
  });

  test('a leaving handle\'s pull is a write a held side takes, and leaves '
      'held — the range it covers may hold one', () {
    final size = sizeFor(Axis.horizontal);
    final handle = painterOf([lineOf('rotation')]).handlesIn(size).first;
    final edit = laneGraphPull(
      handle,
      handle.at,
      frames: geometry.value,
      axis: Axis.horizontal,
    );
    expect(
      edit.applyTo(incoming: KeySide.linear, outgoing: KeyExit.hold),
      (incoming: KeySide.linear, outgoing: KeyExit.hold),
    );
  });

  test('held, a picture draws its lines to what they were fitted to when the '
      'handle was taken — refitted to the bend, a line would slide from '
      'under the hand', () {
    LaneGraphRange rangeOf(TimelineLaneGraphPainter painter) =>
        painter.fits.values.single.ranges.single;
    final before = painterOf([lineOf('rotation')]);
    final bent = layer.copyWith(
      transformTrack: track.copyWith(
        rotation: track.rotation.withKey(
          0,
          0,
          outgoing: const EaseSide(influence: 1, speed: 3),
        ),
      ),
    );
    expect(
      rangeOf(painterOf([lineOf('rotation', on: bent)])).high,
      greaterThan(rangeOf(before).high),
      reason: '⛔전제: the bend reaches past the range the line had',
    );
    expect(
      rangeOf(
        painterOf([lineOf('rotation', on: bent)], held: before.fits),
      ),
      rangeOf(before),
    );
  });
}
