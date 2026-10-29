import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/panel_view_memory.dart';
import 'package:anicel/src/ui/session/tab_rail_wiring.dart';
import 'package:anicel/src/ui/storyboard/storyboard_rows_channel.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// THE STORYBOARD TAB AS THE WORKSPACE HOSTS IT (`workspace_tabs.dart`),
/// with nothing of the app around it: [project] opened in a session, the
/// rail wired to it as the workspace wires it (`TabRailWiring`) and built
/// again when its view moves, the conte at the zoom it opens at unless
/// [pixelsPerFrame] names another — the zooms it writes heard by
/// [onPixelsPerFrameChanged], when the test asks.
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
  ValueChanged<double> onPixelsPerFrameChanged = _unheard,
}) async {
  final session = EditorSessionManager(initialProject: project);
  addTearDown(session.dispose);
  await pumpStoryboardHostOn(
    tester,
    session,
    surface: surface,
    pixelsPerFrame: pixelsPerFrame,
    onPixelsPerFrameChanged: onPixelsPerFrameChanged,
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
///
/// [rowsChannel] is the workspace's, where the ↑/↓ walk and the flip
/// window read the rows while the conte is worked in.
Future<void> pumpStoryboardHostOn(
  WidgetTester tester,
  EditorSessionManager session, {
  Size surface = const Size(1500, 800),
  double pixelsPerFrame = PanelViewMemory.defaultStoryboardPixelsPerFrame,
  ValueChanged<double> onPixelsPerFrameChanged = _unheard,
  StoryboardRowsChannel? rowsChannel,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      // A tab is built for one session, as the workspace builds every panel
      // (I-7, `EditorPanelTab.builtFor`): the host takes the session into
      // its State, so another session's tab is a new one.
      key: ObjectKey(session),
      // The app's theme, as `main.dart` lays it over the workspace: it is
      // what keeps a press inkless (`splashFactory`), among the rest.
      theme: buildAppTheme(),
      home: Scaffold(
        body: ListenableBuilder(
          // The workspace's merge for this tab, less what it owns itself.
          listenable: Listenable.merge([session, session.railView.drawn]),
          builder: (context, _) => StoryboardTabHost(
            session: session,
            rail: TabRailWiring.of(session),
            pixelsPerFrame: pixelsPerFrame,
            onPixelsPerFrameChanged: onPixelsPerFrameChanged,
            showSeconds: false,
            onShowSecondsChanged: (_) {},
            thumbnails: null,
            rowsChannel: rowsChannel,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A zoom no one asked about.
void _unheard(double _) {}
