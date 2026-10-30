import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/theme/lane_curve_palette.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
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
      hasPlugin: null,
    );
    return (
      layer: row,
      lane: lanes.firstWhere((lane) => lane.laneId == laneId),
      reach: null,
    );
  }

  /// A cell no whole number of pixels, so the middles the keys stand on are
  /// not a cell apart everywhere.
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
    frameAxis: (
      geometry: geometry,
      windowBucket: bucket,
      axis: axis,
      laneExtent: timelineLayerRowHeight,
      playhead: null,
      frameCount: 0,
    ),
  );

  Size sizeFor(Axis axis) => sizeAlong(axis, along: 48 * cell, across: 196);

  /// [at] read back along and across the graph.
  ({double time, double across}) readOf(Offset at, Axis axis) => (
    time: laneGraphTimeAt(partAlong(axis, at), geometry.value),
    across: partAcross(axis, at),
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
    expect(arriving.key.dy, closeTo(arriving.across.to, 1e-9));

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
      viewExtentPx: 48 * cell,
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
      viewExtentPx: 48 * cell,
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

  test('no handle on a line of two numbers in a value graph', () {
    expect(
      painterOf([lineOf('position')]).handlesIn(sizeFor(Axis.horizontal)),
      isEmpty,
      reason: 'I-89-Q-a: a point\'s two numbers share one side',
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

  /// **I-89-Q5 B — a speed graph's handles (유저 2026-10-12: 「속도 보기에도
  /// 핸들(AE 식)」):** AE's speed graph — a side's handle as far along as it
  /// reaches and as high as the speed it moves at by its key, on a line of
  /// any numbers, a point's along its path.
  group('a speed graph', () {
    final size = sizeFor(Axis.horizontal);
    TimelineLaneGraphPainter speedOf(
      LaneGraphLine line, {
      Axis axis = Axis.horizontal,
    }) => painterOf([line], mode: LaneGraphMode.speed, axis: axis);

    /// Where [speed] stands across [painter]'s one line, on the timeline.
    double acrossAt(TimelineLaneGraphPainter painter, double speed) =>
        laneGraphAcross(
          speed,
          painter.fits.values.single.ranges.single,
          size.height,
          Axis.horizontal,
        );

    Layer withTrack(TransformTrack track) =>
        layer.copyWith(transformTrack: track);

    test('draws a handle on each side that eases toward the key beside it, '
        'as a value graph does — on a line of any numbers, a point\'s '
        'too', () {
      List<(int, bool)> sides(LaneGraphLine line) => [
        for (final handle in speedOf(line).handlesIn(size))
          (handle.frame, handle.leaving),
      ];
      expect(sides(lineOf('rotation')), [(0, true), (6, false), (18, false)]);
      expect(sides(lineOf('position')), [(0, true), (8, false)]);
    });

    test('a handle stands as far along as its side reaches and as high as '
        'the speed it moves at by its key — its segment\'s average times its '
        'speed — its stem level from the key', () {
      final painter = speedOf(lineOf('rotation'));
      final handles = painter.handlesIn(size);
      // 30 over 0 to 6, and 30 over 12 to 18 — the hold's as if it did not
      // hold, as a run is placed: 5 a frame each.
      for (final (index, time, speed) in [
        (0, 2.0, 0.0),
        (1, 3.0, 5.0),
        (2, 16.5, 10.0),
      ]) {
        final handle = handles[index];
        final reason = '${handle.frame} ${handle.leaving ? 'out' : 'in'}';
        final at = readOf(handle.at, Axis.horizontal);
        expect(at.time, closeTo(time, 1e-9), reason: reason);
        expect(
          at.across,
          closeTo(acrossAt(painter, speed), 1e-9),
          reason: reason,
        );
        final key = readOf(handle.key, Axis.horizontal);
        expect(key.time, closeTo(handle.frame, 1e-9), reason: reason);
        expect(key.across, closeTo(at.across, 1e-9), reason: '$reason level');
        expect(handle.across.from, closeTo(acrossAt(painter, 0), 1e-9));
        expect(handle.across.to, closeTo(acrossAt(painter, 5), 1e-9));
      }
    });

    test('a handle stands on the line it pulls: by its key the line moves '
        'at the handle\'s speed', () {
      final line = lineOf('rotation');
      final curve = line.lane.curve!;
      final painter = speedOf(line);
      // 18's side comes after a hold, whose line lies still to the jump.
      for (final handle in painter.handlesIn(size).take(2)) {
        final (:from, :to) = handle.frames;
        final drawn = laneGraphSpeedAt(
          curve,
          handle.frame.toDouble(),
          from: from,
          to: to,
        );
        expect(
          readOf(handle.key, Axis.horizontal).across,
          closeTo(acrossAt(painter, drawn), 0.5),
          reason: '${handle.frame}',
        );
      }
    });

    test('a point\'s average is how far it walks its path over the frames '
        'it takes — a bent path\'s farther than the line between its '
        'keys — each segment its own', () {
      const ease = EaseSide(influence: 0.5, speed: 1);
      final bent = withTrack(
        TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>()
              .withKey(0, CanvasPoint(x: 0, y: 0), outgoing: ease)
              .withKey(8, CanvasPoint(x: 80, y: 0), path: KeyPath.auto)
              .withKey(16, CanvasPoint(x: 80, y: 60), incoming: ease),
        ),
      );
      final position = bent.transformTrack.position;
      final lengths = [
        for (final from in [0, 8]) position.wayFrom(from, pathKeySpace)!,
      ];
      expect(lengths.first.length, greaterThan(80), reason: '⛔전제: bent');
      expect(lengths.last.length, greaterThan(60), reason: '⛔전제: bent');
      final painter = speedOf(lineOf('position', on: bent));
      final handles = painter.handlesIn(size);
      expect(
        [for (final handle in handles) (handle.frame, handle.frames)],
        [(0, (from: 0, to: 8)), (16, (from: 8, to: 16))],
      );
      for (final (handle, way, time) in [
        (handles.first, lengths.first, 4.0),
        (handles.last, lengths.last, 12.0),
      ]) {
        final at = readOf(handle.at, Axis.horizontal);
        expect(at.time, closeTo(time, 1e-9));
        expect(at.across, closeTo(acrossAt(painter, way.length / 8), 1e-9));
      }
    });

    // An anchor point's keys walk a path too (anchor-walks-a-path).
    for (final laneId in ['position', 'anchor-point']) {
      test('a run through roving keys is one segment: its handles are its '
          'timed ends\', paced by the whole way — $laneId', () {
        const ease = EaseSide(influence: 0.5, speed: 1);
        final keys = PropertyTrack<CanvasPoint>()
            .withKey(0, CanvasPoint(x: 0, y: 0), outgoing: ease)
            .withKey(
              8,
              CanvasPoint(x: 80, y: 0),
              incoming: ease,
              outgoing: ease,
            )
            .withKey(16, CanvasPoint(x: 80, y: 60), incoming: ease)
            .withKeysRoving(frames: {8}, roving: true);
        final roving = withTrack(
          laneId == 'position'
              ? TransformTrack.empty().copyWith(position: keys)
              : TransformTrack.empty().copyWith(anchorPoint: keys),
        );
        final painter = speedOf(lineOf(laneId, on: roving));
        final handles = painter.handlesIn(size);
        expect(
          [
            for (final handle in handles)
              (handle.frame, handle.leaving, handle.frames),
          ],
          [(0, true, (from: 0, to: 16)), (16, false, (from: 0, to: 16))],
          reason: 'none on the roving key',
        );
        expect(
          readOf(handles.first.at, Axis.horizontal).across,
          closeTo(acrossAt(painter, (80 + 60) / 16), 1e-9),
        );
      });
    }

    test('a pair of numbers that walks no path averages the line between '
        'its keys — a scale\'s, as it reads them', () {
      final scaled = withTrack(
        TransformTrack.empty().copyWith(
          scale: PropertyTrack<CanvasPoint>()
              .withKey(
                0,
                CanvasPoint(x: 1, y: 1),
                outgoing: const EaseSide(influence: 0.5, speed: 1),
              )
              .withKey(10, CanvasPoint(x: 1.3, y: 1.4)),
        ),
      );
      final painter = speedOf(lineOf('scale', on: scaled));
      expect(
        readOf(painter.handlesIn(size).single.at, Axis.horizontal).across,
        closeTo(acrossAt(painter, 50 / 10), 1e-9),
      );
    });

    for (final axis in Axis.values) {
      test('pulled to where it stands, a handle writes what it is — on the '
          '${axis.name} graph', () {
        final handles = speedOf(
          lineOf('rotation'),
          axis: axis,
        ).handlesIn(sizeFor(axis));
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
          expect(handle.leaving ? edit.incoming : edit.outgoing, isNull);
        }
      });
    }

    test('a pull is as fast as the hand is high — never slower than still — '
        'its reach held as a value graph holds it', () {
      final painter = speedOf(lineOf('rotation'));
      final handle = painter.handlesIn(size).first;
      KeySideEdit pulledTo(double time, double speed) => laneGraphPull(
        handle,
        Offset(laneGraphAlong(time, geometry.value), acrossAt(painter, speed)),
        frames: geometry.value,
        axis: Axis.horizontal,
      ).outgoing!;

      final half = pulledTo(3, 7.5);
      expect(half.influence, closeTo(0.5, 1e-9));
      expect(half.speed, closeTo(1.5, 1e-9), reason: '7.5 against 5 a frame');
      expect(pulledTo(3, -2).speed, 0, reason: 'never slower than still');
      expect(pulledTo(9, 5).influence, 1, reason: 'never past the next key');
      expect(pulledTo(-2, 5).influence, EaseSide.leastInfluence);
    });

    test('a side that sets off backward stands at its speed\'s size, on the '
        'line — and goes on backward, however fast it is pulled', () {
      final back = withTrack(
        TransformTrack.empty().copyWith(
          rotation: PropertyTrack<double>()
              .withKey(
                0,
                0,
                outgoing: const EaseSide(influence: 0.5, speed: -1),
              )
              .withKey(6, 30),
        ),
      );
      final painter = speedOf(lineOf('rotation', on: back));
      final handle = painter.handlesIn(size).single;
      expect(
        readOf(handle.at, Axis.horizontal).across,
        closeTo(acrossAt(painter, 5), 1e-9),
        reason: '5 a frame, the other way',
      );
      final edit = laneGraphPull(
        handle,
        Offset(handle.at.dx, acrossAt(painter, 10)),
        frames: geometry.value,
        axis: Axis.horizontal,
      );
      expect(edit.outgoing!.speed, closeTo(-2, 1e-9));
    });

    test('a way of no length has no height to read a speed off: its pull '
        'takes the influence alone', () {
      final level = withTrack(
        TransformTrack.empty().copyWith(
          rotation: PropertyTrack<double>()
              .withKey(
                0,
                10,
                outgoing: const EaseSide(influence: 0.4, speed: 2),
              )
              .withKey(6, 10),
        ),
      );
      final handle = speedOf(
        lineOf('rotation', on: level),
      ).handlesIn(size).single;
      final edit = laneGraphPull(
        handle,
        handle.at + const Offset(0, -40),
        frames: geometry.value,
        axis: Axis.horizontal,
      );
      expect(edit.outgoing!.influence, closeTo(0.4, 1e-9));
      expect(edit.outgoing!.speed, isNull);
    });

    test('a point\'s speed is one line, in its first number\'s colour', () {
      final canvas = TestRecordingCanvas();
      speedOf(lineOf('position')).paint(canvas, size);
      expect(
        [
          for (final call in canvas.invocations)
            if (call.invocation.memberName == #drawPath)
              (call.invocation.positionalArguments[1] as Paint).color
                  .toARGB32(),
        ],
        [LaneCurvePalette.across.toARGB32()],
      );
    });
  });
}
