import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
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
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/storyboard_panel.dart' show StoryboardPanel;
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart'
    show seekStoryboardGlobalFrame;
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_double_tap.dart';

/// 🗣️I-73 (유저 2026-10-08, the drawn proposal taken that day): 「이름 옆의
/// 접기(∨)로 어태치 행을 접고, 라벨 · fx · 눈 · 불투명도 · 블렌드 · 레인
/// 펼침이 타임라인과 같이 됩니다」 — and 「카메라 행 범위는 키표시/이동/레인 등
/// 모든거 콘티패널에서 가능. 컷 클램핑만 되도록」 (④ⓔ).
///
/// The conte row's head is the timeline's row, so its twirl opens the
/// conte's lanes under it as the timeline's does: each lane drawn as the
/// camera row's are, each cut's own conte over the cut's own frames. A row
/// riding the conte has no lanes, as on the timeline.
///
/// Cuts a [0, 12) and b [12, 24), each with a conte; a's Position keyed at
/// its own 2 and 8, b's at 3. Four frames of gap, then c [28, 40), which has
/// none.
void main() {
  const trackId = TrackId('t1');
  const a = CutId('a');
  const b = CutId('b');
  final rowId = trackConteRowId(trackId);

  TransformTrack positions(List<int> frames) {
    var position = PropertyTrack<CanvasPoint>.empty();
    for (final frame in frames) {
      position = position.withKey(frame, CanvasPoint(x: 10.0 * frame, y: 0));
    }
    return TransformTrack.empty().copyWith(position: position);
  }

  Layer conte(String cut, List<int> keys) => Layer(
    id: LayerId('$cut-conte'),
    name: 'Conte',
    kind: LayerKind.storyboard,
    transformTrack: positions(keys),
    frames: [Frame(id: FrameId('$cut-panel'), duration: 12, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-panel'), length: 12),
    },
  );

  Layer rider(String cut) => Layer(
    id: LayerId('$cut-over'),
    name: 'Conte+1',
    kind: LayerKind.storyboard,
    attachedToLayerId: LayerId('$cut-conte'),
    attachedPlacement: AttachedPlacement.above,
    attachedMode: AttachedMode.free,
    frames: [Frame(id: FrameId('$cut-over-1'), duration: 6, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$cut-over-1'), length: 6)},
  );

  Cut cutOf(String id, List<Layer> layers, {int gap = 0}) => Cut(
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

  Project film() => Project(
    id: const ProjectId('conte-lanes'),
    name: 'Conte lanes',
    createdAt: DateTime.utc(2026, 10, 9),
    tracks: [
      Track(
        id: trackId,
        name: 'V1',
        cuts: [
          cutOf('a', [conte('a', [2, 8]), rider('a')]),
          cutOf('b', [conte('b', [3]), rider('b')]),
          cutOf('c', const [], gap: 4),
        ],
      ),
    ],
  );

  Future<EditorSessionManager> pumpPanel(
    WidgetTester tester, {
    bool open = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(initialProject: film());
    addTearDown(session.dispose);
    final rail = session.railView;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([
              session,
              rail.expandedLaneLayerIds,
              rail.expandedLaneGroupKeys,
            ]),
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
              expandedLaneLayerIds: rail.expandedLaneLayerIds.value,
              onToggleLayerLanes: SessionRowButtonPresses(session).toggleLanes,
              expandedLaneGroupKeys: rail.expandedLaneGroupKeys.value,
              onToggleLaneGroupKey: SessionRowButtonPresses(
                session,
              ).toggleLaneGroup,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (open) {
      await tester.tap(key('storyboard-lane-toggle-a-conte'));
      await tester.pumpAndSettle();
    }
    return session;
  }

  Finder laneStrip(String laneId) =>
      key('storyboard-conte-lane-$laneId-row-t1');
  Finder laneLabel(String laneId) =>
      key('storyboard-lane-label-$rowId-$laneId');

  double ppf(WidgetTester tester) => tester
      .widget<StoryboardPanel>(find.byType(StoryboardPanel))
      .pixelsPerFrame;

  /// The track frames [conte]'s marks stand on along [laneId]'s strip.
  List<int> marksOf(WidgetTester tester, String laneId, String conte) {
    final strip = tester.getRect(laneStrip(laneId));
    final prefix = 'storyboard-conte-lane-key-span-$conte-$laneId-';
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

  Offset at(WidgetTester tester, String laneId, int globalFrame) {
    final strip = tester.getRect(laneStrip(laneId));
    return Offset(
      strip.left + (globalFrame + 0.5) * ppf(tester),
      strip.center.dy,
    );
  }

  Future<void> openPosition(WidgetTester tester) async {
    await tester.tap(key('storyboard-lane-group-toggle-$rowId-transform-group'));
    await tester.pumpAndSettle();
  }

  List<int> positionKeysOf(EditorSessionManager session, String layer) {
    for (final cut in session.repository.requireProject().tracks.single.cuts) {
      for (final row in cut.layers) {
        if (row.id == LayerId(layer)) {
          return [...row.transformTrack.position.keys.keys];
        }
      }
    }
    throw StateError('no $layer');
  }

  group('the twirl', () {
    testWidgets('the conte head\'s twirl opens its lanes under the row, label '
        'and strip on one line — and a row riding it has none', (
      tester,
    ) async {
      final session = await pumpPanel(tester, open: false);
      expect(laneStrip('transform-group'), findsNothing);
      expect(
        key('storyboard-lane-toggle-a-over'),
        findsNothing,
        reason: 'an attach row rides its base\'s lanes, as on the timeline',
      );

      await tester.tap(key('storyboard-lane-toggle-a-conte'));
      await tester.pumpAndSettle();

      final label = tester.getRect(laneLabel('transform-group'));
      final strip = tester.getRect(laneStrip('transform-group'));
      expect(label.top, closeTo(strip.top, 0.5), reason: 'one line');
      expect(label.height, closeTo(strip.height, 0.5));
      expect(
        session.railView.expandedLaneLayerIds.value,
        containsAll(const [LayerId('a-conte'), LayerId('b-conte')]),
        reason: 'the rows at its seat twirl as one',
      );
    });

    testWidgets('🚨its group twirls with the timeline\'s, in every cut at once',
        (tester) async {
      final session = await pumpPanel(tester);
      expect(laneStrip('position'), findsNothing);

      await openPosition(tester);

      expect(laneStrip('position'), findsOneWidget);
      expect(laneLabel('position'), findsOneWidget);
      expect(
        session.railView.expandedLaneGroupKeys.value,
        containsAll(['a-conte|transform-group', 'b-conte|transform-group']),
      );
    });

    testWidgets('a cut with no conte stood in keeps the lanes, names alone', (
      tester,
    ) async {
      final session = await pumpPanel(tester);
      await openPosition(tester);

      await tester.tapAt(at(tester, 'position', 30));
      await tester.pumpAndSettle();

      expect(session.activeCutId, const CutId('c'));
      expect(laneStrip('position'), findsOneWidget);
      expect(laneLabel('position'), findsOneWidget);
    });
  });

  group('what a lane draws', () {
    testWidgets('each cut\'s own conte keys at the cut\'s own place — the '
        'header their union', (tester) async {
      await pumpPanel(tester);
      await openPosition(tester);

      expect(marksOf(tester, 'transform-group', 'a-conte'), [2, 8]);
      expect(marksOf(tester, 'transform-group', 'b-conte'), [15]);
      expect(marksOf(tester, 'position', 'a-conte'), [2, 8]);
      expect(marksOf(tester, 'position', 'b-conte'), [15]);
      expect(marksOf(tester, 'scale', 'a-conte'), isEmpty);
    });
  });

  group('its labels and its groups', () {
    testWidgets('in a cut that holds no conte they keep their names and no '
        'value', (tester) async {
      await pumpPanel(tester);
      await openPosition(tester);
      await tester.tapAt(at(tester, 'position', 15));
      await tester.pumpAndSettle();
      expect(key('storyboard-lane-value-$rowId-position'), findsOneWidget);

      await tester.tapAt(at(tester, 'position', 30));
      await tester.pumpAndSettle();

      expect(laneLabel('position'), findsOneWidget);
      expect(key('storyboard-lane-value-$rowId-position'), findsNothing);
    });

    testWidgets('🚨its group shut while you stand on a member, the header '
        'takes the stand', (tester) async {
      final session = await pumpPanel(tester);
      await openPosition(tester);
      await tester.tapAt(at(tester, 'position', 15));
      await tester.pumpAndSettle();
      expect(session.storyboardStandingRow, LaneRowAddress(rowId, 'position'));

      await openPosition(tester);

      expect(laneStrip('position'), findsNothing);
      expect(
        session.storyboardStandingRow,
        LaneRowAddress(rowId, 'transform-group'),
      );
    });
  });

  test('🚨a conte born into the track takes the groups its seat has open',
      () {
    final session = EditorSessionManager(initialProject: film());
    addTearDown(session.dispose);
    SessionRowButtonPresses(
      session,
    ).toggleLaneGroup('a-conte|transform-group');
    expect(
      session.railView.expandedLaneGroupKeys.value,
      containsAll(['a-conte|transform-group', 'b-conte|transform-group']),
      reason: 'fixture: the seat twirls as one',
    );
    session.selectCut(const CutId('c'));
    session.selectLayer(const LayerId('c-cel'));

    session.layerStack.addLayerOfKind(LayerKind.storyboard);

    final born = session.repository
        .requireProject()
        .tracks
        .single
        .cuts
        .last
        .layers
        .firstWhere((layer) => layer.kind == LayerKind.storyboard);
    expect(
      session.railView.expandedLaneGroupKeys.value,
      contains('${born.id.value}|transform-group'),
    );
  });

  test('🚨in a gap its twirl still turns every row at its seat — open and '
      'shut', () {
    final session = EditorSessionManager(initialProject: film());
    addTearDown(session.dispose);
    seekStoryboardGlobalFrame(session, 26);
    expect(session.activeCutOrNull, isNull, reason: 'fixture: a gap');
    final presses = SessionRowButtonPresses(session);
    final twirls = session.railView.expandedLaneLayerIds;

    presses.toggleLanes(const LayerId('a-conte'));
    expect(
      twirls.value,
      containsAll(const [LayerId('a-conte'), LayerId('b-conte')]),
    );

    presses.toggleLanes(const LayerId('a-conte'));
    expect(twirls.value, isEmpty, reason: 'shut, not let back open');
  });

  group('pressing and sweeping a lane', () {
    testWidgets('a press stands on that lane of the row, in the cut pressed — '
        'the timeline\'s seat is the cut\'s conte', (tester) async {
      final session = await pumpPanel(tester);
      await openPosition(tester);

      await tester.tapAt(at(tester, 'position', 15));
      await tester.pumpAndSettle();

      expect(session.storyboardStandingRow, LaneRowAddress(rowId, 'position'));
      expect(session.activeCutId, b);
      expect(session.activeLayerId, const LayerId('b-conte'));
      expect(session.currentFrameIndex, 3);
    });

    testWidgets('🚨a sweep selects that lane\'s keys of the cut it began in, '
        'held to it', (tester) async {
      final session = await pumpPanel(tester);
      await openPosition(tester);

      final gesture = await tester.startGesture(
        at(tester, 'position', 1),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(at(tester, 'position', 20));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final selection = session.laneRangeSelection.value!;
      expect(selection.layerId, const LayerId('a-conte'));
      expect(selection.laneId, 'position');
      expect((selection.startIndex, selection.endIndexExclusive), (1, 12));
      expect(session.activeCutId, a);
    });

    testWidgets('🚨a double click on an empty cell keys that lane of the cut '
        'there', (tester) async {
      TimelineDoubleTapGate.reset();
      final session = await pumpPanel(tester);
      await openPosition(tester);

      final point = at(tester, 'position', 18);
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(positionKeysOf(session, 'b-conte'), [3, 6], reason: 'b\'s own 6');
      expect(positionKeysOf(session, 'a-conte'), [2, 8]);
    });
  });
}

Finder key(String value) => find.byKey(ValueKey<String>(value));
