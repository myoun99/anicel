import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
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
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';

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

  /// [riders]: a row rides the conte, so the conte head folds.
  Cut cutOf(String id, {bool projections = true, bool riders = false}) => Cut(
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
        if (riders)
          Layer(
            id: LayerId('$id-over'),
            name: 'Conte+1',
            kind: LayerKind.storyboard,
            attachedToLayerId: LayerId('$id-conte'),
            attachedPlacement: AttachedPlacement.above,
            attachedMode: AttachedMode.free,
            frames: const [],
            timeline: const {},
          ),
      ],
    ],
  );

  /// [conteOnT2]: t2's cut holds a camera and a conte of its own too.
  Project film({bool conteOnT2 = false, bool riders = false}) => Project(
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
        cuts: [
          cutOf('a', riders: riders),
          cutOf('b', riders: riders),
        ],
      ),
      Track(
        id: const TrackId('t2'),
        name: 'V2',
        seLayers: [se('t2-s1')],
        cuts: [cutOf('c', projections: conteOnT2, riders: riders)],
      ),
    ],
  );

  Future<EditorSessionManager> pump(
    WidgetTester tester, {
    bool conteOnT2 = false,
    bool riders = false,
  }) => pumpStoryboardHost(
    tester,
    film(conteOnT2: conteOnT2, riders: riders),
    surface: const Size(1600, 1400),
    pixelsPerFrame: 12,
  );

  Future<void> tap(WidgetTester tester, String name) async {
    await tester.tap(find.named(name));
    await tester.pumpAndSettle();
  }

  /// Presses [from] and walks the pointer to [to] — found afresh each step,
  /// as a row twirled or a graph opened slides every row under it — its
  /// down and first move in one frame. Finders, for a button keyed rather
  /// than named, as a lane's ◆ is ([sweep] takes names).
  Future<void> sweepBetween(WidgetTester tester, Finder from, Finder to) async {
    final start = tester.getCenter(from);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    var at = start;
    for (var step = 0; step < 400; step += 1) {
      final gap = tester.getCenter(to).dy - at.dy;
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

  /// [sweepBetween] the buttons named [from] and [to].
  Future<void> sweep(WidgetTester tester, String from, String to) =>
      sweepBetween(tester, find.named(from), find.named(to));

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

  // 🗣️F-475 (유저 2026-10-26): 「다른버튼도 조사」 — the folds are toggle
  // columns the timeline's rail sweeps, and this rail sweeps its one list.
  testWidgets('🚨the GROUP TWIRL column opens every lane group it crosses — '
      'the V row\'s on its TRACK, the conte\'s on the conte in hand', (
    tester,
  ) async {
    final session = await pump(tester);
    await tap(tester, 'storyboard-track-lane-toggle-t1');
    await tap(tester, 'storyboard-lane-toggle-a-conte');
    String twirl(LayerId row, String lane) =>
        'storyboard-lane-group-toggle-$row-$lane';
    // The conte's effect group stands open before the stroke: the sweep
    // crosses it agreeing, and leaves it be.
    await tap(tester, twirl(conteRow, effectGroupLaneId(shade)));
    final alreadyOpen = laneGroupKey(
      const LayerId('a-conte'),
      effectGroupLaneId(shade),
    );
    final keys = [
      for (final effect in effects)
        laneGroupKey(carrier, effectGroupLaneId(effect)),
      laneGroupKey(const LayerId('a-conte'), 'transform-group'),
      alreadyOpen,
    ];
    expect(
      session.railView.expandedLaneGroupKeys.value.where(keys.contains),
      [alreadyOpen],
      reason: '⛔전제',
    );

    // Down to the conte's Transform, the last group: its effect stands
    // over it.
    await sweep(
      tester,
      twirl(carrier, effectGroupLaneId(effects.first)),
      twirl(conteRow, 'transform-group'),
    );

    expect(
      session.railView.expandedLaneGroupKeys.value,
      containsAll(keys),
      reason:
          'each group by the row it twirls in, as its own twirl turns it — '
          'the press read as it left the group: a stale read spreads shut; '
          'the open one read off the conte in hand: by its own id the host '
          'finds no row, reads it shut and shuts it',
    );
  });

  testWidgets('🚨the FOLD column folds every conte head it crosses, on to the '
      'next track\'s — read off the conte in hand as the press left it', (
    tester,
  ) async {
    final session = await pump(tester, conteOnT2: true, riders: true);
    Set<LayerId> folded() => session.railView.collapsedAttachBaseIds.value;
    expect(folded(), isEmpty, reason: '⛔전제');

    await sweep(
      tester,
      'storyboard-attach-twirl-a-conte',
      'storyboard-attach-twirl-c-conte',
    );

    expect(
      folded(),
      containsAll(const [
        LayerId('a-conte'),
        LayerId('b-conte'),
        LayerId('c-conte'),
      ]),
      reason:
          'the press folded t1\'s head — cut b\'s group with cut a\'s — and '
          'the sweep the head it reached: by its own id the host finds no '
          'layer, and the sweep would spread the fold open',
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

  testWidgets('⛔the SHEET column passes the camera head by — it is handed no '
      'toggle — and turns the conte head\'s, one for the track\'s cuts '
      '(I-89-Q22)', (tester) async {
    final session = await pump(tester);
    expect(
      find.named('storyboard-layer-timesheet-a-cam'),
      findsNothing,
      reason: '「시트토글은 카메라는 로컬기록이니까 없음」',
    );
    expect(
      find.named('storyboard-layer-timesheet-a-conte'),
      findsOneWidget,
      reason: '「콘티행은 그런부분 글로벌이니까 아니면 글로벌시키고 넣고 머리로 하나」',
    );
    final sheeted = [
      transitionOf(session),
      'a-cam',
      't2-s1',
      'a-conte',
      'b-conte',
    ];
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
      [false, true, false, false, false],
      reason:
          'the presses\' rows and the transition row went off the sheet, '
          'and the conte head — every cut\'s conte with it; the camera head '
          'the first stroke crossed kept its',
    );
  });

  testWidgets('🚨the ONION column turns the conte head\'s onion — every cut\'s '
      'conte ghosts — and the conte head\'s own button does too '
      '(I-89-Q22)', (tester) async {
    final session = await pump(tester);
    bool ghosts(String id) =>
        session.onionSkin.isLayerOnionSkinEnabled(LayerId(id));
    expect(
      find.named('storyboard-layer-onion-a-cam'),
      findsNothing,
      reason: 'a camera cannot ghost: its slot stays empty',
    );

    String onionTip() => tester
        .widget<RailGlyphButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is RailGlyphButton &&
                widget.name == 'storyboard-layer-onion-a-conte',
          ),
        )
        .tooltip;
    expect(onionTip(), AppText.strings.railOnionSkin, reason: '⛔전제');

    await tap(tester, 'storyboard-layer-onion-a-conte');
    expect(
      [ghosts('a-conte'), ghosts('b-conte')],
      [true, true],
      reason: '「어니언도 콘티행 기본적으로 버튼 글로벌이니까 넣음」',
    );
    expect(onionTip(), AppText.strings.railOnionSkinOn, reason: 'it lights');

    // Down from the conte head's onion over the S row and the V row: the
    // press turns it off, and nothing it crossed can ghost.
    await sweep(
      tester,
      'storyboard-layer-onion-a-conte',
      'storyboard-layer-visibility-t1-s1',
    );
    expect([ghosts('a-conte'), ghosts('b-conte')], [false, false]);
    expect(session.onionSkin.layerIds.value, isEmpty);
  });

  testWidgets('🚨the ONION column sweeps on to the next track\'s conte head, '
      'read off the conte in hand as the press left it', (tester) async {
    final session = await pump(tester, conteOnT2: true);
    bool ghosts(String id) =>
        session.onionSkin.isLayerOnionSkinEnabled(LayerId(id));
    expect(
      find.named('storyboard-layer-onion-c-conte'),
      findsOneWidget,
      reason: 'the fixture: t2\'s head wears its cut\'s conte',
    );
    expect([ghosts('a-conte'), ghosts('c-conte')], [false, false]);

    await sweep(
      tester,
      'storyboard-layer-onion-a-conte',
      'storyboard-layer-onion-c-conte',
    );

    expect(
      [ghosts('a-conte'), ghosts('b-conte'), ghosts('c-conte')],
      [true, true, true],
      reason:
          'the press turned t1\'s head on, and the sweep the head it reached '
          '— the start read by the conte in hand: by its own id the host finds '
          'no row, and the sweep would spread off',
    );
  });

  // 🗣️F-475 (유저 2026-10-26): 「다른버튼도 조사」 — a lane's ◆ is a toggle
  // column too, pressed on each lane as the lane's own ◆ presses it.
  group('the ◆ column', () {
    /// Stands in cut b at its own frame 3 — a frame the global playhead
    /// does not name, so a lane keyed on the wrong one shows.
    Future<int> standInB(
      EditorSessionManager session,
      WidgetTester tester,
    ) async {
      session.selectCut(const CutId('b'));
      session.selectFrameIndex(3);
      await tester.pumpAndSettle();
      final global = session.activeCutGlobalStartFrame + 3;
      expect(global, isNot(3), reason: '⛔전제: b starts after frame 0');
      return global;
    }

    Finder diamond(LayerId row, String lane) =>
        find.byKey(ValueKey<String>('storyboard-lane-key-toggle-$row-$lane'));

    testWidgets('🚨it keys every lane of the V row it crosses on its TRACK, at '
        'the global playhead — past the effect header between', (
      tester,
    ) async {
      final session = await pump(tester);
      final global = await standInB(session, tester);
      await tap(tester, 'storyboard-track-lane-toggle-t1');
      for (final effect in effects) {
        await tap(
          tester,
          'storyboard-lane-group-toggle-$carrier-${effectGroupLaneId(effect)}',
        );
      }

      await sweepBetween(
        tester,
        diamond(carrier, effectLaneId(effects.first, 'blurX')),
        diamond(carrier, effectLaneId(effects.last, 'blurY')),
      );

      expect(
        [
          for (final effect in track(session, t1).effects)
            for (final parameter in ['blurX', 'blurY'])
              [...effect.parameterOf(parameter).track.keys.keys],
        ],
        [
          for (var lane = 0; lane < 4; lane += 1) [global],
        ],
      );
    });

    testWidgets('🚨it keys a projection row\'s lanes on the layer of the cut '
        'stood in, at that cut\'s own frame', (tester) async {
      final session = await pump(tester);
      await standInB(session, tester);
      await tap(tester, 'storyboard-lane-toggle-b-conte');
      await tap(
        tester,
        'storyboard-lane-group-toggle-$conteRow-transform-group',
      );

      await sweepBetween(
        tester,
        diamond(conteRow, 'position'),
        diamond(conteRow, 'rotation'),
      );

      Map<String, List<int>> keysOf(String id) {
        final track = row(session, id).transformTrack;
        return {
          'position': [...track.position.keys.keys],
          'scale': [...track.scale.keys.keys],
          'rotation': [...track.rotation.keys.keys],
        };
      }

      expect(keysOf('b-conte'), {
        'position': [3],
        'scale': [3],
        'rotation': [3],
      }, reason: 'b\'s own 3');
      expect(keysOf('a-conte'), {
        'position': <int>[],
        'scale': <int>[],
        'rotation': <int>[],
      });
    });

    testWidgets('⛔in a gap a projection row\'s ◆ is inert — a press there '
        'starts no sweep', (tester) async {
      final session = await pump(tester);
      await tap(tester, 'storyboard-lane-toggle-a-conte');
      await tap(
        tester,
        'storyboard-lane-group-toggle-$conteRow-transform-group',
      );
      await tap(tester, 'storyboard-lane-toggle-t2-s1');
      await tap(tester, 'storyboard-lane-group-toggle-t2-s1-transform-group');
      session.selectCut(const CutId('c'));
      await tester.pumpAndSettle();
      final start = diamond(conteRow, 'position');
      expect(
        start,
        findsOneWidget,
        reason: 'the fixture: the row keeps its lanes with no cut stood in',
      );

      await sweepBetween(
        tester,
        start,
        diamond(const LayerId('t2-s1'), 'position'),
      );

      expect(
        [...row(session, 't2-s1').transformTrack.position.keys.keys],
        isEmpty,
        reason:
            'no cut of the row is stood in, so its ◆ has nothing to key — '
            'and a ◆ a tap cannot press starts no sweep',
      );
    });
  });
}
