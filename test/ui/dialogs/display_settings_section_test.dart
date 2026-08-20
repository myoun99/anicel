import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/dialogs/display_settings_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/ui_scale.dart';

void main() {
  late EditorSessionManager session;

  setUp(() {
    // No stores: the section must work with persistence absent, which is
    // also how every widget test runs the app.
    session = EditorSessionManager(initialProject: createDefaultProject());
    AppUiScale.value.value = AppUiScale.defaultScale;
  });

  tearDown(() {
    session.dispose();
    AppUiScale.value.value = AppUiScale.defaultScale;
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: DisplaySettingsSection(session: session)),
    ),
  );

  Finder stop(double scale) =>
      find.byKey(ValueKey<String>('ui-scale-stop-${(scale * 100).round()}'));

  testWidgets('every ladder stop is offered, and only those', (tester) async {
    await pump(tester);
    for (final scale in AppUiScale.ladder) {
      expect(stop(scale), findsOneWidget, reason: AppUiScale.label(scale));
      expect(find.text(AppUiScale.label(scale)), findsOneWidget);
    }
    // ⛔A slider would show a continuum; this is a ladder (유저 확정).
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('tapping a stop sets the live scale', (tester) async {
    await pump(tester);
    await tester.tap(stop(1.25));
    await tester.pump();
    expect(AppUiScale.value.value, 1.25);

    await tester.tap(stop(0.75));
    await tester.pump();
    expect(AppUiScale.value.value, 0.75);
  });

  testWidgets('the section follows the value it did not set', (tester) async {
    // The scale is app-wide, so something else can move it — the restore
    // in `main()` does exactly that, before any of this is mounted.
    await pump(tester);
    session.setUiScale(1.5);
    await tester.pump();
    final selected = tester.widget<Container>(
      find.descendant(of: stop(1.5), matching: find.byType(Container)),
    );
    final unselected = tester.widget<Container>(
      find.descendant(of: stop(1.0), matching: find.byType(Container)),
    );
    expect(
      (selected.decoration! as BoxDecoration).color,
      isNotNull,
      reason: 'selection is COLOR only (법) — the chosen stop is filled',
    );
    expect((unselected.decoration! as BoxDecoration).color, isNull);
  });

  testWidgets('an off-ladder value from outside is snapped, not shown raw', (
    tester,
  ) async {
    await pump(tester);
    session.setUiScale(1.2);
    await tester.pump();
    expect(AppUiScale.value.value, 1.25);
    // ⚠️Otherwise no stop would look selected and the row would read as
    // "the scale is off".
    expect(find.text('120%'), findsNothing);
  });
}
