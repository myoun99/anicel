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
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/lane_graph.dart';
import 'package:anicel/src/ui/timeline/lane_graph_toggle.dart'
    show LaneGraphToggle;
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show TimelineRowDragHooks;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show TimelineGridSheet;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart'
    show TimelineLaneGraph;
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneControlsRow;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/conte_track_fixture.dart';
import '../../helpers/home_page_probes.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_twirls.dart';

/// **I-89 ① — the conte panel draws the timeline's header graphs.**
///
/// 🗣️유저 2026-10-13: everything the timeline panel has, the conte panel
/// has, by the same law and the same code. A group's graph is the
/// timeline's own state ([LaneGraphsView]) turned by the timeline's own
/// verbs ([SessionRowButtonPresses.laneGraphVerbs]), seated and laid by the
/// timeline's own functions — so an S row's or a V row's graph stands in
/// the conte where its lanes are, as tall as on the timeline.
void main() {
  const trackId = TrackId('track');
  const s1 = LayerId('s1');
  const s2 = LayerId('s2');
  const blur = EffectId('blur');
  const hue = EffectId('hue');
  final transform = transformGroupHeaderLane.laneId;
  final carrier = trackTransformLaneCarrierId(trackId);

  /// An S row twirled open — to its Transform group's members, unless
  /// [shut] (F-360: the row keeps its twirls).
  Layer seLayer(LayerId id, {bool shut = false}) => Layer(
    id: id,
    name: id.value,
    kind: LayerKind.se,
    frames: [
      Frame(id: FrameId('${id.value}-f'), duration: 8, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(FrameId('${id.value}-f'), length: 8),
    },
    lanesExpanded: true,
    expandedLaneGroups: {if (!shut) transform},
  );

  Project project({
    List<Layer>? seLayers,
    List<LayerEffect> effects = const [],
    bool lanesExpanded = false,
    Set<String> expandedLaneGroups = const {},
  }) => Project(
    id: const ProjectId('project'),
    name: 'Graphs',
    createdAt: DateTime.utc(2026, 10, 16),
    tracks: [
      Track(
        id: trackId,
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut'),
            name: 'Cut',
            duration: 24,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: const [],
          ),
        ],
        seLayers: seLayers ?? [seLayer(s1)],
        effects: effects,
        lanesExpanded: lanesExpanded,
        expandedLaneGroups: expandedLaneGroups,
      ),
    ],
  );

  /// The panel over a session holding [project], wired as the workspace
  /// wires it: the rows' twirls ([withStoryboardTwirls]) and the header
  /// graphs, the timeline's state turned by the timeline's verbs — and,
  /// with [dragRows], the session's own row drags.
  Future<EditorSessionManager> pump(
    WidgetTester tester,
    Project project, {
    LaneGraphsView graphs = LaneGraphsView.none,
    ValueListenable<List<TimelineRowAddress>>? rowSelection,
    bool dragRows = false,
  }) async {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    session.railView.laneGraphs.value = graphs;
    final presses = SessionRowButtonPresses(session);
    final drags = session.layerRowDragVerbs;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: withStoryboardTwirls(
            session,
            (twirls) => ValueListenableBuilder<LaneGraphsView>(
              valueListenable: session.railView.laneGraphs,
              builder: (context, graphs, _) => StoryboardPanel(
                project: session.repository.requireProject(),
                activeCutId: const CutId('cut'),
                pixelsPerFrame: 12,
                projectFrameRate: ProjectFrameRate.fps24,
                expandedLaneLayerIds: twirls.expandedLaneLayerIds,
                onToggleLayerLanes: twirls.onToggleLayerLanes,
                expandedLaneGroupKeys: twirls.expandedLaneGroupKeys,
                onToggleLaneGroupKey: twirls.onToggleLaneGroupKey,
                layerLanesOpenOf: twirls.layerLanesOpenOf,
                poseDisplaySize: const CanvasSize(width: 640, height: 360),
                rowSelection: rowSelection,
                laneGraphs: graphs,
                laneGraphVerbs: presses.laneGraphVerbs,
                rowDragHooks: dragRows
                    ? TimelineRowDragHooks(
                        drag: drags.inFlight,
                        onBegin: drags.beginLayerRowDrag,
                        onUpdate: drags.updateLayerRowDrag,
                        onRowTarget: drags.updateLayerRowDropOnRow,
                        onEffectUpdate: drags.updateEffectRowDrag,
                        onEnd: drags.endLayerRowDrag,
                        onCancel: drags.cancelLayerRowDrag,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Finder graphOf(String key) =>
      find.byKey(ValueKey<String>('storyboard-lane-graph-$key'));

  Finder labelOf(LayerId layerId, String laneId) => find.byWidgetPredicate(
    (widget) =>
        widget is TimelineLaneControlsRow &&
        widget.layer.id == layerId &&
        widget.lane.laneId == laneId,
  );

  List<({LayerId layer, String lane})> linesOf(
    WidgetTester tester,
    String key, {
    bool guests = false,
  }) {
    final lines = tester.widget<TimelineLaneGraph>(graphOf(key)).lines;
    return [
      for (final line in guests ? lines.guests() : lines.own())
        (layer: line.layer.id, lane: line.lane.laneId),
    ];
  }

  testWidgets('an S row\'s open graph stands where its lanes are, as tall '
      'as the timeline\'s — the rail and the sheet stand as far beside it', (
    tester,
  ) async {
    final key = laneGroupKey(s1, transform);
    await pump(
      tester,
      project(),
      graphs: LaneGraphsView(open: {key: const LaneGraph()}),
    );

    final laneHeight = tester.getSize(labelOf(s1, transform)).height;
    final extent = const LaneGraph().extentAt(laneHeight);
    expect(graphOf(key), findsOneWidget);
    // Seven rows tall as it opens ([laneGraphOpeningRows]): its lanes and
    // the room after them, ONE picture.
    expect(tester.getSize(graphOf(key)).height, extent);
    // It stands from its first member, under the header that heads it.
    expect(
      tester.getTopLeft(graphOf(key)).dy,
      tester.getBottomLeft(labelOf(s1, transform)).dy,
    );
    // And the rail stands as far: the V row under the S row starts where
    // the graph ends, on both sides.
    expect(
      tester.getTopLeft(find.byType(StoryboardTrackLabelRow)).dy,
      tester.getBottomLeft(graphOf(key)).dy,
    );
    // The sheet rules it as ONE row: no seam runs through its picture.
    final sheet = tester.widget<TimelineGridSheet>(
      find.byKey(const ValueKey<String>('storyboard-grid-sheet')),
    );
    expect([for (final row in sheet.rows.rows) row.extent], contains(extent));
  });

  testWidgets('the S header\'s graph button is the timeline\'s: it opens '
      'and shuts the group\'s graph, and reads it so', (tester) async {
    final key = laneGroupKey(s1, transform);
    final session = await pump(tester, project());
    final button = find.named(
      'storyboard-lane-group-graph-${s1.value}-$transform',
    );
    bool lit() => tester
        .widget<LaneGraphToggle>(
          find.ancestor(of: button, matching: find.byType(LaneGraphToggle)),
        )
        .on;
    expect(graphOf(key), findsNothing);
    expect(lit(), isFalse);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(session.railView.laneGraphs.value.open.keys, contains(key));
    expect(graphOf(key), findsOneWidget);
    expect(lit(), isTrue);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(session.railView.laneGraphs.value.open.keys, isNot(contains(key)));
    expect(graphOf(key), findsNothing);
  });

  testWidgets('a V row\'s fx header opens its graph and its group with it, '
      'as a layer\'s does', (tester) async {
    final header = effectGroupLaneId(blur);
    final key = laneGroupKey(carrier, header);
    final session = await pump(
      tester,
      project(
        effects: [LayerEffect.defaults(id: blur, kind: EffectKind.blur)],
        lanesExpanded: true,
      ),
    );
    expect(
      session.repository.requireProject().tracks.single.expandedLaneGroups,
      isNot(contains(header)),
    );

    await tester.tap(
      find.named('storyboard-lane-group-graph-${carrier.value}-$header'),
    );
    await tester.pumpAndSettle();
    // ↩️The graph opened over a shut group: the twirl was asked of a layer,
    // and the V row's lane carrier is none.
    expect(
      session.repository.requireProject().tracks.single.expandedLaneGroups,
      contains(header),
    );
    expect(graphOf(key), findsOneWidget);
  });

  testWidgets('an enlarged graph folds every other lane of the conte to a '
      'thin strip, rail and strips alike, and stands as far as the view '
      'lets one', (tester) async {
    final key = laneGroupKey(s1, transform);
    await pump(
      tester,
      project(seLayers: [seLayer(s1), seLayer(s2)]),
      graphs: LaneGraphsView(open: {key: const LaneGraph(enlarged: true)}),
    );

    final laneHeight = tester.getSize(labelOf(s1, transform)).height;
    // Another row's member lane: its label and its strip, thin — its plate
    // alone.
    expect(
      tester.getSize(labelOf(s2, 'position')).height,
      laneGraphFoldedExtent,
    );
    expect(
      tester.widget<TimelineLaneControlsRow>(labelOf(s2, 'position')).folded,
      isTrue,
    );
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('storyboard-se-lane-row-0-2-position'),
            ),
          )
          .height,
      laneGraphFoldedExtent,
    );
    // Its header stands whole, as every header does.
    expect(tester.getSize(labelOf(s2, transform)).height, laneHeight);
    // The enlarged graph and its header fill the rows' view.
    final view = tester
        .getSize(
          find.byKey(const ValueKey<String>('storyboard-vertical-viewport')),
        )
        .height;
    expect(
      tester.getSize(graphOf(key)).height,
      laneGraphMostExtent(view, laneHeight),
    );
  });

  testWidgets('another open graph the enlarged one folds stands as its '
      'first lane\'s strip — its other lanes stand nowhere', (tester) async {
    final enlarged = laneGroupKey(s1, transform);
    final folded = laneGroupKey(s2, transform);
    await pump(
      tester,
      project(seLayers: [seLayer(s1), seLayer(s2)]),
      graphs: LaneGraphsView(
        open: {
          enlarged: const LaneGraph(enlarged: true),
          folded: const LaneGraph(),
        },
      ),
    );

    // Its first member's label is the strip; the rest build nothing.
    expect(
      tester.getSize(labelOf(s2, 'anchor-point')).height,
      laneGraphFoldedExtent,
    );
    expect(labelOf(s2, 'scale'), findsNothing);
    // And the strip side draws it as the empty strip, no picture.
    expect(graphOf(folded), findsNothing);
  });

  testWidgets('what a graph draws follows the row selection, which the conte '
      'draws without building its rows again', (tester) async {
    final key = laneGroupKey(s1, transform);
    final selection = ValueNotifier<List<TimelineRowAddress>>(const []);
    addTearDown(selection.dispose);
    await pump(
      tester,
      project(),
      graphs: LaneGraphsView(open: {key: const LaneGraph()}),
      rowSelection: selection,
    );

    List<String> drawn() => [
      for (final line in linesOf(tester, key)) line.lane,
    ];
    List<String> pickedOn(String laneId) =>
        tester
            .widget<TimelineLaneControlsRow>(labelOf(s1, laneId))
            .seat!
            .picked;

    // Nothing picked, stood nowhere: the whole group.
    expect(drawn(), containsAll(['position', 'scale', 'rotation']));
    expect(pickedOn('scale'), isEmpty);

    selection.value = const [LaneRowAddress(s1, 'position')];
    await tester.pump();
    expect(drawn(), ['position']);
    expect(pickedOn('scale'), ['position']);
  });

  testWidgets('a pinned lane of another row is a guest in every open graph '
      '— an S row\'s and the V row\'s, their groups shut', (tester) async {
    final key = laneGroupKey(s1, transform);
    final blurX = effectLaneId(blur, 'blurX');
    await pump(
      tester,
      project(
        seLayers: [seLayer(s1), seLayer(s2, shut: true)],
        effects: [LayerEffect.defaults(id: blur, kind: EffectKind.blur)],
      ),
      graphs: LaneGraphsView(
        open: {key: const LaneGraph()},
        pinned: {laneGroupKey(s2, 'rotation'), laneGroupKey(carrier, blurX)},
      ),
    );

    expect(
      linesOf(tester, key, guests: true),
      unorderedEquals([
        (layer: s2, lane: 'rotation'),
        (layer: carrier, lane: blurX),
      ]),
    );
  });

  testWidgets('an fx header dragged into an open graph\'s room stays where '
      'it is: the room is no row (I-89 ③)', (tester) async {
    final header = effectGroupLaneId(blur);
    final session = await pump(
      tester,
      project(
        effects: [
          LayerEffect.defaults(id: blur, kind: EffectKind.blur),
          LayerEffect.defaults(id: hue, kind: EffectKind.hueSaturation),
        ],
        lanesExpanded: true,
        expandedLaneGroups: {header},
      ),
      graphs: LaneGraphsView(
        open: {laneGroupKey(carrier, header): const LaneGraph()},
      ),
      dragRows: true,
    );
    List<EffectId> chain() => [
      for (final effect
          in session.repository.requireProject().tracks.single.effects)
        effect.id,
    ];
    final first = labelOf(carrier, header);
    final next = labelOf(carrier, effectGroupLaneId(hue));
    final lastMember = tester
        .getBottomLeft(labelOf(carrier, effectLaneId(blur, 'blurY')))
        .dy;
    final from = tester.getCenter(first);

    // Into the middle of the room: the gap before the next header, where
    // the chain already is.
    final room = (lastMember + tester.getTopLeft(next).dy) / 2;
    await tester.dragFrom(from, Offset(0, room - from.dy));
    await tester.pumpAndSettle();
    expect(chain(), [blur, hue]);

    // Past the next header's middle: that IS a move — the drag is live.
    final past = tester.getCenter(next).dy + 4;
    await tester.dragFrom(from, Offset(0, past - from.dy));
    await tester.pumpAndSettle();
    expect(chain(), [hue, blur]);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('through the app: a graph opened by the timeline\'s verb '
      'stands in the conte panel, its button the conte\'s own', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: conteTrackProject())),
    );
    await tester.pumpAndSettle();
    await showStoryboardPanel(tester);
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final presses = SessionRowButtonPresses(session);
    final key = laneGroupKey(conteSeId, transform);

    presses.toggleLanes(conteSeId);
    await tester.pumpAndSettle();
    expect(
      find.named('storyboard-lane-group-graph-${conteSeId.value}-$transform'),
      findsOneWidget,
    );
    presses.toggleLaneGraph(key);
    await tester.pumpAndSettle();
    expect(graphOf(key), findsOneWidget);
  });
}
