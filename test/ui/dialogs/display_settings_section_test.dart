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
    ShapeDecoration decorationOf(double scale) =>
        tester.widget<Container>(
              find.descendant(of: stop(scale), matching: find.byType(Container)),
            ).decoration!
            as ShapeDecoration;

    final selected = decorationOf(1.5);
    final unselected = decorationOf(1.0);
    expect(
      selected.color,
      isNotNull,
      reason: 'selection is COLOR only (법) — the chosen stop is filled',
    );
    expect(unselected.color, isNull);
    // ⛔And the SHAPE does not change with selection: a border that thickens
    // when a stop lands would shove its neighbours sideways.
    expect(
      (selected.shape as RoundedSuperellipseBorder).side.width,
      (unselected.shape as RoundedSuperellipseBorder).side.width,
    );
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
