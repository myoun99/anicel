import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

/// THE TIMELINE TAB AS THE WORKSPACE HOSTS IT (`workspace_tabs.dart`), with
/// nothing of the app around it: [project] opened in a session, the rows'
/// twirls, attach folds and header graphs the session's own (`RailView`)
/// and pressed through its presses, the grid turned by its own ⇄ from
/// [orientation], at the zoom the workspace opens at, its axes where the
/// project keeps them, a Scale lane linked by the transform tool as the app
/// opens it.
///
/// The workspace's own verbs are not here — a section's button, the row
/// filter, a per-cut zoom, the onion panel's reveal: a contract the APP
/// wires keeps a test that opens the app.
///
/// 📏heavy-tests-timeline (2026-10-25): a timeline test opened the app and
/// pulled the dock up for room — most of each one's two to four seconds,
/// as the conte's was (`pumpStoryboardHost`).
Future<EditorSessionManager> pumpTimelineHost(
  WidgetTester tester,
  Project project, {
  Size surface = const Size(1400, 700),
  TimelineOrientation orientation = TimelineOrientation.horizontal,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final session = EditorSessionManager(initialProject: project);
  addTearDown(session.dispose);
  final turned = ValueNotifier(orientation);
  addTearDown(turned.dispose);
  final zoom = ValueNotifier(TimelineZoomLimits.referencePixelsPerFrame);
  addTearDown(zoom.dispose);
  final transformTool = ValueNotifier(TransformToolOptions.defaults);
  addTearDown(transformTool.dispose);
  final railExtents = {
    for (final railId in LayerRailId.values) railId: LayerRailExtent(),
  };
  addTearDown(() {
    for (final extent in railExtents.values) {
      extent.dispose();
    }
  });
  final rail = session.railView;
  final views = session.panelViews;
  final presses = SessionRowButtonPresses(session);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // Laid out tight, as a dock lays its panel — the tick host asks it.
        body: SizedBox.expand(
          child: TickLayer.host(
            child: ListenableBuilder(
              listenable: Listenable.merge([session, turned, rail.drawn]),
              builder: (context, _) => TimelineTabHost(
                session: session,
                orientation: turned.value,
                onOrientationChanged: (next) => turned.value = next,
                pixelsPerFrame: zoom.value,
                pixelsPerFrameListenable: zoom,
                onPixelsPerFrameChanged: (next) => zoom.value = next,
                showSeconds: false,
                onShowSecondsChanged: (_) {},
                timelineRailExtent: railExtents[LayerRailId.timeline],
                xsheetRailExtent: railExtents[LayerRailId.xsheet],
                timelineFrameAxisOffset:
                    views.frameAxisOffsets[LayerRailId.timeline],
                xsheetFrameAxisOffset:
                    views.frameAxisOffsets[LayerRailId.xsheet],
                timelineLayerAxisOffset:
                    views.layerAxisOffsets[LayerRailId.timeline],
                xsheetLayerAxisOffset:
                    views.layerAxisOffsets[LayerRailId.xsheet],
                expandedLaneLayerIds: rail.expandedLaneLayerIds.value,
                onToggleLayerLanes: presses.toggleLanes,
                expandedLaneGroupKeys: rail.expandedLaneGroupKeys.value,
                onToggleLaneGroupKey: presses.toggleLaneGroup,
                laneGraphs: rail.laneGraphs.value,
                laneGraphVerbs: presses.laneGraphVerbs,
                hiddenSections: rail.hiddenSections.value,
                rowFilter: rail.rowFilter.value,
                collapsedAttachBaseIds: rail.collapsedAttachBaseIds.value,
                onToggleAttachGroup: presses.toggleGroupFold,
                transformOptions: transformTool,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}
