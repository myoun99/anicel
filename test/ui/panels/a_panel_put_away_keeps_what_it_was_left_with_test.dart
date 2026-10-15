import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show LayerFoldTwirl;
import 'package:anicel/src/ui/widgets/app_icon_button.dart'
    show AppIconButtonFace;

/// A PANEL PUT AWAY KEEPS WHAT IT WAS LEFT WITH. A panel is built only
/// while it shows (유저 2026-10-14), so what a hand set on it lives above it
/// — ↩️each of these lived in the panel's own state, held only by the panel
/// being kept alive behind the one in front.
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: createDefaultProject()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String key) async {
    final button = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('the storyboard\'s twirls: an S row opened stays open through '
      'the timeline in front', (tester) async {
    await pumpApp(tester);
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final name = 'storyboard-se-lane-toggle-${session.activeTrack.id.value}-1';
    LayerFoldTwirl twirl() => tester.widget<LayerFoldTwirl>(
      find.byWidgetPredicate((w) => w is LayerFoldTwirl && w.name == name),
    );
    await press(tester, 'timeline-mode-storyboard-button');
    expect(twirl().expanded, isFalse, reason: '⛔전제: S1 starts folded');
    await tester.ensureVisible(find.byWidget(twirl()));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidget(twirl()));
    await tester.pumpAndSettle();
    expect(twirl().expanded, isTrue, reason: '⛔전제: the twirl opened S1');

    await press(tester, 'timeline-mode-timeline-button');
    await press(tester, 'timeline-mode-storyboard-button');
    expect(twirl().expanded, isTrue,
        reason: '🚨the storyboard came back with S1 folded again');
  });

  testWidgets('the timesheet\'s data sheet stays on through the conte in '
      'front', (tester) async {
    await pumpApp(tester);
    bool dataSheet() => tester
        .widget<AppIconButtonFace>(
          find.byKey(
            const ValueKey<String>('timesheet-data-mode-toggle-button'),
          ),
        )
        .isSelected;
    expect(dataSheet(), isFalse, reason: '⛔전제: the notation sheet first');
    await press(tester, 'timesheet-data-mode-toggle-button');
    expect(dataSheet(), isTrue, reason: '⛔전제: the switch turned it on');

    await press(tester, 'timeline-mode-conte-button');
    expect(
      find.byKey(const ValueKey<String>('timesheet-data-mode-toggle-button')),
      findsNothing,
      reason: '⛔전제: the timesheet is not built behind the conte',
    );
    await press(tester, 'panel-tab-timesheet');
    expect(dataSheet(), isTrue,
        reason: '🚨the timesheet came back on the notation sheet');
  });
}
