import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/dialogs/audio_settings_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The audio UI reads in the PROGRAM language (the UI-R10 #7 setting):
/// the tables are complete by construction (const constructors refuse a
/// missing entry at compile time); this pins the WIRING — the widgets
/// actually consult the session's language rather than their old
/// hardcoded English.
void main() {
  EditorSessionManager session() => EditorSessionManager(
    initialProject: createDefaultProject(),
    audioConformStore: AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => const ConformResult(
        outcome: ConformOutcome.undecodable,
        error: 'test stub',
      ),
      log: (_) {},
    ),
  );

  testWidgets('Preferences ▸ Audio follows the program language', (
    tester,
  ) async {
    final manager = session();
    manager.setLanguageSettings(
      const AppLanguageSettings(programLanguage: AppLanguage.ko),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AudioSettingsSection(session: manager),
          ),
        ),
      ),
    );
    expect(find.text('장치'), findsOneWidget);
    expect(find.text('시스템 기본값'), findsWidgets);
    expect(find.text('싱크 인스펙터'), findsOneWidget);
    // And back to English when the setting says so.
    manager.setLanguageSettings(
      const AppLanguageSettings(programLanguage: AppLanguage.en),
    );
    await tester.pump();
    expect(find.text('Devices'), findsOneWidget);
    manager.dispose();
  });

  testWidgets('the recording messages speak the program language', (
    tester,
  ) async {
    final manager = session();
    manager.setLanguageSettings(
      const AppLanguageSettings(programLanguage: AppLanguage.ja),
    );
    // Stopping with nothing armed is the simplest message-producing path.
    expect(manager.stopVoiceRecordingAndPlace(), '録音中ではありません。');
    manager.setLanguageSettings(
      const AppLanguageSettings(programLanguage: AppLanguage.en),
    );
    expect(manager.stopVoiceRecordingAndPlace(), 'Nothing was recording.');
    manager.dispose();
  });
}
