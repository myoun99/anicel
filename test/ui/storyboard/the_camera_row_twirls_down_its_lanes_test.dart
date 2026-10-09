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
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/storyboard_panel.dart' show StoryboardPanel;
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_double_tap.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneKeyMarker;

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
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(initialProject: film());
    addTearDown(session.dispose);
    if (transitions.isNotEmpty) {
      session.transitions.updateTransitionInstructions(transitions);
    }
    final twirls = session.railView.expandedLaneLayerIds;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([session, twirls]),
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
              expandedLaneLayerIds: twirls.value,
              onToggleLayerLanes: SessionRowButtonPresses(session).toggleLanes,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (open) {
      await tester.tap(key('storyboard-lane-toggle-a-cam'));
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

      await tester.tap(key('storyboard-lane-toggle-a-cam'));
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

      await tester.tap(key('storyboard-lane-toggle-a-cam'));
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

      await tester.tap(key('storyboard-lane-toggle-a-cam'));
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
