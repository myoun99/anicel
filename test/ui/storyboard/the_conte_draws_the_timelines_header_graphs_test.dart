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
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/timeline/lane_graph.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart'
    show TimelineLaneGraph;
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneControlsRow;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  final transform = transformGroupHeaderLane.laneId;
  final carrier = trackTransformLaneCarrierId(trackId);

  Layer seLayer(LayerId id) => Layer(
    id: id,
    name: id.value,
    kind: LayerKind.se,
    frames: [
      Frame(id: FrameId('${id.value}-f'), duration: 8, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(FrameId('${id.value}-f'), length: 8),
    },
    // Twirled open to the Transform group's members, as the row keeps it
    // (F-360).
    lanesExpanded: true,
    expandedLaneGroups: {transform},
  );

  Project project({
    List<Layer>? seLayers,
    List<LayerEffect> effects = const [],
    bool lanesExpanded = false,
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
      ),
    ],
  );

  /// The panel over a session holding [project], wired as the workspace
  /// wires it: the rows' twirls ([withStoryboardTwirls]) and the header
  /// graphs, the timeline's state turned by the timeline's verbs.
  Future<EditorSessionManager> pump(
    WidgetTester tester,
    Project project, {
    LaneGraphsView graphs = LaneGraphsView.none,
    ValueListenable<List<TimelineRowAddress>>? rowSelection,
  }) async {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    session.railView.laneGraphs.value = graphs;
    final presses = SessionRowButtonPresses(session);
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

  testWidgets('an S row\'s open graph stands where its lanes are, as tall '
      'as the timeline\'s, and the rail stands as far beside it', (
    tester,
  ) async {
    final key = laneGroupKey(s1, transform);
    await pump(
      tester,
      project(),
      graphs: LaneGraphsView(open: {key: const LaneGraph()}),
    );

    final laneHeight = tester.getSize(labelOf(s1, transform)).height;
    expect(graphOf(key), findsOneWidget);
    // Seven rows tall as it opens ([laneGraphOpeningRows]): its lanes and
    // the room after them, ONE picture.
    expect(
      tester.getSize(graphOf(key)).height,
      const LaneGraph().extentAt(laneHeight),
    );
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
  });

  testWidgets('the S header\'s graph button is the timeline\'s: it opens '
      'and shuts the group\'s graph', (tester) async {
    final key = laneGroupKey(s1, transform);
    final session = await pump(tester, project());
    final button = find.named(
      'storyboard-lane-group-graph-${s1.value}-$transform',
    );
    expect(graphOf(key), findsNothing);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(session.railView.laneGraphs.value.open.keys, contains(key));
    expect(graphOf(key), findsOneWidget);

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
    // Another row's member lane: its label and its strip, thin.
    expect(
      tester.getSize(labelOf(s2, 'position')).height,
      laneGraphFoldedExtent,
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
      for (final line
          in tester.widget<TimelineLaneGraph>(graphOf(key)).lines.own())
        line.lane.laneId,
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
}
