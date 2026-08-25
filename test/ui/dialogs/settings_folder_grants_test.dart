import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/autosave_settings_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';

/// Q-scoped-folder-settings (유저 08-26 「알아서 맡김」 → A): the folder
/// settings keep the TOKEN the picker handed over, not just the path —
/// on macOS a stored path without it stays on screen while every write
/// quietly fails after a relaunch.
void main() {
  tearDown(() {
    AppSave.settings.value = const AppSaveSettings();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AutosaveSettingsSection(session: session),
          ),
        ),
      ),
    );
  }

  testWidgets('the browse buttons store the grant WITH its token', (
    tester,
  ) async {
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
        const FolderGrant.granted(path: '/picked/folder', bookmark: 'TOK==');
    addTearDown(() => FolderPicker.debugFolderPicker = null);
    await pumpSection(tester);

    for (final (key, read) in [
      (
        'settings-recordings-browse',
        () => AppSave.settings.value.recordingsDirectory,
      ),
      ('settings-conform-browse', () => AppSave.settings.value.conformDirectory),
    ]) {
      final button = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        read(),
        const GrantedDirectory(path: '/picked/folder', bookmark: 'TOK=='),
        reason: '$key must keep the token — the path alone dies at the next '
            'launch on macOS',
      );
    }
  });

  testWidgets('🚨 the shell reopens the folder grants at launch, and a '
      'moved folder is followed', (tester) async {
    // The WIRING: a resolver nobody calls is a token nobody uses — the
    // stored path would sit on screen while every write bounced, the
    // exact silent failure this round exists to end.
    FolderPicker.debugBookmarkResolver = (base64, kind) async =>
        const FolderGrant.granted(path: '/mounted/takes', bookmark: 'FRESH==');
    addTearDown(() => FolderPicker.debugBookmarkResolver = null);
    AppSave.settings.value = const AppSaveSettings(
      recordingsDirectory: GrantedDirectory(
        path: '/old/takes',
        bookmark: 'TOK==',
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
    await tester.pump();

    expect(
      AppSave.settings.value.recordingsDirectory,
      const GrantedDirectory(path: '/mounted/takes', bookmark: 'FRESH=='),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
