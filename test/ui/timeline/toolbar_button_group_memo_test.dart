import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

/// A button whose enabled state did not change must not be rebuilt.
///
/// The action toolbar was cached as ONE blob, so any of the fifteen
/// predicates in its token dropped every button in the row. Measured on a
/// flip step that crosses "no cel ↔ cel": five of the toolbar's ten buttons
/// change — all of them the comma buttons, which read a single boolean —
/// and all ten were rebuilt, 395 widgets' worth. The groups carry their own
/// predicates now (the file's existing `_StaticCommandGroup` idiom), which
/// takes it to 257.
///
/// ⚠️ The oracle is widget INSTANCE identity. Asking "is the button still
/// enabled" passes against a toolbar that rebuilds it every step.
void main() {
  testWidgets('a crossing rebuilds the comma buttons and leaves the icon '
      'buttons alone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final toolbar = find.byType(TimelineActionToolbar);

    Object iconButton(String keyValue) => tester.widget(
      find.descendant(
        of: toolbar,
        matching: find.byWidgetPredicate(
          (w) => w is AppIconButton && w.keyValue == keyValue,
        ),
      ),
    );
    Object commaButton() => tester.widget(
      find.descendant(
        of: toolbar,
        matching: find.byKey(const ValueKey<String>('set-comma-1-button')),
      ),
    );

    // A cel at 0, empty paper at 4 — the crossing the flip makes.
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final addBefore = iconButton('new-frame-button');
    final markBefore = iconButton('toggle-mark-button');
    final commaBefore = commaButton();

    session.selectFrameIndex(4);
    await tester.pumpAndSettle();

    // FIXTURE GUARD: the step really did change a button. Without this the
    // test would pass on a step that changed nothing, which is the case the
    // defect never touched.
    expect(
      identical(commaButton(), commaBefore),
      isFalse,
      reason: 'the comma buttons DO change across this step',
    );
    expect(
      identical(iconButton('new-frame-button'), addBefore),
      isTrue,
      reason: 'the Add button did not change, so it must not be rebuilt',
    );
    expect(
      identical(iconButton('toggle-mark-button'), markBefore),
      isTrue,
      reason: 'nor the mark button',
    );

    session.prerenderScheduler.cancel();
  });
}
