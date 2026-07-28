import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/dialogs/input_settings_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

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
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const ValueKey<String>('open-dialog'),
              onPressed: () =>
                  showInputSettingsDialog(context, session: session),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('open-dialog')));
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('Windows shows the tablet-service radios and Wintab applies', (
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
    // The touch policy switch stays for every platform.
    expect(
      find.byKey(const ValueKey<String>('settings-touch-timeline-scroll')),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
  });
}
