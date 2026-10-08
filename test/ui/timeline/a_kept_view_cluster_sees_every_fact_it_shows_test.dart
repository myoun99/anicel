import 'package:flutter/foundation.dart' show ValueListenable;
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
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

import '../../helpers/home_page_probes.dart' show showStoryboardPanel;

typedef _Inputs = ({
  ValueNotifier<int> cursor,
  ProjectFrameRate rate,
  bool seconds,
  double zoom,
  ValueChanged<double>? onZoom,
  ValueListenable<String> cutName,
  TimelineOrientation orientation,
});

/// 🚨F-244 ⑧: A KEPT VIEW CLUSTER SEES EVERY FACT IT SHOWS.
///
/// The panel keeps its view cluster while [TimelineViewClusterFacts] answer
/// the same, so a fact left out of them is a cluster kept across a change of
/// it — a counter still in the old rate, a − and + still bound to a zoom the
/// host took away. This changes one fact at a time and asks the cluster on
/// screen to be the one the changed panel builds when mounted afresh.
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
  final otherCursor = ValueNotifier<int>(29);
  // The name is HEARD, like the cursor (I-57): a crossing rebuilds its one
  // Text, so the fact is which channel the slot listens to.
  final cutName = ValueNotifier<String>('c1');
  final otherCutName = ValueNotifier<String>('c2');
  // ONE function, as the workspace's tear-off is in the app.
  void zoom(double _) {}

  final _Inputs base = (
    cursor: cursor,
    rate: ProjectFrameRate.fps24,
    seconds: true,
    zoom: 24,
    onZoom: zoom,
    cutName: cutName,
    orientation: TimelineOrientation.horizontal,
  );

  Widget panel(_Inputs inputs) => MaterialApp(
    home: Scaffold(
      body: TimelinePanel(
        layers: layers,
        activeLayerId: const LayerId('a'),
        frameCursor: inputs.cursor,
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
        showSeconds: inputs.seconds,
        pixelsPerFrame: inputs.zoom,
        onPixelsPerFrameChanged: inputs.onZoom,
        cutName: inputs.cutName,
      ),
    ),
  );

  TimelineViewCluster cluster(WidgetTester tester) =>
      tester.widget<TimelineViewCluster>(find.byType(TimelineViewCluster));

  // Everything the cluster draws from, its toggle's look included.
  Object shown(TimelineViewCluster cluster) => (
    cluster.frameCursor,
    cluster.globalFrame,
    cluster.projectFrameRate,
    cluster.showSeconds,
    cluster.pixelsPerFrame,
    cluster.onPixelsPerFrameChanged,
    cluster.cutName,
    cluster.trailing
        .map((control) => (control as AppIconButton).tooltip)
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
    'the cursor its counter hears': (
      cursor: otherCursor,
      rate: base.rate,
      seconds: base.seconds,
      zoom: base.zoom,
      onZoom: base.onZoom,
      cutName: base.cutName,
      orientation: base.orientation,
    ),
    'the rate its counter counts in': (
      cursor: base.cursor,
      rate: const ProjectFrameRate.integer(30),
      seconds: base.seconds,
      zoom: base.zoom,
      onZoom: base.onZoom,
      cutName: base.cutName,
      orientation: base.orientation,
    ),
    'the notation its counter reads in': (
      cursor: base.cursor,
      rate: base.rate,
      seconds: false,
      zoom: base.zoom,
      onZoom: base.onZoom,
      cutName: base.cutName,
      orientation: base.orientation,
    ),
    'the zoom': (
      cursor: base.cursor,
      rate: base.rate,
      seconds: base.seconds,
      zoom: 48,
      onZoom: base.onZoom,
      cutName: base.cutName,
      orientation: base.orientation,
    ),
    'the zoom taken away': (
      cursor: base.cursor,
      rate: base.rate,
      seconds: base.seconds,
      zoom: base.zoom,
      onZoom: null,
      cutName: base.cutName,
      orientation: base.orientation,
    ),
    'the cut\'s name': (
      cursor: base.cursor,
      rate: base.rate,
      seconds: base.seconds,
      zoom: base.zoom,
      onZoom: base.onZoom,
      cutName: otherCutName,
      orientation: base.orientation,
    ),
    'the orientation its toggle shows': (
      cursor: base.cursor,
      rate: base.rate,
      seconds: base.seconds,
      zoom: base.zoom,
      onZoom: base.onZoom,
      cutName: base.cutName,
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
  // through the app, and the cluster must show what its host was handed;
  // the cut's name is `the_cut_name_stands_by_the_zoom_test`'s.
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
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-zoom-in-button')),
      );
      await tester.pumpAndSettle();
      expect(host(tester).pixelsPerFrame, isNot(before), reason: 'premise');
      expect(cluster(tester).pixelsPerFrame, host(tester).pixelsPerFrame);
    });

    testWidgets('the notation', (tester) async {
      await openStoryboard(tester);
      final before = host(tester).showSeconds;
      await tester.tap(
        find.byKey(
          const ValueKey<String>('storyboard-time-display-toggle-button'),
        ),
      );
      await tester.pumpAndSettle();
      expect(host(tester).showSeconds, isNot(before), reason: 'premise');
      expect(cluster(tester).showSeconds, host(tester).showSeconds);
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
