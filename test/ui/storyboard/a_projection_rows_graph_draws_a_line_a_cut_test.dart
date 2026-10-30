import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/timeline/lane_graph.dart';
import 'package:anicel/src/ui/timeline/lane_graph_box_stretch.dart';
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart'
    show LaneGraphReach;
import 'package:anicel/src/ui/timeline/lane_graph_toggle.dart'
    show LaneGraphToggle;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show PropertyLaneRow, laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart'
    show LaneEditPreview;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart'
    show
        LaneGraphHandle,
        LaneGraphPicture,
        TimelineLaneGraph,
        TimelineLaneGraphPainter;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';

/// **I-89 ① — a projection row's header graph draws a line a cut.**
///
/// 🗣️유저 2026-10-13: everything the timeline panel has, the conte panel
/// has, by the same law and the same code. The camera row and the conte
/// row show a cut's layer in every cut (I-73 ④), so the graph over their
/// lanes draws each cut's lane of that layer — valued in the cut, over the
/// cut's own frames on the track (「컷 클램핑만 되도록」, 유저 2026-10-08).
/// The session keys a graph by the layer the row has in hand and turns the
/// row's head family as one; the rail keys it by the row's own id, so its
/// buttons, pins and tools turn the camera in hand's.
///
/// Cuts a [0, 24) and b [24, 48), four frames of gap, then c [52, 64). a's
/// camera keys 0 and 12, b's 2 and 6 — each one's Rotation eased out of its
/// first; c's none. An S row beside them, twirled to its Transform group.
void main() {
  const trackId = TrackId('t1');
  const aCam = LayerId('a-cam');
  const s1 = LayerId('s1');
  final transform = transformGroupHeaderLane.laneId;
  final cameraRow = trackCameraRowId(trackId);
  final inHand = laneGroupKey(aCam, transform);
  final cameraGraph = laneGroupKey(cameraRow, transform);

  /// A camera keyed at [frames], its Rotation eased out of the first.
  CutCamera keyed(List<int> frames) {
    final track = CutCamera(
      keyframes: {
        for (final frame in frames)
          frame: CameraPose(center: CanvasPoint(x: 320.0 + frame, y: 180)),
      },
    ).track;
    var rotation = PropertyTrack<double>();
    for (final (index, frame) in frames.indexed) {
      rotation = rotation.withKey(
        frame,
        3.0 * frame,
        outgoing: index == 0 ? const EaseSide() : null,
      );
    }
    return CutCamera.fromTrack(track.copyWith(rotation: rotation));
  }

  Cut cameraCut(String id, int duration, List<int> keys, {int gap = 0}) =>
      Cut(
        id: CutId(id),
        name: id,
        duration: duration,
        leadingGapFrames: gap,
        canvasSize: const CanvasSize(width: 640, height: 360),
        camera: keyed(keys),
        layers: [
          Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
          Layer(
            id: LayerId('$id-cam'),
            name: 'Camera',
            kind: LayerKind.camera,
            frames: const [],
          ),
        ],
      );

  Project cameras() => Project(
    id: const ProjectId('camera-graphs'),
    name: 'Camera graphs',
    createdAt: DateTime.utc(2026, 10, 16),
    tracks: [
      Track(
        id: trackId,
        name: 'V1',
        cuts: [
          cameraCut('a', 24, [0, 12]),
          cameraCut('b', 24, [2, 6]),
          cameraCut('c', 12, const [], gap: 4),
        ],
        seLayers: [
          Layer(
            id: s1,
            name: 'S1',
            kind: LayerKind.se,
            frames: [
              Frame(id: const FrameId('s1-f'), duration: 8, strokes: const []),
            ],
            timeline: {
              0: const TimelineExposure.drawing(FrameId('s1-f'), length: 8),
            },
            lanesExpanded: true,
            expandedLaneGroups: {transform},
          ),
        ],
      ),
    ],
  );

  /// The host over a session holding [project], wired as the workspace
  /// wires it — the twirls, and the header graphs: the timeline's state,
  /// turned by the timeline's verbs — with [twirl]'s lanes open.
  Future<EditorSessionManager> pumpHost(
    WidgetTester tester,
    Project project, {
    required String twirl,
  }) async {
    final session = await pumpStoryboardHost(
      tester,
      project,
      surface: const Size(1600, 1200),
      pixelsPerFrame: 12,
    );
    await tester.tap(find.named('storyboard-lane-toggle-$twirl'));
    await tester.pumpAndSettle();
    return session;
  }

  Finder graphOf(String key) =>
      find.byKey(ValueKey<String>('storyboard-lane-graph-$key'));

  /// [key]'s graph's lines of [laneId] — its own, or its [guests] — each
  /// by its layer and where it reaches.
  List<(String, LaneGraphReach?)> linesOf(
    WidgetTester tester,
    String key,
    String laneId, {
    bool guests = false,
  }) {
    final lines = tester.widget<TimelineLaneGraph>(graphOf(key)).lines;
    return [
      for (final line in guests ? lines.guests() : lines.own())
        if (line.lane.laneId == laneId) (line.layer.id.value, line.reach),
    ];
  }

  /// The lanes of [laneId] [key]'s graph draws as its own, a line each.
  List<PropertyLaneRow> lanesOf(
    WidgetTester tester,
    String key,
    String laneId,
  ) => [
    for (final line
        in tester.widget<TimelineLaneGraph>(graphOf(key)).lines.own())
      if (line.lane.laneId == laneId) line.lane,
  ];

  bool lit(WidgetTester tester, String name) => tester
      .widget<LaneGraphToggle>(
        find.ancestor(
          of: find.named(name),
          matching: find.byType(LaneGraphToggle),
        ),
      )
      .on;

  LaneGraphsView graphs(EditorSessionManager session) =>
      session.railView.laneGraphs.value;

  /// The one handle [key]'s graph draws on [layer]'s [laneId] line, and
  /// where it stands on the screen.
  (LaneGraphHandle, Offset) handleOn(
    WidgetTester tester,
    String key,
    LayerId layer,
    String laneId,
  ) {
    final paint = find.descendant(
      of: find.descendant(
        of: graphOf(key),
        matching: find.byType(LaneGraphPicture),
      ),
      matching: find.byType(CustomPaint),
    );
    final painter =
        tester.widget<CustomPaint>(paint).painter! as TimelineLaneGraphPainter;
    final box = tester.renderObject<RenderBox>(paint);
    final handle = painter
        .handlesIn(box.size)
        .singleWhere(
          (handle) =>
              handle.line.layer.id == layer &&
              handle.line.lane.laneId == laneId,
        );
    return (handle, box.localToGlobal(handle.at));
  }

  /// Pulls the handle at [at] up and right by a little, a mouse's pull —
  /// [mid] asked while it is held.
  Future<void> pull(
    WidgetTester tester,
    Offset at, {
    void Function()? mid,
  }) async {
    final gesture = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(20, -20));
    await tester.pump();
    mid?.call();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('the timeline\'s verb on the camera in hand opens the camera '
      'row\'s graph over its lanes — a line a cut, each over the cut\'s own '
      'frames', (tester) async {
    final session = await pumpHost(tester, cameras(), twirl: 'a-cam');
    expect(graphOf(cameraGraph), findsNothing);

    SessionRowButtonPresses(session).toggleLaneGraph(inHand);
    await tester.pumpAndSettle();

    expect(graphOf(cameraGraph), findsOneWidget);
    expect(linesOf(tester, cameraGraph, 'position'), [
      ('a-cam', (start: 0, end: 24)),
      ('b-cam', (start: 24, end: 48)),
      ('c-cam', (start: 52, end: 64)),
    ]);
    // Valued in its cut: each line the curve its own camera's keys draw —
    // at the cut's own 12, a's last key, b held at its last, c at rest.
    final rotations = [
      for (final lane in lanesOf(tester, cameraGraph, 'rotation')) lane.curve,
    ];
    expect(rotations, everyElement(isNotNull));
    expect([for (final curve in rotations) curve!.at(12).single], [36, 18, 0]);
  });

  testWidgets('the camera row\'s head wears the timeline camera row\'s graph '
      'button: it turns the graph of the camera in hand, and reads it so', (
    tester,
  ) async {
    final session = await pumpHost(tester, cameras(), twirl: 'a-cam');
    const button = 'storyboard-layer-graph-a-cam';
    expect(find.named(button), findsOneWidget);
    expect(lit(tester, button), isFalse);

    await tester.tap(find.named(button));
    await tester.pumpAndSettle();
    expect(graphs(session).open.keys, contains(inHand));
    expect(graphOf(cameraGraph), findsOneWidget);
    expect(lit(tester, button), isTrue);

    await tester.tap(find.named(button));
    await tester.pumpAndSettle();
    expect(graphs(session).open.keys, isNot(contains(inHand)));
    expect(graphOf(cameraGraph), findsNothing);
  });

  testWidgets('a camera lane\'s pin is that lane of the camera in hand: every '
      'open graph of another row draws it as a guest, a line a cut', (
    tester,
  ) async {
    final session = await pumpHost(tester, cameras(), twirl: 'a-cam');
    final seGraph = laneGroupKey(s1, transform);
    SessionRowButtonPresses(session).toggleLaneGraph(seGraph);
    await tester.pumpAndSettle();
    final pin = 'storyboard-lane-pin-${cameraRow.value}-position';
    expect(find.named(pin), findsOneWidget);
    expect(lit(tester, pin), isFalse);

    await tester.tap(find.named(pin));
    await tester.pumpAndSettle();

    expect(graphs(session).pinned, contains(laneGroupKey(aCam, 'position')));
    expect(lit(tester, pin), isTrue);
    expect(linesOf(tester, seGraph, 'position', guests: true), [
      ('a-cam', (start: 0, end: 24)),
      ('b-cam', (start: 24, end: 48)),
      ('c-cam', (start: 52, end: 64)),
    ]);
  });

  testWidgets('its tools turn the graph of the camera in hand — the plot '
      'pill, the pen, the transform box, the snap, and the enlarging', (
    tester,
  ) async {
    final session = await pumpHost(tester, cameras(), twirl: 'a-cam');
    SessionRowButtonPresses(session).toggleLaneGraph(inHand);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'storyboard-lane-graph-plot-${LaneGraphMode.speed.name}-'
          '$cameraGraph',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(graphs(session).open[inHand]!.mode, LaneGraphMode.speed);

    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-lane-graph-pen-$cameraGraph')),
    );
    await tester.pumpAndSettle();
    expect(graphs(session).open[inHand]!.pen, isTrue);

    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-lane-graph-box-$cameraGraph')),
    );
    await tester.pumpAndSettle();
    expect(graphs(session).open[inHand]!.transformBox, isFalse);

    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-lane-graph-snap-$cameraGraph')),
    );
    await tester.pumpAndSettle();
    expect(graphs(session).open[inHand]!.snap, isTrue);

    await tester.tap(
      find.byKey(
        ValueKey<String>('storyboard-lane-graph-enlarge-$cameraGraph'),
      ),
    );
    await tester.pumpAndSettle();
    expect(graphs(session).open[inHand]!.enlarged, isTrue);
  });

  // graph-key-drag-snaps: this rail's frames are the track's.
  testWidgets('a key carried on it snaps by the track\'s playhead and by the '
      'movie\'s end, where the end line stands', (tester) async {
    final session = await pumpHost(tester, cameras(), twirl: 'a-cam');
    SessionRowButtonPresses(session).toggleLaneGraph(inHand);
    await tester.pumpAndSettle();

    final frames = tester
        .widget<LaneGraphPicture>(
          find.descendant(
            of: graphOf(cameraGraph),
            matching: find.byType(LaneGraphPicture),
          ),
        )
        .frameAxis;
    expect(frames.playhead, same(session.playheadCursors.trackFrame));
    expect(frames.frameCount, 64, reason: 'c ends on 64');
  });

  testWidgets('what it draws follows the row selection of the row\'s own '
      'lanes — a line a cut of each lane picked', (tester) async {
    final session = await pumpHost(tester, cameras(), twirl: 'a-cam');
    SessionRowButtonPresses(session).toggleLaneGraph(inHand);
    await tester.pumpAndSettle();
    expect(lanesOf(tester, cameraGraph, 'scale'), hasLength(3));

    session.rowSelection.value = [LaneRowAddress(cameraRow, 'position')];
    await tester.pumpAndSettle();

    expect(graphOf(cameraGraph), findsOneWidget);
    expect(lanesOf(tester, cameraGraph, 'position'), hasLength(3));
    expect(lanesOf(tester, cameraGraph, 'scale'), isEmpty);
  });

  testWidgets('a handle on the line of the cut stood in writes that cut\'s '
      'key, through the edits its lane labels key by', (tester) async {
    final session = await pumpHost(tester, cameras(), twirl: 'a-cam');
    SessionRowButtonPresses(session).toggleLaneGraph(inHand);
    await tester.pumpAndSettle();
    expect(session.activeCutId, const CutId('a'), reason: '⛔전제');
    final (handle, at) = handleOn(tester, cameraGraph, aCam, 'rotation');
    expect((handle.frame, handle.leaving), (0, true), reason: '⛔전제');

    await pull(tester, at);

    final cuts = session.repository.requireProject().tracks.single.cuts;
    expect(
      cuts.first.camera.track.rotation.keyAt(0)!.outgoing,
      isNot(const EaseSide()),
    );
    expect(
      cuts[1].camera.track.rotation.keyAt(2)!.outgoing,
      const EaseSide(),
      reason: 'b\'s, untouched',
    );
  });

  testWidgets('a handle on the line of a cut NOT stood in writes that cut\'s '
      'key where it is — its line bends as it goes, one undo, and the '
      'session stays where it stood (I-89-Q23)', (tester) async {
    final session = await pumpHost(tester, cameras(), twirl: 'a-cam');
    SessionRowButtonPresses(session).toggleLaneGraph(inHand);
    await tester.pumpAndSettle();
    expect(session.activeCutId, const CutId('a'), reason: '⛔전제');
    final (handle, at) = handleOn(
      tester,
      cameraGraph,
      const LayerId('b-cam'),
      'rotation',
    );
    expect((handle.frame, handle.leaving), (2, true), reason: '⛔전제');
    double bAt4() => lanesOf(tester, cameraGraph, 'rotation')[1].curve!
        .at(4)
        .single;
    final still = bAt4();
    Cut b() => session.repository.requireProject().tracks.single.cuts[1];

    await pull(
      tester,
      at,
      mid: () {
        expect(
          session.dragPreview.value,
          isA<LaneEditPreview>().having(
            (preview) => preview.cameraCutId,
            'cameraCutId',
            const CutId('b'),
          ),
        );
        expect(bAt4(), isNot(still), reason: 'b\'s line, in flight');
      },
    );

    expect(
      b().camera.track.rotation.keyAt(2)!.outgoing,
      isNot(const EaseSide()),
    );
    expect(
      session.repository
          .requireProject()
          .tracks
          .single
          .cuts
          .first
          .camera
          .track
          .rotation
          .keyAt(0)!
          .outgoing,
      const EaseSide(),
      reason: 'a\'s, untouched',
    );
    expect(session.activeCutId, const CutId('a'), reason: 'not stood in');

    session.undo();
    await tester.pumpAndSettle();
    expect(b().camera.track.rotation.keyAt(2)!.outgoing, const EaseSide());
  });

  /// [key]'s graph as it is drawn: its painter, and the box it paints.
  ({TimelineLaneGraphPainter painter, RenderBox box}) pictureOf(
    WidgetTester tester,
    String key,
  ) {
    final paint = find.descendant(
      of: find.descendant(
        of: graphOf(key),
        matching: find.byType(LaneGraphPicture),
      ),
      matching: find.byType(CustomPaint),
    );
    return (
      painter:
          tester.widget<CustomPaint>(paint).painter!
              as TimelineLaneGraphPainter,
      box: tester.renderObject<RenderBox>(paint),
    );
  }

  /// A mouse's box on [key]'s graph from frame [from]'s cell at its top to
  /// frame [to]'s at its foot (I-3 ⑤) — pressed on the graph's ground.
  Future<void> drawBox(
    WidgetTester tester,
    String key,
    int from,
    int to,
  ) async {
    final (:painter, :box) = pictureOf(tester, key);
    final frames = painter.frameAxis.geometry.value;
    final press = Offset(frames.edgeAt(from) + 1, 1);
    expect(
      (painter.keyAt(press, box.size), painter.handleAt(press, box.size)),
      (null, null),
      reason: '⛔전제: the ground',
    );
    final gesture = await tester.startGesture(
      box.localToGlobal(press),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(
      box.localToGlobal(Offset(frames.edgeAt(to) + 1, box.size.height - 1)),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a box on its ground picks the keys of the cut it began in, in '
      'that cut\'s own frames — as a sweep on the row\'s lanes does '
      '(I-3 ⑤)', (tester) async {
    final session = await pumpHost(tester, cameras(), twirl: 'a-cam');
    SessionRowButtonPresses(session).toggleLaneGraph(inHand);
    await tester.pumpAndSettle();

    // From a's own 10, over a's keys on 12 and b's on its own 2 and 6 (the
    // track's 26 and 30), to the track's 32.
    await drawBox(tester, cameraGraph, 10, 32);

    final picked = session.laneRangeSelection.value!;
    expect(
      (picked.layerId, picked.startIndex, picked.endIndexExclusive),
      (aCam, 10, 24),
    );
    expect(picked.spanLaneIds, [
      for (final line in pictureOf(tester, cameraGraph).painter.own)
        if (line.layer.id == aCam && line.lane.keyedFrames.contains(12))
          line.lane.laneId,
    ]);
    expect(picked.spanLaneIds, contains('rotation'), reason: '⛔전제');
  });

  testWidgets('a handle of the box round a cut\'s keys stretches them in '
      'that cut\'s own frames, about the box\'s other end (I-3 ⑥)', (
    tester,
  ) async {
    final session = await pumpHost(tester, cameras(), twirl: 'a-cam');
    SessionRowButtonPresses(session).toggleLaneGraph(inHand);
    session.selectCut(const CutId('b'));
    session.updateLaneRangeSelectionDrag(
      layerId: const LayerId('b-cam'),
      laneId: 'rotation',
      anchorIndex: 2,
      headIndex: 6,
      spanLaneIds: const ['rotation'],
    );
    await tester.pumpAndSettle();
    final (:painter, :box) = pictureOf(tester, cameraGraph);
    final round = painter.pickedIn(box.size).box!;
    final cell = painter.frameAxis.geometry.value.frameCellExtent;

    // b's keys on its own 2 and 6 — the track's 26 and 30 — and the
    // box's end pulled four frames on: twice as long about b's own 2.
    final gesture = await tester.startGesture(
      box.localToGlobal(
        laneGraphBoxHandleAt((along: 1, across: 0), round, Axis.horizontal),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(Offset(cell * 4, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final b = session.repository.requireProject().tracks.single.cuts[1];
    expect(b.camera.track.rotation.keys.keys.toList()..sort(), [2, 10]);
  });

  testWidgets('a box on its ground over an S row\'s pinned keys as well picks '
      'the cut\'s keys alone — a sweep on a projection row\'s lanes stays '
      'in them (I-3 ⑤)', (tester) async {
    final project = cameras();
    final s1Keyed = project.tracks.single.seLayers.single.copyWith(
      transformTrack: TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(14, 0).withKey(20, 30),
      ),
    );
    final session = await pumpHost(
      tester,
      project.copyWith(
        tracks: [project.tracks.single.copyWith(seLayers: [s1Keyed])],
      ),
      twirl: 'a-cam',
    );
    SessionRowButtonPresses(session)
      ..toggleLaneGraph(inHand)
      ..toggleLanePin(laneGroupKey(s1, 'rotation'));
    await tester.pumpAndSettle();
    expect(
      linesOf(tester, cameraGraph, 'rotation', guests: true),
      [('s1', null)],
      reason: '⛔전제',
    );

    await drawBox(tester, cameraGraph, 10, 22);

    expect(session.trackFrameRangeSelection.value, isNull);
    expect(session.laneRangeSelection.value, isNotNull);
    final picked = session.laneRangeSelection.value!;
    expect(
      (picked.layerId, picked.startIndex, picked.endIndexExclusive),
      (aCam, 10, 23),
    );
    expect(picked.spanLaneIds, [
      for (final line in pictureOf(tester, cameraGraph).painter.own)
        if (line.layer.id == aCam && line.lane.keyedFrames.contains(12))
          line.lane.laneId,
    ]);
  });

  testWidgets('a box on an S row\'s graph over a pinned row\'s keys as well '
      'picks the two rows on the track, as a sweep leaving the lanes does '
      '(I-3 ⑤)', (tester) async {
    const s2 = LayerId('s2');
    Layer keyedSound(LayerId id, {required bool open}) => Layer(
      id: id,
      name: id.value,
      kind: LayerKind.se,
      frames: [
        Frame(id: FrameId('${id.value}-f'), duration: 8, strokes: const []),
      ],
      timeline: {
        0: TimelineExposure.drawing(FrameId('${id.value}-f'), length: 8),
      },
      expandedLaneGroups: {if (open) transform},
      transformTrack: TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(4, 0).withKey(10, 30),
      ),
    );
    final project = cameras();
    final session = await pumpHost(
      tester,
      project.copyWith(
        tracks: [
          project.tracks.single.copyWith(
            seLayers: [
              keyedSound(s1, open: true),
              keyedSound(s2, open: false),
            ],
          ),
        ],
      ),
      twirl: 's1',
    );
    final key = laneGroupKey(s1, transform);
    SessionRowButtonPresses(session)
      ..toggleLaneGraph(key)
      ..toggleLanePin(laneGroupKey(s2, 'rotation'));
    await tester.pumpAndSettle();

    await drawBox(tester, key, 3, 10);

    expect(session.laneRangeSelection.value, isNull);
    expect(session.trackFrameRangeSelection.value, isNotNull);
    final picked = session.trackFrameRangeSelection.value!;
    expect(picked.rows, const [
      LaneRowAddress(s1, 'rotation'),
      LaneRowAddress(s2, 'rotation'),
    ]);
    expect((picked.startFrame, picked.endFrameExclusive), (3, 11));
  });

  group('the conte row', () {
    final conteRow = trackConteRowId(trackId);
    final conteGraph = laneGroupKey(conteRow, transform);

    /// [cut]'s conte, its Position keyed at [keys] — and, when [eased], its
    /// Rotation as well, eased out of the first.
    Layer conte(String cut, List<int> keys, {bool eased = false}) {
      var position = PropertyTrack<CanvasPoint>.empty();
      var rotation = PropertyTrack<double>();
      for (final (index, frame) in keys.indexed) {
        position = position.withKey(frame, CanvasPoint(x: 10.0 * frame, y: 0));
        if (eased) {
          rotation = rotation.withKey(
            frame,
            3.0 * frame,
            outgoing: index == 0 ? const EaseSide() : null,
          );
        }
      }
      return Layer(
        id: LayerId('$cut-conte'),
        name: 'Conte',
        kind: LayerKind.storyboard,
        transformTrack: TransformTrack.empty().copyWith(
          position: position,
          rotation: rotation,
        ),
        frames: [
          Frame(id: FrameId('$cut-panel'), duration: 12, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('$cut-panel'), length: 12),
        },
      );
    }

    Cut conteCut(String id, List<Layer> layers, {int gap = 0}) => Cut(
      id: CutId(id),
      name: id,
      duration: 12,
      leadingGapFrames: gap,
      canvasSize: const CanvasSize(width: 640, height: 360),
      layers: [
        Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
        ...layers,
      ],
    );

    /// Cuts a [0, 12) and b [12, 24), each with a conte — a's Position
    /// keyed at its own 2 and 8, b's at [b] ([eased] out of its first) —
    /// then c [28, 40), which has none.
    Project contes({List<int> b = const [3], bool eased = false}) => Project(
      id: const ProjectId('conte-graphs'),
      name: 'Conte graphs',
      createdAt: DateTime.utc(2026, 10, 16),
      tracks: [
        Track(
          id: trackId,
          name: 'V1',
          cuts: [
            conteCut('a', [
              conte('a', [2, 8]),
            ]),
            conteCut('b', [
              conte('b', b, eased: eased),
            ]),
            conteCut('c', const [], gap: 4),
          ],
        ),
      ],
    );

    testWidgets('its Transform header\'s graph button turns the graph of the '
        'conte in hand, drawn a line a cut that holds one, valued there', (
      tester,
    ) async {
      final session = await pumpHost(tester, contes(), twirl: 'a-conte');
      final button =
          'storyboard-lane-group-graph-${conteRow.value}-$transform';
      expect(find.named(button), findsOneWidget);

      await tester.tap(find.named(button));
      await tester.pumpAndSettle();

      expect(
        graphs(session).open.keys,
        contains(laneGroupKey(const LayerId('a-conte'), transform)),
      );
      expect(lit(tester, button), isTrue);
      expect(linesOf(tester, conteGraph, 'position'), [
        ('a-conte', (start: 0, end: 12)),
        ('b-conte', (start: 12, end: 24)),
      ]);
      // Each its own cut's keys, and a curve to draw them by.
      final positions = lanesOf(tester, conteGraph, 'position');
      expect([for (final lane in positions) lane.keyedFrames], [
        {2, 8},
        {3},
      ]);
      expect(
        [for (final lane in positions) lane.curve],
        everyElement(isNotNull),
      );
    });

    testWidgets('a handle on the line of a cut not stood in writes that '
        'cut\'s conte where it is (I-89-Q23)', (tester) async {
      final session = await pumpHost(
        tester,
        contes(b: [3, 9], eased: true),
        twirl: 'a-conte',
      );
      await tester.tap(
        find.named('storyboard-lane-group-graph-${conteRow.value}-$transform'),
      );
      await tester.pumpAndSettle();
      expect(session.activeCutId, const CutId('a'), reason: '⛔전제');
      final (handle, at) = handleOn(
        tester,
        conteGraph,
        const LayerId('b-conte'),
        'rotation',
      );
      expect((handle.frame, handle.leaving), (3, true), reason: '⛔전제');

      await pull(tester, at);

      Layer conteOf(int cut) => session.repository
          .requireProject()
          .tracks
          .single
          .cuts[cut]
          .layers
          .firstWhere((layer) => layer.kind == LayerKind.storyboard);
      expect(
        conteOf(1).transformTrack.rotation.keyAt(3)!.outgoing,
        isNot(const EaseSide()),
      );
      expect(
        conteOf(0).transformTrack.rotation.keys,
        isEmpty,
        reason: 'a\'s, untouched',
      );
      expect(session.activeCutId, const CutId('a'), reason: 'not stood in');
    });
  });
}
