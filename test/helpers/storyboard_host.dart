import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/panel_view_memory.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

import 'storyboard_twirls.dart';

/// THE STORYBOARD TAB AS THE WORKSPACE HOSTS IT (`workspace_tabs.dart`),
/// with nothing of the app around it: [project] opened in a session, the
/// rows' twirls, attach folds and header graphs the session's own
/// ([withStoryboardTwirls]), the conte at the zoom it opens at unless
/// [pixelsPerFrame] names another.
///
/// 📏heavy-tests-timeline (2026-10-20): opening the app and turning to the
/// conte was two of a storyboard test's three seconds — 2.1s, against 0.45s
/// for this, warm, on the same project. A contract the APP wires keeps a
/// test that opens the app; one the panel answers pumps this.
Future<EditorSessionManager> pumpStoryboardHost(
  WidgetTester tester,
  Project project, {
  Size surface = const Size(1500, 800),
  double pixelsPerFrame = PanelViewMemory.defaultStoryboardPixelsPerFrame,
}) async {
  final session = EditorSessionManager(initialProject: project);
  addTearDown(session.dispose);
  await pumpStoryboardHostOn(
    tester,
    session,
    surface: surface,
    pixelsPerFrame: pixelsPerFrame,
  );
  return session;
}

/// [pumpStoryboardHost] on a [session] the test made and set up itself —
/// the test disposes it.
///
/// 📏tests-hand-roll-the-tab-hosts (2026-10-25): seventy test files built
/// the tab themselves, most with a session they had edited first; each
/// told its own part of the workspace's wiring, and what the workspace
/// learned later none of them heard.
Future<void> pumpStoryboardHostOn(
  WidgetTester tester,
  EditorSessionManager session, {
  Size surface = const Size(1500, 800),
  double pixelsPerFrame = PanelViewMemory.defaultStoryboardPixelsPerFrame,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final rail = session.railView;
  final presses = SessionRowButtonPresses(session);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: withStoryboardTwirls(
          session,
          (twirls) => ListenableBuilder(
            listenable: Listenable.merge([
              rail.laneGraphs,
              rail.collapsedAttachBaseIds,
            ]),
            builder: (context, _) => StoryboardTabHost(
              session: session,
              collapsedAttachBaseIds: rail.collapsedAttachBaseIds.value,
              onToggleAttachGroup: presses.toggleGroupFold,
              expandedLaneLayerIds: twirls.expandedLaneLayerIds,
              onToggleLayerLanes: twirls.onToggleLayerLanes,
              expandedLaneGroupKeys: twirls.expandedLaneGroupKeys,
              onToggleLaneGroupKey: twirls.onToggleLaneGroupKey,
              laneGraphs: rail.laneGraphs.value,
              laneGraphVerbs: presses.laneGraphVerbs,
              pixelsPerFrame: pixelsPerFrame,
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
}
