import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_panel.dart' show StoryboardPanel;
import 'package:anicel/src/ui/timeline/lane_graph.dart'
    show LaneGraph, LaneGraphsView;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_double_tap.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneKeyMarker, timelineLaneKeyMarkerSizeOf;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';

/// 🗣️I-73 ④ (유저 2026-10-08): 「카메라 행 범위는 키표시/이동/레인 등 모든거
/// 콘티패널에서 가능. 컷 클램핑만 되도록」 — and the camera row's head is the
/// timeline's camera row, so its twirl opens the camera's lanes under it as
/// the timeline's does (ⓔ): each lane drawn as the row is, each cut's own
/// lane over the cut's own frames, held to the cut.
///
/// Cuts a [0, 24) and b [24, 48), four frames of gap, then c [52, 64). a's
/// camera keys 0, 12, 20 and 30 on every lane — the last past its end — and
/// 16 on its Position lane alone; b's 2, 6 and 12. With the O.L, a 12-frame
/// span at [18, 30) joins a and b.
void main() {
  const trackId = TrackId('t1');
  const a = CutId('a');
  const b = CutId('b');
  final rowId = trackCameraRowId(trackId);

  CutCamera keyed(List<int> frames, {List<int> positionOnly = const []}) {
    var track = CutCamera(
      keyframes: {
        for (final frame in frames)
          frame: CameraPose(center: CanvasPoint(x: 320.0 + frame, y: 180)),
      },
    ).track;
    for (final frame in positionOnly) {
      track = track.copyWith(
        position: track.position.withKey(
          frame,
          CanvasPoint(x: 320.0 + frame, y: 180),
        ),
      );
    }
    return CutCamera.fromTrack(track);
  }

  Cut cutOf(
    String id,
    int duration,
    List<int> keys, {
    int gap = 0,
    List<int> positionOnly = const [],
  }) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 640, height: 360),
    camera: keyed(keys, positionOnly: positionOnly),
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

  Project film() => Project(
    id: const ProjectId('camera-lanes'),
    name: 'Camera lanes',
    createdAt: DateTime.utc(2026, 10, 9),
    tracks: [
      Track(
        id: trackId,
        name: 'V1',
        cuts: [
          cutOf('a', 24, [0, 12, 20, 30], positionOnly: [16]),
          cutOf('b', 24, [2, 6, 12]),
          cutOf('c', 12, const [], gap: 4),
        ],
      ),
    ],
  );

  /// The 12-frame O.L across a|b.
  const ol = {18: InstructionEvent(instructionId: 'ol', length: 12)};

  Future<EditorSessionManager> pumpPanel(
    WidgetTester tester, {
    Map<int, InstructionEvent> transitions = const {},
    bool open = true,
  }) async {
    final session = EditorSessionManager(initialProject: film());
    addTearDown(session.dispose);
    if (transitions.isNotEmpty) {
      session.transitions.updateTransitionInstructions(transitions);
    }
    await pumpStoryboardHostOn(
      tester,
      session,
      surface: const Size(1600, 900),
      pixelsPerFrame: 12,
    );
    if (open) {
      await tester.tap(find.named('storyboard-lane-toggle-a-cam'));
      await tester.pumpAndSettle();
    }
    return session;
  }

  Finder laneStrip(String laneId) =>
      key('storyboard-camera-lane-$laneId-row-t1');
  Finder laneLabel(String laneId) =>
      key('storyboard-lane-label-$rowId-$laneId');

  double ppf(WidgetTester tester) => tester
      .widget<StoryboardPanel>(find.byType(StoryboardPanel))
      .pixelsPerFrame;

  /// The track frames [camera]'s marks stand on along [laneId]'s strip.
  List<int> marksOf(WidgetTester tester, String laneId, String camera) {
    final strip = tester.getRect(laneStrip(laneId));
    final prefix = 'storyboard-camera-lane-key-span-$camera-$laneId-';
    return [
      for (final element in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(prefix),
          )
          .evaluate())
        ((tester.getRect(find.byWidget(element.widget)).center.dx -
                    strip.left) /
                ppf(tester))
            .floor(),
    ]..sort();
  }

  Rect markRect(WidgetTester tester, String laneId, String camera, int frame) =>
      tester.getRect(
        key('storyboard-camera-lane-key-span-$camera-$laneId-$frame'),
      );

  bool ringed(WidgetTester tester, String laneId, String camera, int frame) =>
      tester
          .widget<TimelineLaneKeyMarker>(
            key('storyboard-camera-lane-key-$camera-$laneId-$frame'),
          )
          .selected;

  /// A point on [laneId]'s strip at [globalFrame]'s cell, [across] of the
  /// way down it.
  Offset at(
    WidgetTester tester,
    String laneId,
    int globalFrame, {
    double across = 0.5,
  }) {
    final strip = tester.getRect(laneStrip(laneId));
    return Offset(
      strip.left + (globalFrame + 0.5) * ppf(tester),
      strip.top + strip.height * across,
    );
  }

  Future<void> sweep(WidgetTester tester, Offset from, Offset to) async {
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Cut cutIn(EditorSessionManager session, CutId cutId) => session.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .singleWhere((cut) => cut.id == cutId);

  List<int> positionKeysOf(EditorSessionManager session, CutId cutId) => [
    ...cutIn(session, cutId).camera.track.position.keys.keys,
  ];

  List<int> scaleKeysOf(EditorSessionManager session, CutId cutId) => [
    ...cutIn(session, cutId).camera.track.scale.keys.keys,
  ];

  /// The band over the camera lanes, piece by piece, against [laneId]'s
  /// strip.
  List<Rect> bandOf(WidgetTester tester, String laneId) {
    final strip = tester.getRect(laneStrip(laneId));
    return [
      for (final element in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'storyboard-projection-lane-range-selection-',
                ),
          )
          .evaluate())
        tester.getRect(find.byWidget(element.widget)).shift(-strip.topLeft),
    ];
  }

  group('the twirl', () {
    testWidgets('the head\'s twirl opens the camera\'s lanes under the row — '
        'label and strip on one line, above the transition row', (
      tester,
    ) async {
      await pumpPanel(tester, open: false);
      expect(laneStrip('position'), findsNothing);
      expect(laneLabel('position'), findsNothing);

      await tester.tap(find.named('storyboard-lane-toggle-a-cam'));
      await tester.pumpAndSettle();

      final row = tester.getRect(key('storyboard-camera-row-t1'));
      var above = row.bottom;
      for (final laneId in const ['position', 'scale', 'rotation']) {
        final label = tester.getRect(laneLabel(laneId));
        final strip = tester.getRect(laneStrip(laneId));
        expect(label.top, closeTo(strip.top, 0.5), reason: '$laneId: a line');
        expect(label.height, closeTo(strip.height, 0.5));
        expect(strip.top, closeTo(above, 0.5), reason: '$laneId in order');
        above = strip.bottom;
      }
      expect(
        tester.getRect(key('storyboard-transition-row-t1')).top,
        closeTo(above, 0.5),
        reason: 'the transition row follows the lanes',
      );
    });

    testWidgets('🚨it is the track\'s: another cut stood in, and a gap, keep '
        'the lanes', (tester) async {
      final session = await pumpPanel(tester);

      await tester.tapAt(at(tester, 'position', 30));
      await tester.pumpAndSettle();
      expect(session.activeCutId, b);
      expect(laneStrip('position'), findsOneWidget, reason: 'b stood in');

      await tester.tapAt(at(tester, 'position', 50));
      await tester.pumpAndSettle();
      expect(session.activeCutOrNull, isNull);
      expect(laneStrip('position'), findsOneWidget, reason: 'a gap');
      expect(laneLabel('position'), findsOneWidget);
    });

    testWidgets('🚨its twirl is ONE for the track\'s cameras — every cut\'s '
        'camera twirls with it, and a cut born on the track wears it', (
      tester,
    ) async {
      final session = await pumpPanel(tester, open: false);
      final twirls = session.railView.expandedLaneLayerIds;
      List<LayerId> cameras() => [
        for (final cut in session.repository.requireProject().tracks.single
            .cuts)
          cut.layers.cameraLayer!.id,
      ];

      await tester.tap(find.named('storyboard-lane-toggle-a-cam'));
      await tester.pumpAndSettle();
      expect(
        twirls.value,
        containsAll(const [
          LayerId('a-cam'),
          LayerId('b-cam'),
          LayerId('c-cam'),
        ]),
        reason: 'one head',
      );

      session.selectCut(b);
      session.cutVerbs.createCut();
      await tester.pumpAndSettle();
      expect(cameras(), hasLength(4), reason: 'a cut with a camera, born');
      expect(twirls.value, containsAll(cameras()), reason: 'born wearing it');

      // The head is the camera of the cut stood in — the one just born.
      final head = session.requireActiveCut.layers.cameraLayer!.id;
      await tester.tap(find.named('storyboard-lane-toggle-${head.value}'));
      await tester.pumpAndSettle();
      expect(
        twirls.value.intersection(cameras().toSet()),
        isEmpty,
        reason: 'shut as one',
      );
    });

    testWidgets('the legend\'s twirl-all shuts and opens them too', (
      tester,
    ) async {
      await pumpPanel(tester);

      await tester.tap(key('legend-lanes-toggle'));
      await tester.pumpAndSettle();
      expect(laneStrip('position'), findsNothing, reason: 'all shut');

      await tester.tap(key('legend-lanes-toggle'));
      await tester.pumpAndSettle();
      expect(laneStrip('position'), findsOneWidget, reason: 'all open');
    });

    testWidgets('its head shuts them', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.named('storyboard-lane-toggle-a-cam'));
      await tester.pumpAndSettle();
      expect(laneStrip('position'), findsNothing);
      expect(laneLabel('position'), findsNothing);
    });

    testWidgets('🚨shut while you stand on one of them, the row takes the '
        'stand — what leaves the screen keeps nothing (R5 #11)', (
      tester,
    ) async {
      final session = await pumpPanel(tester);
      await tester.tapAt(at(tester, 'scale', 6));
      await tester.pumpAndSettle();
      expect(session.storyboardStandingRow, LaneRowAddress(rowId, 'scale'));

      await tester.tap(find.named('storyboard-lane-toggle-a-cam'));
      await tester.pumpAndSettle();

      expect(session.storyboardStandingRow, LayerRowAddress(rowId));
    });
  });

  group('what a lane draws', () {
    testWidgets('each cut\'s keys of that lane at the cut\'s own place, held '
        'to its own frames', (tester) async {
      await pumpPanel(tester);

      expect(marksOf(tester, 'position', 'a-cam'), [0, 12, 16, 20]);
      expect(marksOf(tester, 'scale', 'a-cam'), [0, 12, 20], reason: 'no 16');
      expect(marksOf(tester, 'position', 'b-cam'), [26, 30, 36]);
      expect(marksOf(tester, 'position', 'c-cam'), isEmpty);
      expect(
        key('storyboard-camera-lane-key-span-a-cam-position-30'),
        findsNothing,
        reason: 'a ends at 24; its key at 30 would stand on b',
      );
      expect(
        key('storyboard-camera-lane-position-line-a-cam'),
        findsOneWidget,
        reason: 'the line between its keys',
      );
      expect(
        {
          for (final marker in tester.widgetList<TimelineLaneKeyMarker>(
            find.byType(TimelineLaneKeyMarker),
          ))
            marker.axis,
        },
        {Axis.horizontal},
        reason: 'the storyboard lays its track across: its marks lie, as the '
            'timeline\'s do',
      );
    });

    testWidgets('🚨an O.L splits each lane as it splits the row — the leaving '
        'cut above, the arriving below', (tester) async {
      await pumpPanel(tester, transitions: ol);

      final strip = tester.getRect(laneStrip('position'));
      expect(
        markRect(tester, 'position', 'a-cam', 12).center.dy,
        closeTo(strip.center.dy, 1),
        reason: 'before the O.L, one line',
      );
      expect(
        markRect(tester, 'position', 'a-cam', 20).center.dy,
        lessThan(strip.center.dy),
        reason: 'a leaves, above',
      );
      expect(marksOf(tester, 'position', 'b-cam'), [20, 24, 30]);
      expect(
        markRect(tester, 'position', 'b-cam', 2).center.dy,
        greaterThan(strip.center.dy),
        reason: 'b arrives, below',
      );
    });

    // F-367-Q4 (user, 2026-10-18): 「세로 유지 · 가로만 줄임(프레임 블록처럼)」
    // — a member's key reads its cell along the track, as the band's does
    // ([timelineLaneKeyMarkerSizeOf]).
    testWidgets('🚨a member key keeps the lane\'s height and narrows with its '
        'cell, as the band\'s do', (tester) async {
      await pumpPanel(tester);
      final span = markRect(tester, 'position', 'a-cam', 12);
      final drawn = tester.getRect(
        find.descendant(
          of: key('storyboard-camera-lane-key-a-cam-position-12'),
          matching: find.byType(CustomPaint),
        ),
      );
      final wanted = timelineLaneKeyMarkerSizeOf(
        span.height,
        frameCellExtent: ppf(tester),
        heads: false,
      );
      expect(
        timelineLaneKeyMarkerSizeOf(
          span.height,
          frameCellExtent: span.height,
          heads: false,
        ).width,
        isNot(moreOrLessEquals(wanted.width)),
        reason: '⛔전제: a cell narrower than the lane is high',
      );
      expect(drawn.width, moreOrLessEquals(wanted.width));
      expect(drawn.height, moreOrLessEquals(wanted.height));
    });

  });

  group('pressing a lane', () {
    testWidgets('stands on that lane of the row, in the cut pressed — the '
        'timeline\'s seat is the cut\'s camera', (tester) async {
      final session = await pumpPanel(tester);

      await tester.tapAt(at(tester, 'scale', 30));
      await tester.pumpAndSettle();

      expect(session.storyboardStandingRow, LaneRowAddress(rowId, 'scale'));
      expect(session.activeCutId, b);
      expect(session.activeLayerId, const LayerId('b-cam'));
      expect(session.currentFrameIndex, 6, reason: 'b\'s own frame at 30');
    });

    testWidgets('🚨over an O.L the line pressed names the cut', (tester) async {
      final session = await pumpPanel(tester, transitions: ol);

      await tester.tapAt(at(tester, 'position', 20, across: 0.8));
      await tester.pumpAndSettle();
      expect(session.activeCutId, b, reason: 'the lower line is b\'s');
      expect(session.currentFrameIndex, 2);

      await tester.tapAt(at(tester, 'position', 20, across: 0.2));
      await tester.pumpAndSettle();
      expect(session.activeCutId, a, reason: 'the upper line is a\'s');
      expect(session.currentFrameIndex, 20);
    });

    testWidgets('its label reads the cut stood in at the frame of its own, '
        'and its ◆ walks that cut\'s keys', (tester) async {
      final session = await pumpPanel(tester);

      await tester.tapAt(at(tester, 'position', 27));
      await tester.pumpAndSettle();
      expect(session.currentFrameIndex, 3, reason: 'b\'s own 3');

      await tester.tap(key('storyboard-lane-next-key-$rowId-position'));
      await tester.pumpAndSettle();
      expect(session.activeCutId, b);
      expect(session.currentFrameIndex, 6, reason: 'b\'s next key');

      await tester.tap(key('storyboard-lane-prev-key-$rowId-position'));
      await tester.pumpAndSettle();
      expect(session.currentFrameIndex, 2, reason: 'b\'s key before it');
    });
  });

  group('its labels — the timeline lane\'s own, on the cut stood in', () {
    String valueOf(WidgetTester tester, String laneId) => tester
        .widget<Text>(
          find.descendant(
            of: key('storyboard-lane-value-$rowId-$laneId'),
            matching: find.byType(Text),
          ),
        )
        .data!;

    testWidgets('🚨its ◆ keys that lane of the camera stood in, at the frame '
        'of its own', (tester) async {
      final session = await pumpPanel(tester);
      await tester.tapAt(at(tester, 'scale', 28));
      await tester.pumpAndSettle();

      await tester.tap(key('storyboard-lane-key-toggle-$rowId-scale'));
      await tester.pumpAndSettle();

      expect(scaleKeysOf(session, b), [2, 4, 6, 12], reason: 'b\'s own 4');
      expect(positionKeysOf(session, b), [2, 6, 12]);
    });

    // 🗣️F-475 (유저 2026-10-26): 「다른버튼도 조사」.
    testWidgets('🚨a stroke down its ◆s keys every lane of the camera stood '
        'in, at the frame of its own', (tester) async {
      final session = await pumpPanel(tester);
      await tester.tapAt(at(tester, 'scale', 28));
      await tester.pumpAndSettle();

      await sweep(
        tester,
        tester.getCenter(key('storyboard-lane-key-toggle-$rowId-position')),
        tester.getCenter(key('storyboard-lane-key-toggle-$rowId-rotation')),
      );

      final camera = cutIn(session, b).camera.track;
      expect(
        {
          'position': [...camera.position.keys.keys],
          'scale': [...camera.scale.keys.keys],
          'rotation': [...camera.rotation.keys.keys],
        },
        {
          'position': [2, 4, 6, 12],
          'scale': [2, 4, 6, 12],
          'rotation': [2, 4, 6, 12],
        },
        reason: 'b\'s own 4, on every lane the stroke crossed',
      );
      expect(scaleKeysOf(session, a), [0, 12, 20, 30]);
    });

    testWidgets('🚨a value scrubbed on it shows in flight and lands on the '
        'camera stood in, at the frame of its own', (tester) async {
      final session = await pumpPanel(tester);
      await tester.tapAt(at(tester, 'scale', 28));
      await tester.pumpAndSettle();
      final before = valueOf(tester, 'scale');

      final gesture = await tester.startGesture(
        tester.getCenter(key('storyboard-lane-value-$rowId-scale')),
        kind: PointerDeviceKind.mouse,
      );
      for (var step = 0; step < 6; step += 1) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      final during = valueOf(tester, 'scale');
      await gesture.up();
      await tester.pumpAndSettle();

      expect(during, isNot(before), reason: 'the label follows the scrub');
      expect(scaleKeysOf(session, b), contains(4), reason: 'keyed at b\'s 4');
      expect(scaleKeysOf(session, a), [0, 12, 20, 30]);
    });

    testWidgets('in a gap they keep their names and no value', (tester) async {
      await pumpPanel(tester);
      await tester.tapAt(at(tester, 'scale', 28));
      await tester.pumpAndSettle();
      expect(key('storyboard-lane-value-$rowId-scale'), findsOneWidget);

      await tester.tapAt(at(tester, 'scale', 50));
      await tester.pumpAndSettle();

      expect(laneLabel('scale'), findsOneWidget);
      expect(key('storyboard-lane-value-$rowId-scale'), findsNothing);
    });

    testWidgets('🚨in a gap the legend\'s twirl-all still shuts them', (
      tester,
    ) async {
      final session = await pumpPanel(tester);
      await tester.tapAt(at(tester, 'scale', 50));
      await tester.pumpAndSettle();
      expect(session.activeCutOrNull, isNull);

      await tester.tap(key('legend-lanes-toggle'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(laneStrip('scale'), findsNothing);
    });
  });

  group('a double click on a lane — the timeline lane\'s own', () {
    setUp(TimelineDoubleTapGate.reset);

    Future<void> clickTwice(WidgetTester tester, Offset point) async {
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
    }

    testWidgets('🚨on an empty cell, keys that lane of the cut there — and no '
        'other', (tester) async {
      final session = await pumpPanel(tester);

      await clickTwice(tester, at(tester, 'scale', 28));

      expect(scaleKeysOf(session, b), [2, 4, 6, 12], reason: 'b\'s own 4');
      expect(positionKeysOf(session, b), [2, 6, 12], reason: 'scale alone');
      expect(scaleKeysOf(session, a), [0, 12, 20, 30]);
    });

    // I-89 ① ⓕ: the double click lands on the frame it names, as the
    // timeline's does — and over an O.L that frame is the line's cut's,
    // where the track frame alone would name the cut in front.
    testWidgets('🚨over an O.L, keys the lane of the cut whose line it is on', (
      tester,
    ) async {
      final session = await pumpPanel(tester, transitions: ol);

      await clickTwice(tester, at(tester, 'scale', 21, across: 0.8));

      expect(scaleKeysOf(session, b), [2, 3, 6, 12], reason: 'b\'s own 3');
      expect(scaleKeysOf(session, a), [0, 12, 20, 30]);
    });
  });

  group('a sweep on a lane — the timeline lane\'s range, held to the cut', () {
    testWidgets('🚨selects that lane\'s keys of the cut it began in, on its '
        'camera — and stops at the cut\'s last frame', (tester) async {
      final session = await pumpPanel(tester);

      await sweep(tester, at(tester, 'position', 10), at(tester, 'position', 40));

      final selection = session.laneRangeSelection.value!;
      expect(selection.layerId, const LayerId('a-cam'));
      expect(selection.laneId, 'position');
      expect(
        (selection.startIndex, selection.endIndexExclusive),
        (10, 24),
        reason: 'a\'s own 10 to its last, not on into b',
      );
      expect(session.storyboardStandingRow, LaneRowAddress(rowId, 'position'));
      expect(ringed(tester, 'position', 'a-cam', 12), isTrue);
      expect(ringed(tester, 'position', 'a-cam', 16), isTrue);
      expect(ringed(tester, 'position', 'a-cam', 0), isFalse);
      expect(ringed(tester, 'scale', 'a-cam', 12), isFalse, reason: 'its lane');
      final band = bandOf(tester, 'position').single;
      final strip = tester.getRect(laneStrip('position'));
      expect(band.left, closeTo(10 * ppf(tester), 0.01));
      expect(band.right, closeTo(24 * ppf(tester), 0.01));
      expect((band.top, band.height), (0, strip.height));
    });

    // 🗣️F-514 (유저 2026-10-30): a graph shows what it picked itself.
    testWidgets('🎯a lane in an open graph wears no band, and what it picks '
        'stands', (tester) async {
      final session = await pumpPanel(tester);
      await sweep(
        tester,
        at(tester, 'position', 10),
        at(tester, 'position', 40),
      );
      final band = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'storyboard-projection-lane-range-selection-',
            ),
      );
      expect(band, findsOneWidget, reason: 'fixture: its strip wears it');
      final picked = session.laneRangeSelection.value;

      session.railView.laneGraphs.value = LaneGraphsView(
        open: {
          laneGroupKey(rowId, transformGroupHeaderLane.laneId):
              const LaneGraph(),
        },
      );
      await tester.pumpAndSettle();

      expect(laneStrip('position'), findsNothing, reason: 'fixture: seated');
      expect(band, findsNothing);
      expect(session.laneRangeSelection.value, picked);
    });

    testWidgets('a sweep down across the lanes spans them, and the band runs '
        'across them as one', (tester) async {
      final session = await pumpPanel(tester);

      await sweep(
        tester,
        at(tester, 'position', 10),
        at(tester, 'rotation', 14),
      );

      final selection = session.laneRangeSelection.value!;
      expect(selection.layerId, const LayerId('a-cam'));
      expect(selection.laneIds, ['position', 'scale', 'rotation']);
      final band = bandOf(tester, 'position').single;
      final rotation = tester.getRect(laneStrip('rotation'));
      final position = tester.getRect(laneStrip('position'));
      expect(band.height, closeTo(rotation.bottom - position.top, 0.5));
    });

    testWidgets('🚨a sweep begun on a lane\'s lower half reaches the lane its '
        'pointer is in, measured from the lane\'s top', (tester) async {
      final session = await pumpPanel(tester);

      await sweep(
        tester,
        at(tester, 'position', 10, across: 0.6),
        at(tester, 'rotation', 12, across: 0.2),
      );

      expect(
        session.laneRangeSelection.value!.laneIds,
        ['position', 'scale', 'rotation'],
      );
    });

    testWidgets('🚨over an O.L the band stands on the line of the cut', (
      tester,
    ) async {
      final session = await pumpPanel(tester, transitions: ol);
      final strip = tester.getRect(laneStrip('position'));

      await sweep(
        tester,
        at(tester, 'position', 20, across: 0.8),
        at(tester, 'position', 22, across: 0.8),
      );

      final selection = session.laneRangeSelection.value!;
      expect(selection.layerId, const LayerId('b-cam'));
      expect((selection.startIndex, selection.endIndexExclusive), (2, 5));
      final band = bandOf(tester, 'position').single;
      expect((band.top, band.height), (strip.height / 2, strip.height / 2));
    });

    testWidgets('🚨a drag from inside the selection moves that lane\'s keys '
        'of the cut, and no other lane\'s', (tester) async {
      final session = await pumpPanel(tester);
      await sweep(tester, at(tester, 'position', 11), at(tester, 'position', 17));
      expect(session.laneRangeSelection.value!.startIndex, 11);

      await sweep(tester, at(tester, 'position', 12), at(tester, 'position', 14));

      expect(positionKeysOf(session, a), [0, 14, 18, 20, 30]);
      expect(scaleKeysOf(session, a), [0, 12, 20, 30]);
      expect(positionKeysOf(session, b), [2, 6, 12]);
    });

    testWidgets('a tap on a lane lets the selection go', (tester) async {
      final session = await pumpPanel(tester);
      await sweep(tester, at(tester, 'position', 10), at(tester, 'position', 14));
      expect(session.laneRangeSelection.value, isNotNull);

      await tester.tapAt(
        at(tester, 'position', 40),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(session.laneRangeSelection.value, isNull);
    });
  });
}

Finder key(String value) => find.byKey(ValueKey<String>(value));
