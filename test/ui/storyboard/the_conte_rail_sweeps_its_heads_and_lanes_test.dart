import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/timeline/lane_graph.dart' show LaneGraphsView;

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_twirls.dart';

/// 🗣️I-89 ①ⓒ (유저 2026-10-13): 「다시 말하지만 이런건 다 콘티패널에도
/// 동일하게 있어야해. 같은 법으로」 — the conte rail sweeps the timeline's
/// one list over every row it draws: the camera and conte heads, which wear
/// the timeline's row, and every lane, whose group switch, graph and pin
/// buttons are the timeline's lanes' own. ↩️Its list of its own stepped
/// over the camera row and every lane, and the conte head's twirl.
///
/// Each stroke lands as a FAST swipe does — its down and its first move in
/// one frame, nothing rebuilt between the press and the sweep — so the row
/// it starts on is read as the press left it, across the rail's border: a
/// projection head by the layer it has in hand.
///
/// Track t1: cuts a and b, each with a camera and a conte, a stood in; an S
/// row; a chain of two effects on the V row. Track t2 under it: one cut, an
/// S row.
void main() {
  // ⛔THE CLAIM SET IS GLOBAL — a stroke left claimed reads the next case's
  // press as one a button already handled.
  tearDown(debugClearValueControlPointers);

  const t1 = TrackId('t1');
  final carrier = trackTransformLaneCarrierId(t1);
  final conteRow = trackConteRowId(t1);
  const effects = [EffectId('blur'), EffectId('glow')];
  const shade = EffectId('shade');

  Layer se(String id) => Layer(
    id: LayerId(id),
    name: 'S1',
    kind: LayerKind.se,
    frames: const [],
    timeline: const {},
  );

  Cut cutOf(String id, {bool projections = true}) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
      if (projections) ...[
        Layer(
          id: LayerId('$id-cam'),
          name: 'Camera',
          kind: LayerKind.camera,
          frames: const [],
        ),
        Layer(
          id: LayerId('$id-conte'),
          name: 'Conte',
          kind: LayerKind.storyboard,
          effects: [LayerEffect(id: shade, kind: EffectKind.blur)],
          frames: [
            Frame(id: FrameId('$id-panel'), duration: 12, strokes: const []),
          ],
          timeline: {
            0: TimelineExposure.drawing(FrameId('$id-panel'), length: 12),
          },
        ),
      ],
    ],
  );

  Project film() => Project(
    id: const ProjectId('conte-sweep'),
    name: 'Conte sweep',
    createdAt: DateTime.utc(2026, 10, 17),
    tracks: [
      Track(
        id: t1,
        name: 'V1',
        seLayers: [se('t1-s1')],
        effects: [
          for (final effect in effects)
            LayerEffect(id: effect, kind: EffectKind.blur),
        ],
        cuts: [cutOf('a'), cutOf('b')],
      ),
      Track(
        id: const TrackId('t2'),
        name: 'V2',
        seLayers: [se('t2-s1')],
        cuts: [cutOf('c', projections: false)],
      ),
    ],
  );

  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(initialProject: film());
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: withStoryboardTwirls(
            session,
            (twirls) => ValueListenableBuilder<LaneGraphsView>(
              valueListenable: session.railView.laneGraphs,
              builder: (context, open, _) => StoryboardTabHost(
                session: session,
                expandedLaneLayerIds: twirls.expandedLaneLayerIds,
                onToggleLayerLanes: twirls.onToggleLayerLanes,
                expandedLaneGroupKeys: twirls.expandedLaneGroupKeys,
                onToggleLaneGroupKey: twirls.onToggleLaneGroupKey,
                laneGraphs: open,
                laneGraphVerbs: SessionRowButtonPresses(
                  session,
                ).laneGraphVerbs,
                pixelsPerFrame: 12,
                onPixelsPerFrameChanged: (_) {},
                showSeconds: false,
                onShowSecondsChanged: (_) {},
                thumbnails: null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Future<void> tap(WidgetTester tester, String name) async {
    await tester.tap(find.named(name));
    await tester.pumpAndSettle();
  }

  /// Presses [from] and walks the pointer to [to] — found afresh each step,
  /// as a row twirled or a graph opened slides every row under it — its
  /// down and first move in one frame.
  Future<void> sweep(WidgetTester tester, String from, String to) async {
    final start = tester.getCenter(find.named(from));
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    var at = start;
    for (var step = 0; step < 400; step += 1) {
      final gap = tester.getCenter(find.named(to)).dy - at.dy;
      if (gap.abs() < 1) {
        break;
      }
      at = Offset(start.dx, at.dy + gap.clamp(-8.0, 8.0));
      await gesture.moveTo(at);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Track track(EditorSessionManager session, TrackId id) => session.repository
      .requireProject()
      .tracks
      .firstWhere((track) => track.id == id);

  Layer row(EditorSessionManager session, String id) => [
    for (final track in session.repository.requireProject().tracks) ...[
      track.transitionLayer,
      ...track.seLayers,
      for (final cut in track.cuts) ...cut.layers,
    ],
  ].firstWhere((layer) => layer.id == LayerId(id));

  String transitionOf(EditorSessionManager session) =>
      '${track(session, t1).transitionLayer.id}';

  LayerFxState fx(EditorSessionManager session, String id) =>
      session.effectsAndFx.layerFxState(LayerId(id));

  testWidgets('🚨the EYE column paints the camera head — the row it stepped '
      'over — down to the conte head\'s', (tester) async {
    final session = await pump(tester);
    final eyed = ['a-cam', transitionOf(session), 't1-s1', 'a-conte'];
    expect(
      [for (final id in eyed) row(session, id).isVisible],
      everyElement(isTrue),
      reason: '⛔전제',
    );

    await sweep(
      tester,
      'storyboard-layer-visibility-a-cam',
      'storyboard-layer-visibility-a-conte',
    );

    expect(
      [for (final id in eyed) row(session, id).isVisible],
      everyElement(isFalse),
      reason:
          'the press hid the camera, and the sweep spread it down the rows '
          'it crossed — read off the camera in hand, as the press left it',
    );
  });

  testWidgets('🚨the FX column turns every switch it crosses — the camera\'s, '
      'the S row\'s, the TRACK\'s, each effect\'s on the V row\'s chain and '
      'the conte\'s', (tester) async {
    final session = await pump(tester);
    await tap(tester, 'storyboard-track-lane-toggle-t1');
    expect(
      [
        for (final id in ['a-cam', 't1-s1', 'a-conte']) fx(session, id),
        session.effectsAndFx.trackFxState(t1),
      ],
      everyElement(LayerFxState.on),
      reason: '⛔전제',
    );

    await sweep(
      tester,
      'storyboard-layer-fx-a-cam',
      'storyboard-layer-fx-a-conte',
    );

    expect(
      [
        for (final id in ['a-cam', 't1-s1', 'a-conte']) fx(session, id),
        session.effectsAndFx.trackFxState(t1),
      ],
      everyElement(LayerFxState.off),
    );
    expect(
      [for (final effect in track(session, t1).effects) effect.enabled],
      [false, false],
      reason:
          'the V row\'s lanes are its chain\'s effects, each header its '
          'effect\'s switch, pressed on the TRACK — the sweep crossed them '
          'between the V row and the conte',
    );
  });

  testWidgets('🚨a sweep can START on a lane group\'s switch — the V row\'s '
      'chain\'s first effect, read as the press left it', (tester) async {
    final session = await pump(tester);
    await tap(tester, 'storyboard-track-lane-toggle-t1');
    String header(EffectId effect) =>
        'storyboard-lane-group-fx-$carrier-${effectGroupLaneId(effect)}';

    await sweep(tester, header(effects.first), header(effects.last));

    expect(
      [for (final effect in track(session, t1).effects) effect.enabled],
      [false, false],
      reason:
          'the press bypassed the first, and the sweep the one under it — '
          'the header the press set read live, not as its row was built',
    );
  });

  testWidgets('🚨and on a projection row\'s — the conte\'s Transform, read off '
      'the conte in hand as the press left it', (tester) async {
    final session = await pump(tester);
    await tap(tester, 'storyboard-lane-toggle-a-conte');
    String header(String lane) => 'storyboard-lane-group-fx-$conteRow-$lane';

    await sweep(
      tester,
      header('transform-group'),
      header(effectGroupLaneId(shade)),
    );

    final conte = row(session, 'a-conte');
    expect(
      [conte.transformEnabled, conte.effects.single.enabled],
      [false, false],
      reason:
          'the press bypassed the Transform, and the sweep the effect under '
          'it — the row read by its layer in hand: by its own id the host '
          'finds no layer, and a stale read spreads what the press undid',
    );
  });

  testWidgets('⛔in a gap a projection row\'s group switches are inert — a '
      'press there starts no sweep', (tester) async {
    final session = await pump(tester);
    await tap(tester, 'storyboard-lane-toggle-a-conte');
    session.selectCut(const CutId('c'));
    await tester.pumpAndSettle();
    final header = 'storyboard-lane-group-fx-$conteRow-transform-group';
    expect(
      find.named(header),
      findsOneWidget,
      reason: 'the fixture: the row keeps its lanes with no cut stood in',
    );
    // The header reads on, so the row the sweep reaches starts off: a sweep
    // that started would turn it over. (🧪10-18: with the row on, a sweep
    // from here showed nothing either way.)
    await tap(tester, 'storyboard-layer-fx-t2-s1');
    expect(fx(session, 't2-s1'), LayerFxState.off, reason: '⛔전제');

    await sweep(tester, header, 'storyboard-layer-fx-t2-s1');

    expect(
      row(session, 'a-conte').transformEnabled,
      isTrue,
      reason: 'no cut of the row is stood in, so there is none to write',
    );
    expect(
      fx(session, 't2-s1'),
      LayerFxState.off,
      reason: 'and a switch a tap cannot press starts no sweep',
    );
  });

  testWidgets('🚨a projection row\'s group switch is swept on the layer of the '
      'cut stood in — crossed on its own, from the track under it', (
    tester,
  ) async {
    // From t2's S row UP to the conte's Transform header, so the conte
    // head is never crossed: its fx switch would turn the group with it.
    final session = await pump(tester);
    await tap(tester, 'storyboard-lane-toggle-a-conte');
    final header = 'storyboard-lane-group-fx-$conteRow-transform-group';
    expect(find.named(header), findsOneWidget, reason: 'the fixture');
    expect(row(session, 'a-conte').transformEnabled, isTrue, reason: '⛔전제');

    await sweep(tester, 'storyboard-layer-fx-t2-s1', header);

    expect(fx(session, 't2-s1'), LayerFxState.off, reason: 'the press');
    expect(
      row(session, 'a-conte').transformEnabled,
      isFalse,
      reason: 'the header the sweep reached, turned on the conte in hand',
    );
  });

  testWidgets('🚨the TWIRL column opens every row\'s lanes it crosses — the '
      'camera\'s, the S row\'s, the V row\'s and the conte head\'s', (
    tester,
  ) async {
    final session = await pump(tester);
    List<bool> open() => [
      for (final id in [const LayerId('a-cam'), const LayerId('t1-s1')])
        session.layerSwitches.isLayerLanesOpen(id),
      session.layerSwitches.isLayerLanesOpen(carrier),
      session.layerSwitches.isLayerLanesOpen(const LayerId('a-conte')),
    ];
    expect(open(), everyElement(isFalse), reason: '⛔전제');

    await sweep(
      tester,
      'storyboard-lane-toggle-a-cam',
      'storyboard-lane-toggle-a-conte',
    );

    expect(
      open(),
      everyElement(isTrue),
      reason:
          '↩️the conte head\'s twirl was the one its rail\'s own list never '
          'swept, and the camera row was stepped over whole',
    );
  });

  testWidgets('🚨the GRAPH column opens every graph it crosses — the camera '
      'head\'s, each effect header\'s on the V row and the conte\'s', (
    tester,
  ) async {
    final session = await pump(tester);
    await tap(tester, 'storyboard-track-lane-toggle-t1');
    await tap(tester, 'storyboard-lane-toggle-a-conte');
    final keys = [
      'a-cam|transform-group',
      for (final effect in effects) '$carrier|${effectGroupLaneId(effect)}',
      'a-conte|transform-group',
    ];
    expect(
      session.railView.laneGraphs.value.open.keys.where(keys.contains),
      isEmpty,
      reason: '⛔전제',
    );

    await sweep(
      tester,
      'storyboard-layer-graph-a-cam',
      'storyboard-lane-group-graph-$conteRow-transform-group',
    );

    expect(
      session.railView.laneGraphs.value.open.keys,
      containsAll(keys),
      reason:
          'each graph by the layer it heads in — the conte\'s and the '
          'camera\'s their layers in hand, as the rows\' own buttons turn them',
    );
  });

  testWidgets('🚨the PIN column pins every member lane it crosses', (
    tester,
  ) async {
    final session = await pump(tester);
    await tap(tester, 'storyboard-lane-toggle-a-conte');
    await tap(tester, 'storyboard-lane-group-toggle-$conteRow-transform-group');
    final pins = 'storyboard-lane-pin-$conteRow-';
    double topOf(String name) => tester.getCenter(find.named(name)).dy;
    final members = [
      for (final element in find
          .namedWhere((name) => name.startsWith(pins))
          .evaluate())
        nameOf(element)!,
    ]..sort((a, b) => topOf(a).compareTo(topOf(b)));
    expect(members.length, greaterThan(2), reason: 'the fixture');
    expect(session.railView.laneGraphs.value.pinned, isEmpty, reason: '⛔전제');

    await sweep(tester, members.first, members.last);

    expect(
      session.railView.laneGraphs.value.pinned,
      containsAll([
        for (final pin in members) 'a-conte|${pin.substring(pins.length)}',
      ]),
      reason: 'each by the layer in hand, as the pins\' own buttons press it',
    );
  });

  testWidgets('⛔the V row draws a twirl only while its track has lanes, as '
      'every row does — the twirl the sweep paints', (tester) async {
    await pump(tester);
    expect(
      find.named('storyboard-track-lane-toggle-t1'),
      findsOneWidget,
      reason: 't1 has a chain of two effects to twirl down',
    );
    expect(
      find.named('storyboard-track-lane-toggle-t2'),
      findsNothing,
      reason:
          '↩️it stood on a track with none, turning nothing — a button the '
          'sweep, by the timeline rows\' law, could not paint',
    );
  });

  testWidgets('⛔the SHEET column passes the projection heads by — they are '
      'handed no toggle (I-89-Q22)', (tester) async {
    final session = await pump(tester);
    for (final head in ['a-cam', 'a-conte']) {
      expect(
        find.named('storyboard-layer-timesheet-$head'),
        findsNothing,
        reason: '「시트토글은 카메라는 로컬기록이니까 없음」',
      );
    }
    final sheeted = [transitionOf(session), 'a-cam', 't2-s1', 'a-conte'];
    expect(
      [for (final id in sheeted) row(session, id).onTimesheet],
      everyElement(isTrue),
      reason: '⛔전제',
    );

    // Up from the S row over the transition row to the camera head, and up
    // from t2's S row to t1's conte head: each stroke crosses a head.
    await sweep(
      tester,
      'storyboard-layer-timesheet-t1-s1',
      'storyboard-layer-visibility-a-cam',
    );
    await sweep(
      tester,
      'storyboard-layer-timesheet-t2-s1',
      'storyboard-layer-visibility-a-conte',
    );

    expect(
      [for (final id in sheeted) row(session, id).onTimesheet],
      [false, true, false, true],
      reason:
          'the presses\' rows and the transition row went off the sheet; '
          'the heads the strokes crossed kept theirs',
    );
  });
}
