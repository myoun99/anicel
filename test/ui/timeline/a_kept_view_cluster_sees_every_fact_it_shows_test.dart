import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';

import '../../helpers/home_page_probes.dart' show showStoryboardPanel;
import '../../helpers/timeline_zoom.dart';

typedef _Inputs = ({
  ProjectFrameRate rate,
  double zoom,
  ValueChanged<double>? onZoom,
  TimelineOrientation orientation,
});

/// 🚨F-244 ⑧: A KEPT VIEW CLUSTER SEES EVERY FACT IT SHOWS.
///
/// The panel keeps its view cluster while [TimelineViewClusterFacts] answer
/// the same, so a fact left out of them is a cluster kept across a change of
/// it — a readout still bound to a zoom the host took away, or still held
/// in the old rate's range. This changes one fact at a time and asks the
/// cluster on screen to be the one the changed panel builds when mounted
/// afresh.
void main() {
  final layers = [
    Layer(
      id: const LayerId('a'),
      name: 'A',
      frames: const [],
      timeline: const {},
    ),
  ];
  final cursor = ValueNotifier<int>(29);
  // ONE function, as the workspace's tear-off is in the app.
  void zoom(double _) {}

  final _Inputs base = (
    rate: ProjectFrameRate.fps24,
    zoom: 24,
    onZoom: zoom,
    orientation: TimelineOrientation.horizontal,
  );

  Widget panel(_Inputs inputs) => MaterialApp(
    home: Scaffold(
      body: TimelinePanel(
        layers: layers,
        activeLayerId: const LayerId('a'),
        frameCursor: cursor,
        playbackFrameCount: 48,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
        onSelectLayer: (_) {},
        onSelectFrame: (_) {},
        onAddLayer: () {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        orientation: inputs.orientation,
        onOrientationChanged: (_) {},
        projectFrameRate: inputs.rate,
        pixelsPerFrame: inputs.zoom,
        onPixelsPerFrameChanged: inputs.onZoom,
      ),
    ),
  );

  TimelineViewCluster cluster(WidgetTester tester) =>
      tester.widget<TimelineViewCluster>(find.byType(TimelineViewCluster));

  // Everything the cluster draws from, its toggle's look included.
  Object shown(TimelineViewCluster cluster) => (
    cluster.projectFrameRate,
    cluster.pixelsPerFrame,
    cluster.onPixelsPerFrameChanged,
    cluster.trailing
        .map((control) => (control as TimelineOrientationToggle).orientation)
        .join(' | '),
  );

  Future<void> open(WidgetTester tester, _Inputs inputs) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(panel(inputs));
    await tester.pumpAndSettle();
  }

  testWidgets('premise: the cluster is kept while nothing it shows moves', (
    tester,
  ) async {
    await open(tester, base);
    final kept = cluster(tester);
    await tester.pumpWidget(panel(base));
    expect(identical(cluster(tester), kept), isTrue);
  });

  final changes = <String, _Inputs>{
    'the rate its zoom is held in': (
      rate: const ProjectFrameRate.integer(30),
      zoom: base.zoom,
      onZoom: base.onZoom,
      orientation: base.orientation,
    ),
    'the zoom': (
      rate: base.rate,
      zoom: 30,
      onZoom: base.onZoom,
      orientation: base.orientation,
    ),
    'the zoom taken away': (
      rate: base.rate,
      zoom: base.zoom,
      onZoom: null,
      orientation: base.orientation,
    ),
    'the orientation its toggle shows': (
      rate: base.rate,
      zoom: base.zoom,
      onZoom: base.onZoom,
      orientation: TimelineOrientation.vertical,
    ),
  };

  for (final MapEntry(key: fact, value: changed) in changes.entries) {
    testWidgets('$fact changed alone builds the cluster anew', (tester) async {
      await open(tester, base);
      await tester.pumpWidget(panel(changed));
      await tester.pumpAndSettle();
      final kept = shown(cluster(tester));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(panel(changed));
      await tester.pumpAndSettle();
      expect(kept, shown(cluster(tester)));
    });
  }

  // The storyboard keeps its own by the same facts. What moves there moves
  // through the app, and the cluster must show what its host was handed.
  group('the storyboard\'s, through the app', () {
    Future<EditorSessionManager> openStoryboard(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: HomePage(
            initialProject: Project(
              id: const ProjectId('kept-cluster'),
              name: 'Kept cluster',
              createdAt: DateTime.utc(2026, 10, 1),
              tracks: [
                Track(
                  id: const TrackId('t'),
                  name: 'Video',
                  cuts: [
                    Cut(
                      id: const CutId('cut-0'),
                      name: 'cut-0',
                      duration: 48,
                      canvasSize: const CanvasSize(width: 640, height: 360),
                      layers: layers,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await showStoryboardPanel(tester);
      return tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
    }

    StoryboardTabHost host(WidgetTester tester) =>
        tester.widget<StoryboardTabHost>(find.byType(StoryboardTabHost));

    testWidgets('the zoom', (tester) async {
      await openStoryboard(tester);
      final before = host(tester).pixelsPerFrame;
      await dragTimelineZoom(tester, 20);
      expect(host(tester).pixelsPerFrame, isNot(before), reason: 'premise');
      expect(cluster(tester).pixelsPerFrame, host(tester).pixelsPerFrame);
    });

    testWidgets('the rate', (tester) async {
      final session = await openStoryboard(tester);
      session.projectSettings.setProjectFrameRate(
        const ProjectFrameRate.integer(30),
      );
      await tester.pumpAndSettle();
      expect(
        cluster(tester).projectFrameRate,
        const ProjectFrameRate.integer(30),
      );
    });
  });
}
