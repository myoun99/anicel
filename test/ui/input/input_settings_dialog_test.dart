import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/boolean_dot_probe.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/dialogs/input_settings_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/models/app_input_settings.dart';

/// PEN-2: the Input Settings dialog's tablet-service switch (Windows
/// only — the CSP-style dual backend).
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Future<EditorSessionManager> pumpDialog(WidgetTester tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    // The section itself, as the Preferences dialog mounts it (SAVE-1).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InputSettingsSection(session: session),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('Windows shows the tablet-service pair and Wintab applies', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pumpDialog(tester);

    expect(
      find.byKey(const ValueKey<String>('settings-tablet-standard')),
      findsOneWidget,
    );
    final wintab = find.byKey(const ValueKey<String>('settings-tablet-wintab'));
    expect(wintab, findsOneWidget);

    // The dialog scrolls now (PEN-7a grew it) — bring the row into view.
    await tester.ensureVisible(wintab);
    await tester.pumpAndSettle();
    await tester.tap(wintab);
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.tabletService, TabletService.wintab);

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-tablet-standard')),
    );
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.tabletService, TabletService.standard);

    // A press SELECTS — pressing the one that is on leaves it on: there is
    // always a service, and the radio this pair used to be never let go of
    // one either.
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-tablet-standard')),
    );
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.tabletService, TabletService.standard);
    // 유저 named this pair as the pick-one group (guide-sym ⑥⑧), so the
    // idle one steps back.
    expect(tester.booleanDotIn(wintab).inPickOneGroup, isTrue);

    // Foundation debug vars must be back BEFORE the binding's invariant
    // check (which runs ahead of tearDown).
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('non-Windows hides the tablet-service section', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpDialog(tester);

    expect(
      find.byKey(const ValueKey<String>('settings-tablet-wintab')),
      findsNothing,
    );
    // A row that is NOT platform-conditional stays, or this case would
    // also pass on a dialog that rendered nothing at all.
    expect(
      find.byKey(const ValueKey<String>('settings-extra-finger')),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
  });
}
