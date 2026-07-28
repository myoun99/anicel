import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/app_documents.dart'
    show appRecordingsDirectory;
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/ui/dialogs/preferences_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';
import 'package:anicel/src/ui/playback/audio_sync_settings.dart';

/// SAVE-1: the unified Preferences dialog — sections switch in place and
/// the Autosave section drives the live save policy.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
  });
  tearDown(() {
    session.dispose();
    AppSave.settings.value = const AppSaveSettings();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Future<void> pumpPreferences(
    WidgetTester tester, {
    PreferencesSection initialSection = PreferencesSection.input,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPreferencesDialog(
                context,
                session: session,
                initialSection: initialSection,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('sections switch in place: Input first, every section '
      'reachable from the rail', (tester) async {
    await pumpPreferences(tester);
    expect(
      find.byKey(const ValueKey<String>('preferences-dialog')),
      findsOneWidget,
    );
    // Input is the landing section.
    expect(
      find.byKey(const ValueKey<String>('settings-touch-timeline-scroll')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('preferences-section-autosave')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('settings-autosave-enabled')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('preferences-section-audio')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('settings-av-offset-value')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('preferences-section-language')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('settings-program-language')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('preferences-section-accent')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('settings-accent2-auto')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('preferences-section-system')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('system-status-section')),
      findsOneWidget,
    );
  });

  testWidgets('the Autosave section drives the live policy: toggle, '
      'interval commit, and the sidecar folder switch', (tester) async {
    await pumpPreferences(tester, initialSection: PreferencesSection.autosave);

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-autosave-enabled')),
    );
    await tester.pumpAndSettle();
    expect(AppSave.settings.value.autosaveEnabled, isFalse);

    // Interval: bad input snaps back, good input commits.
    final interval = find.byKey(
      const ValueKey<String>('settings-autosave-interval'),
    );
    // Re-enable so the field accepts input.
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-autosave-enabled')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(interval, '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(AppSave.settings.value.autosaveIntervalMinutes, 5);
    await tester.enterText(interval, '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(AppSave.settings.value.autosaveIntervalMinutes, 12);

    // The sidecar switch turns the custom folder on (empty until chosen)
    // and back off to "beside the file".
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-sidecar-custom')),
    );
    await tester.pumpAndSettle();
    expect(AppSave.settings.value.sidecarDirectory, '');
    expect(find.text('No folder chosen yet'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-sidecar-custom')),
    );
    await tester.pumpAndSettle();
    expect(AppSave.settings.value.sidecarDirectory, isNull);

    // REC1-B2: the recordings folder row shows the live shelf — the
    // default app folder, a custom choice, and the reset back.
    final recordingsPath = find.byKey(
      const ValueKey<String>('settings-recordings-directory'),
    );
    await tester.ensureVisible(recordingsPath);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(recordingsPath).data,
      appRecordingsDirectory(),
    );
    expect(
      find.byKey(const ValueKey<String>('settings-recordings-reset')),
      findsNothing,
      reason: 'the default shelf has nothing to reset',
    );

    session.setSaveSettings(
      AppSave.settings.value.copyWith(recordingsDirectory: '/tmp/takes'),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(recordingsPath).data, '/tmp/takes');
    final reset = find.byKey(
      const ValueKey<String>('settings-recordings-reset'),
    );
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(AppSave.settings.value.recordingsDirectory, isNull);
    expect(
      tester.widget<Text>(recordingsPath).data,
      appRecordingsDirectory(),
    );
  });

  testWidgets('the Audio section drives the live A/V offset: typed values '
      'clamp, the unit switch keeps the number, and the inspector reports '
      'the fallback while no device is open', (tester) async {
    await pumpPreferences(tester, initialSection: PreferencesSection.audio);

    final offset = find.byKey(
      const ValueKey<String>('settings-av-offset-value'),
    );
    await tester.enterText(offset, '120');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(session.audioSyncSettings.value.offset, 120);
    expect(session.audioSyncSettings.value.unit, AvOffsetUnit.milliseconds);

    // A typo-sized value clamps instead of being accepted as a "setup"
    // (5000 ms of shift would just look like a sync bug).
    await tester.enterText(offset, '5000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      session.audioSyncSettings.value.offset,
      AudioSyncSettings.maxMilliseconds,
    );

    // Switching units keeps the typed number, re-clamped for the unit.
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-av-offset-unit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('frames').last);
    await tester.pumpAndSettle();
    expect(session.audioSyncSettings.value.unit, AvOffsetUnit.frames);
    expect(
      session.audioSyncSettings.value.offset,
      AudioSyncSettings.maxFrames,
    );

    // No device in widget tests → the inspector says so rather than
    // showing nothing.
    expect(
      find.textContaining('not open', findRichText: true),
      findsOneWidget,
    );
  });
}
