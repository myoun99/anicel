import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_command_bar.dart';

/// I-57 (10-13): a host makes its toolbar anew on every notify, and the
/// command bar took that for a new bar — its overflow scroller and the tick
/// layer round it were made again, laid out, painted and described again,
/// round buttons that had not changed. The bar seats a new piece now and
/// keeps its frame. Both frame panels mount the one bar.
void main() {
  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Future<void> pump(WidgetTester tester, {required bool storyboard}) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    if (storyboard) {
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
      );
      await tester.pumpAndSettle();
    }
  }

  TimelineCommandBar bar(WidgetTester tester) =>
      tester.widget<TimelineCommandBar>(find.byType(TimelineCommandBar));

  Widget scroller(WidgetTester tester) => tester.widget(
    find.descendant(
      of: find.byType(TimelineCommandBar),
      matching: find.byType(SingleChildScrollView),
    ),
  );

  for (final storyboard in [false, true]) {
    final panel = storyboard ? 'storyboard' : 'timeline';
    testWidgets('$panel: a notify that changes nothing seats the new toolbar '
        'in the frame the bar already had', (tester) async {
      await pump(tester, storyboard: storyboard);
      final leading = bar(tester).leading;
      final frame = scroller(tester);

      sessionOf(tester).notifyChanged();
      await tester.pump();

      expect(
        identical(bar(tester).leading, leading),
        isFalse,
        reason: 'premise: the host handed the bar a new toolbar',
      );
      expect(identical(scroller(tester), frame), isTrue);
    });
  }
}
