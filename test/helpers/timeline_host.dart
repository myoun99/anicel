import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/tab_rail_wiring.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

/// THE TIMELINE TAB AS THE WORKSPACE HOSTS IT (`workspace_tabs.dart`), with
/// nothing of the app around it: [project] opened in a session, the rail
/// wired to it as the workspace wires it (`TabRailWiring`), the grid turned
/// by its own ⇄ from [orientation], at the zoom the workspace opens at, a
/// Scale lane linked by the transform tool as the app opens it. The session
/// goes with the tab, as the app's goes with its page — so what it left
/// running is stopped before the test's end looks for it.
///
/// The workspace's own verbs are not here — a per-cut zoom, the onion
/// panel's reveal, a file placed from the pool: a contract the APP wires
/// keeps a test that opens the app.
///
/// 📏heavy-tests-timeline (2026-10-25): a timeline test opened the app and
/// pulled the dock up for room — most of each one's two to four seconds,
/// as the conte's was (`pumpStoryboardHost`).
Future<EditorSessionManager> pumpTimelineHost(
  WidgetTester tester,
  Project project, {
  Size surface = const Size(1400, 700),
  TimelineOrientation orientation = TimelineOrientation.horizontal,
  double pixelsPerFrame = TimelineZoomLimits.referencePixelsPerFrame,
}) async {
  final session = EditorSessionManager(initialProject: project);
  final tab = await _timelineTab(
    tester,
    session,
    surface: surface,
    orientation: orientation,
    pixelsPerFrame: pixelsPerFrame,
  );
  await tester.pumpWidget(_SessionOwner(session: session, child: tab));
  await tester.pumpAndSettle();
  return session;
}

/// [pumpTimelineHost] on a [session] the test made and set up itself —
/// the test disposes it.
///
/// 📏tests-hand-roll-the-tab-hosts (2026-10-25): as the conte's
/// (`pumpStoryboardHostOn`).
Future<void> pumpTimelineHostOn(
  WidgetTester tester,
  EditorSessionManager session, {
  Size surface = const Size(1400, 700),
  TimelineOrientation orientation = TimelineOrientation.horizontal,
  double pixelsPerFrame = TimelineZoomLimits.referencePixelsPerFrame,
}) async {
  await tester.pumpWidget(
    await _timelineTab(
      tester,
      session,
      surface: surface,
      orientation: orientation,
      pixelsPerFrame: pixelsPerFrame,
    ),
  );
  await tester.pumpAndSettle();
}

Future<Widget> _timelineTab(
  WidgetTester tester,
  EditorSessionManager session, {
  required Size surface,
  required TimelineOrientation orientation,
  required double pixelsPerFrame,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final turned = ValueNotifier(orientation);
  addTearDown(turned.dispose);
  final zoom = ValueNotifier(pixelsPerFrame);
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
  Widget tab(BuildContext context, Widget? _) => TimelineTabHost(
    session: session,
    orientation: turned.value,
    onOrientationChanged: (next) => turned.value = next,
    pixelsPerFrame: zoom.value,
    pixelsPerFrameListenable: zoom,
    onPixelsPerFrameChanged: (next) => zoom.value = next,
    rulerView: FrameRulerView.frames,
    onRulerViewChanged: (_) {},
    timelineRailExtent: railExtents[LayerRailId.timeline],
    xsheetRailExtent: railExtents[LayerRailId.xsheet],
    rail: TabRailWiring.of(session),
    transformOptions: transformTool,
  );
  return MaterialApp(
    // A tab is its session's, as the conte's helper keys it.
    key: ObjectKey(session),
    // The app's theme, as `main.dart` lays it over the workspace: it is
    // what keeps a press inkless (`splashFactory`), among the rest.
    theme: buildAppTheme(),
    home: Scaffold(
      // Laid out tight, as a dock lays its panel — the tick host asks it.
      body: SizedBox.expand(
        child: TickLayer.host(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              session,
              turned,
              session.railView.drawn,
            ]),
            builder: tab,
          ),
        ),
      ),
    ),
  );
}

/// The session the timeline tab up shows — the app's or [pumpTimelineHost]'s,
/// asked the same way.
EditorSessionManager timelineSessionOf(WidgetTester tester) =>
    tester.widget<TimelineTabHost>(find.byType(TimelineTabHost)).session;

/// Disposes [session] when the tree it was pumped in goes.
class _SessionOwner extends StatefulWidget {
  const _SessionOwner({required this.session, required this.child});

  final EditorSessionManager session;
  final Widget child;

  @override
  State<_SessionOwner> createState() => _SessionOwnerState();
}

class _SessionOwnerState extends State<_SessionOwner> {
  @override
  void dispose() {
    widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
