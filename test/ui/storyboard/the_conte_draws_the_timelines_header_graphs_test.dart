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
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart'
    show TimelineLaneSelection;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart'
    show trackCameraRowId;
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/models/working_panel.dart';
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
import 'package:anicel/src/ui/timeline/session_lane_callbacks.dart'
    show sessionLaneEditCallbacks;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show TimelineGridSheet;
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart'
    show LaneEditPreview, TimelineDragPreview;
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart'
    show TimelineLaneRangeHooks;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart'
    show
        LaneGraphPicture,
        TimelineLaneGraph,
        TimelineLaneGraphPainter,
        laneGraphAcross,
        laneGraphAlong;
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneControlsRow, TimelineLaneFrameRow, TimelineLaneKeyMarker;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

  /// One track of one cut, its [cutLayers] — S rows [seLayers], the V row
  /// carrying [effects], twirled as [lanesExpanded] and
  /// [expandedLaneGroups] say.
  Project project({
    List<Layer>? seLayers,
    List<LayerEffect> effects = const [],
    bool lanesExpanded = false,
    Set<String> expandedLaneGroups = const {},
    List<Layer> cutLayers = const [],
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
            layers: cutLayers,
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
  /// with [dragRows], the session's own row drags; with [laneEdits], the
  /// session's own lane edits, as the host hands the S and V rows theirs;
  /// an edit in flight on [dragPreview]; a frame [pixelsPerFrame] wide.
  Future<EditorSessionManager> pump(
    WidgetTester tester,
    Project project, {
    LaneGraphsView graphs = LaneGraphsView.none,
    ValueListenable<List<TimelineRowAddress>>? rowSelection,
    bool dragRows = false,
    bool laneEdits = false,
    ValueListenable<TimelineDragPreview?>? dragPreview,
    double pixelsPerFrame = 12,
    TimelineLaneRangeHooks? laneRange,
  }) async {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    session.railView.laneGraphs.value = graphs;
    final presses = SessionRowButtonPresses(session);
    final drags = session.layerRowDragVerbs;
    final edits = laneEdits
        ? sessionLaneEditCallbacks(
            session,
            frameIsGlobal: true,
            transformOptions: null,
          )
        : null;
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
                pixelsPerFrame: pixelsPerFrame,
                projectFrameRate: ProjectFrameRate.fps24,
                expandedLaneLayerIds: twirls.expandedLaneLayerIds,
                onToggleLayerLanes: twirls.onToggleLayerLanes,
                expandedLaneGroupKeys: twirls.expandedLaneGroupKeys,
                onToggleLaneGroupKey: twirls.onToggleLaneGroupKey,
                layerLanesOpenOf: twirls.layerLanesOpenOf,
                poseDisplaySize: const CanvasSize(width: 640, height: 360),
                rowSelection: rowSelection,
                dragPreview: dragPreview,
                laneRange: laneRange,
                laneGraphs: graphs,
                laneGraphVerbs: presses.laneGraphVerbs,
                layerLaneEdit: edits,
                trackLaneEditFor: edits == null ? null : (_) => edits,
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

  // 🗣️F-514 (유저 2026-10-30): a graph shows what it picked itself.
  testWidgets('🎯a lane in an open graph wears no band, whatever is picked '
      'on it', (tester) async {
    final key = laneGroupKey(s1, transform);
    final picked = ValueNotifier<TimelineLaneSelection?>(
      const TimelineLaneSelection(
        layerId: s1,
        laneId: 'position',
        startIndex: 2,
        endIndexExclusive: 6,
      ),
    );
    addTearDown(picked.dispose);
    final session = await pump(
      tester,
      project(),
      laneRange: TimelineLaneRangeHooks(
        selection: picked,
        onSelectUpdate: (_, _, _, _, _) {},
        onTapAt: (_, _, _) {},
        onTapClear: () {},
        onMoveBegin: () => false,
        onMoveUpdate: (_, {stretch, values, landings}) {},
        onMoveEnd: () {},
        onMoveCancel: () {},
      ),
    );
    const band = ValueKey<String>('storyboard-lane-range-selection');
    expect(find.byKey(band), findsOneWidget, reason: 'fixture: a lane\'s');

    session.railView.laneGraphs.value = LaneGraphsView(
      open: {key: const LaneGraph()},
    );
    await tester.pumpAndSettle();

    expect(graphOf(key), findsOneWidget);
    expect(find.byKey(band), findsNothing);
  });

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
    // The sheet rules a thin lane as thin as it stands: one table.
    final sheet = tester.widget<TimelineGridSheet>(
      find.byKey(const ValueKey<String>('storyboard-grid-sheet')),
    );
    expect(
      [for (final row in sheet.rows.rows) row.extent],
      contains(laneGraphFoldedExtent),
    );
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

  testWidgets('an enlarged graph folds a projection row\'s lanes as well — '
      'the camera row\'s, rail and strips alike', (tester) async {
    final key = laneGroupKey(s1, transform);
    await pump(
      tester,
      project(
        cutLayers: [
          Layer(
            id: const LayerId('camera'),
            name: 'Camera',
            kind: LayerKind.camera,
            frames: const [],
            lanesExpanded: true,
          ),
        ],
      ),
      graphs: LaneGraphsView(open: {key: const LaneGraph(enlarged: true)}),
    );

    final row = trackCameraRowId(trackId);
    expect(
      tester.getSize(labelOf(row, 'position')).height,
      laneGraphFoldedExtent,
    );
    expect(
      tester.widget<TimelineLaneControlsRow>(labelOf(row, 'position')).folded,
      isTrue,
    );
    expect(
      tester
          .getSize(
            find.byKey(
              ValueKey<String>(
                'storyboard-camera-lane-position-row-${trackId.value}',
              ),
            ),
          )
          .height,
      laneGraphFoldedExtent,
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
    final blurriness = effectLaneId(blur, 'blurriness');
    await pump(
      tester,
      project(
        seLayers: [seLayer(s1), seLayer(s2, shut: true)],
        effects: [LayerEffect.defaults(id: blur, kind: EffectKind.blur)],
      ),
      graphs: LaneGraphsView(
        open: {key: const LaneGraph()},
        pinned: {
          laneGroupKey(s2, 'rotation'),
          laneGroupKey(carrier, blurriness),
        },
      ),
    );

    expect(
      linesOf(tester, key, guests: true),
      unorderedEquals([
        (layer: s2, lane: 'rotation'),
        (layer: carrier, lane: blurriness),
      ]),
    );
  });

  testWidgets('a graph follows a key in flight as the strips do — an S '
      'row\'s and the V row\'s fx alike (F-195)', (tester) async {
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(preview.dispose);
    final seKey = laneGroupKey(s1, transform);
    final fxKey = laneGroupKey(carrier, effectGroupLaneId(blur));
    final blurred = LayerEffect.defaults(id: blur, kind: EffectKind.blur);
    final hued = LayerEffect.defaults(
      id: hue,
      kind: EffectKind.hueSaturation,
    );
    final session = await pump(
      tester,
      project(
        effects: [blurred, hued],
        lanesExpanded: true,
        expandedLaneGroups: {effectGroupLaneId(blur), effectGroupLaneId(hue)},
      ),
      graphs: LaneGraphsView(
        open: {seKey: const LaneGraph(), fxKey: const LaneGraph()},
      ),
      dragPreview: preview,
    );
    final blurriness = effectLaneId(blur, 'blurriness');
    final saturation = effectLaneId(hue, 'saturation');
    Set<int> drawnKeys(String key, String laneId) => {
      for (final line
          in tester.widget<TimelineLaneGraph>(graphOf(key)).lines.own())
        if (line.lane.laneId == laneId) ...line.lane.keyedFrames,
    };
    Set<int> stripKeys(String laneId) => tester
        .widget<TimelineLaneFrameRow>(
          find.descendant(
            of: find.byKey(
              ValueKey<String>('storyboard-track-lane-row-0-$laneId'),
            ),
            matching: find.byType(TimelineLaneFrameRow),
          ),
        )
        .lane
        .keyedFrames;
    LayerEffect keyed(LayerEffect effect, String parameter, int frame) {
      final held = effect.parameters[parameter]!;
      return effect.withParameter(
        parameter,
        held.copyWith(track: held.track.withKey(frame, 10)),
      );
    }

    expect(drawnKeys(seKey, 'rotation'), isEmpty, reason: 'premise');
    expect(drawnKeys(fxKey, blurriness), isEmpty, reason: 'premise');
    expect(stripKeys(saturation), isEmpty, reason: 'premise');

    // A key on the S row's rotation, in flight.
    final se = session.repository.requireProject().tracks.single.seLayers;
    preview.value = LaneEditPreview.row(
      row: se.single,
      globalRow: se.single.copyWith(
        transformTrack: se.single.transformTrack.copyWith(
          rotation: se.single.transformTrack.rotation.withKey(4, 30),
        ),
      ),
    );
    await tester.pump();
    expect(drawnKeys(seKey, 'rotation'), {4});

    // And keys on the V row's fx chain: in its graph, and on a strip of a
    // group no graph is open over.
    preview.value = LaneEditPreview.track(
      trackId: trackId,
      trackEffects: [keyed(blurred, 'blurriness', 3), keyed(hued, 'saturation', 5)],
    );
    await tester.pump();
    expect(drawnKeys(fxKey, blurriness), {3});
    expect(stripKeys(saturation), {5});
  });

  // I-89 ① ⓕ: 「S 레인 띠가 키 끌기 미리보기 … 를 따라가는지」 — the strips
  // with no graph open over them, as the V row's do above.
  testWidgets('an S row\'s strips follow a key in flight as the V row\'s '
      'do', (tester) async {
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(preview.dispose);
    final session = await pump(tester, project(), dragPreview: preview);
    Set<int> stripKeys() => tester
        .widget<TimelineLaneFrameRow>(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('storyboard-se-lane-row-0-1-rotation'),
            ),
            matching: find.byType(TimelineLaneFrameRow),
          ),
        )
        .lane
        .keyedFrames;
    expect(stripKeys(), isEmpty, reason: 'premise');

    final se = session.repository.requireProject().tracks.single.seLayers;
    preview.value = LaneEditPreview.row(
      row: se.single,
      globalRow: se.single.copyWith(
        transformTrack: se.single.transformTrack.copyWith(
          rotation: se.single.transformTrack.rotation.withKey(4, 30),
        ),
      ),
    );
    await tester.pump();

    expect(stripKeys(), {4});
  });

  testWidgets('a handle pulled in a graph writes its key as the timeline\'s '
      'does — an S row\'s and the V row\'s fx alike, by the edits their '
      'strips key by', (tester) async {
    final seKey = laneGroupKey(s1, transform);
    final fxKey = laneGroupKey(carrier, effectGroupLaneId(blur));
    final blurred = LayerEffect.defaults(id: blur, kind: EffectKind.blur);
    final blurriness = blurred.parameters['blurriness']!;
    final session = await pump(
      tester,
      project(
        seLayers: [
          seLayer(s1).copyWith(
            transformTrack: TransformTrack.empty().copyWith(
              rotation: PropertyTrack<double>()
                  .withKey(0, 0, outgoing: const EaseSide())
                  .withKey(8, 45),
            ),
          ),
        ],
        effects: [
          blurred.withParameter(
            'blurriness',
            blurriness.copyWith(
              track: blurriness.track
                  .withKey(0, 0, outgoing: const EaseSide())
                  .withKey(8, 10),
            ),
          ),
        ],
        lanesExpanded: true,
        expandedLaneGroups: {effectGroupLaneId(blur)},
      ),
      graphs: LaneGraphsView(
        open: {seKey: const LaneGraph(), fxKey: const LaneGraph()},
      ),
      laneEdits: true,
    );
    Track track() => session.repository.requireProject().tracks.single;
    // The one handle [key]'s graph shows — its key on 0, leaving — pulled.
    Future<void> pull(String key) async {
      await tester.ensureVisible(graphOf(key));
      await tester.pumpAndSettle();
      final paint = find.descendant(
        of: find.descendant(
          of: graphOf(key),
          matching: find.byType(LaneGraphPicture),
        ),
        matching: find.byType(CustomPaint),
      );
      final painter =
          tester.widget<CustomPaint>(paint).painter!
              as TimelineLaneGraphPainter;
      final box = tester.renderObject<RenderBox>(paint);
      final handle = painter.handlesIn(box.size).single;
      expect((handle.frame, handle.leaving), (0, true), reason: '⛔전제');
      final gesture = await tester.startGesture(
        box.localToGlobal(handle.at),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(20, -20));
      await tester.pump();
      expect(
        session.dragPreview.value,
        isA<LaneEditPreview>(),
        reason: '⛔전제: in hand, and shown',
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await pull(seKey);
    expect(
      track().seLayers.single.transformTrack.rotation.keyAt(0)!.outgoing,
      isNot(const EaseSide()),
    );
    await pull(fxKey);
    expect(
      track().effects.single.parameters['blurriness']!.track.keyAt(0)!.outgoing,
      isNot(const EaseSide()),
    );
  });

  testWidgets('a key\'s mark in a graph is as big as a member lane marks '
      'it, as on the timeline — where a frame is the tighter side of a cell '
      'and where a lane\'s row is (F-367-Q3)', (tester) async {
    final seKey = laneGroupKey(s1, transform);
    final blurred = LayerEffect.defaults(id: blur, kind: EffectKind.blur);
    final blurriness = blurred.parameters['blurriness']!;
    final seen = <Size>{};
    for (final pixelsPerFrame in const [12.0, 40.0]) {
      await pump(
        tester,
        project(
          seLayers: [
            seLayer(s1).copyWith(
              transformTrack: TransformTrack.empty().copyWith(
                rotation: PropertyTrack<double>().withKey(0, 0).withKey(4, 45),
              ),
            ),
          ],
          effects: [
            blurred.withParameter(
              'blurriness',
              blurriness.copyWith(track: blurriness.track.withKey(0, 10)),
            ),
          ],
          lanesExpanded: true,
          expandedLaneGroups: {effectGroupLaneId(blur)},
        ),
        graphs: LaneGraphsView(open: {seKey: const LaneGraph()}),
        pixelsPerFrame: pixelsPerFrame,
      );
      // The V row's blur, no graph open over it: a member lane marking its
      // key at 0 itself.
      final member = tester
          .widget<TimelineLaneKeyMarker>(
            find.descendant(
              of: find.byKey(
                ValueKey<String>(
                  'storyboard-track-lane-row-0-${effectLaneId(blur, 'blurriness')}',
                ),
              ),
              matching: find.byType(TimelineLaneKeyMarker),
            ),
          )
          .markerSize;
      seen.add(member);
      final paint = find.descendant(
        of: find.descendant(
          of: graphOf(seKey),
          matching: find.byType(LaneGraphPicture),
        ),
        matching: find.byType(CustomPaint),
      );
      final canvas = TestRecordingCanvas();
      tester
          .widget<CustomPaint>(paint)
          .painter!
          .paint(canvas, tester.getSize(paint));
      // Each key's mark as drawn — the whole of its box, whatever its
      // shape, to a float's precision: a path keeps its points in floats.
      final marks = [
        for (final call in canvas.invocations)
          if (call.invocation.memberName == #drawPath &&
              (call.invocation.positionalArguments[1] as Paint).style ==
                  PaintingStyle.fill)
            (call.invocation.positionalArguments[0] as Path).getBounds().size,
      ];
      expect(marks, hasLength(2), reason: '⛔전제: the rotation\'s keys');
      for (final mark in marks) {
        expect(
          mark,
          within(distance: 1e-3, from: member),
          reason: '$pixelsPerFrame',
        );
      }
      await tester.pumpWidget(const SizedBox());
    }
    expect(seen, hasLength(2), reason: '⛔전제: the frames moved the marks');
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
        .getBottomLeft(labelOf(carrier, effectLaneId(blur, 'blurDimensions')))
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

    // Shut by the same verb, its group stays open: only the graphs' own
    // state moves, which the conte panel's tab hears as the timeline's does.
    presses.toggleLaneGraph(key);
    await tester.pumpAndSettle();
    expect(graphOf(key), findsNothing);
  });

  // I-3 ④: the pen is the graph's, and the conte's graph is the timeline's
  // — its key comes by the ＋ this panel's lanes take.
  testWidgets('through the app: a press on the conte\'s graph line with its '
      'pen up puts a key there, as the timeline\'s does', (tester) async {
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
    presses
      ..toggleLanes(conteSeId)
      ..toggleLaneGraph(key);
    // A key on 0 for a line to be drawn through: the ＋ on the lane stood.
    session.standOnRow(
      const LaneRowAddress(conteSeId, 'rotation'),
      panel: WorkingPanel.storyboard,
      globalFrameIndex: 0,
    );
    session.cellInstances.createInstancesForSelection();
    presses.penLaneGraph(key);
    await tester.pumpAndSettle();
    List<int> keyed() => [
      ...session.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .single
          .transformTrack
          .rotation
          .keys
          .keys,
    ]..sort();
    expect(keyed(), [0], reason: '⛔전제');

    final paint = find.descendant(
      of: find.descendant(
        of: graphOf(key),
        matching: find.byType(LaneGraphPicture),
      ),
      matching: find.byType(CustomPaint),
    );
    await tester.ensureVisible(paint);
    await tester.pumpAndSettle();
    final painter =
        tester.widget<CustomPaint>(paint).painter! as TimelineLaneGraphPainter;
    final box = tester.renderObject<RenderBox>(paint);
    final line = painter.own.single;
    final fit = painter.fits[laneGroupKey(line.layer.id, line.lane.laneId)]!;
    await tester.tapAt(
      box.localToGlobal(
        Offset(
          laneGraphAlong(5, painter.frameAxis.geometry.value),
          laneGraphAcross(
            line.lane.curve!.at(5).single,
            fit.ranges.single,
            box.size.height,
            Axis.horizontal,
          ),
        ),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(keyed(), [0, 5]);
  });
}
