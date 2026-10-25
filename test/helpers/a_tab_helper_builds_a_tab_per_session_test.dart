import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

import 'storyboard_host.dart';
import 'timeline_host.dart';

/// The tab helpers build a tab for ONE session, as the workspace builds
/// every panel (I-7, `EditorPanelTab.builtFor`): a host takes the session
/// into its State, so another session's tab is a new State — never the
/// last one's carried over. A test that pumps a second session into the
/// same helper gets the tab the app would show it.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  testWidgets('the timeline tab', (tester) async {
    final first = session();
    final second = session();
    await pumpTimelineHostOn(tester, first);
    final before = tester.state(find.byType(TimelineTabHost));

    await pumpTimelineHostOn(tester, first);
    expect(
      tester.state(find.byType(TimelineTabHost)),
      same(before),
      reason: 'the same session keeps its tab',
    );

    await pumpTimelineHostOn(tester, second);
    expect(tester.state(find.byType(TimelineTabHost)), isNot(same(before)));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the conte tab', (tester) async {
    final first = session();
    final second = session();
    await pumpStoryboardHostOn(tester, first);
    final before = tester.state(find.byType(StoryboardTabHost));

    await pumpStoryboardHostOn(tester, first);
    expect(
      tester.state(find.byType(StoryboardTabHost)),
      same(before),
      reason: 'the same session keeps its tab',
    );

    await pumpStoryboardHostOn(tester, second);
    expect(tester.state(find.byType(StoryboardTabHost)), isNot(same(before)));
    await tester.pumpWidget(const SizedBox());
  });
}
