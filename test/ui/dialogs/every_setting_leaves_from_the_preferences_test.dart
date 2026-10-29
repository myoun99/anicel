import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/settings_file.dart';
import 'package:anicel/src/services/persistence/settings_room_file.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/dialogs/preferences_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/settle_async.dart';
import '../../helpers/temp_dir.dart';

/// I-142-Q1 (유저 2026-10-29): 「환경설정 창에 「설정 전부 내보내기」」 —
/// the preferences window hands the person every setting that travels, as
/// the room holds it, in one file.
void main() {
  late EditorSessionManager session;
  late Directory folder;
  final placed = <String>[];

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    folder = Directory.systemTemp.createTempSync('qa_all_settings_');
  });
  tearDown(() {
    session.dispose();
    FolderPicker.debugOperatingSystem = null;
    FolderPicker.debugSaveDestinationPicker = null;
    for (final path in placed) {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    placed.clear();
    deleteTempQuietly(folder);
  });

  /// [document] put in the (sandboxed) room as [entry]'s store would.
  void putInTheRoom(String entry, Map<String, Object?> document) {
    final path = settingsRoomPath(entry);
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(document));
    placed.add(path);
  }

  testWidgets('「설정 전부 내보내기」 asks where under the settings\' name, '
      'writes what the room holds — and what stays on this machine stays — '
      'and says so', (tester) async {
    const scale = {'version': 1, 'scale': 1.25};
    putInTheRoom('ui_scale.json', scale);
    putInTheRoom('window.json', {'version': 1, 'width': 800});
    // The room's first entry and its last — every one between them leaves
    // too.
    const first = {'version': 1, 'hue': 2};
    putInTheRoom('accent_settings.json', first);
    const last = {'version': 1, 'gap': 3};
    putInTheRoom('workspace_layout.json', last);
    FolderPicker.debugOperatingSystem = 'windows';
    final asked = <String>[];
    FolderPicker.debugSaveDestinationPicker = ({
      required String suggestedName,
      String? initialDirectory,
    }) async {
      asked.add(suggestedName);
      return FolderGrant.granted(
        path: '${folder.path}/$suggestedName',
        kind: GrantKind.file,
      );
    };
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPreferencesDialog(
                context,
                session: session,
                openSessions: [session],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('preferences-export-all')),
    );
    final notice = find.byType(AppConfirmDialog);
    await settleAsync(
      tester,
      () => notice.evaluate().isNotEmpty,
      everyFrame: tester.pump,
    );

    final name = AppText.strings.settingsAllFileName;
    expect(asked, ['$name.$anicelSettingsExtension']);
    final written = await tester.runAsync(
      () => File('${folder.path}/${asked.single}').readAsString(),
    );
    final documents = readSettingsFile(written!)!.documents;
    expect(documents['ui_scale.json'], scale);
    expect(documents['accent_settings.json'], first);
    expect(documents['workspace_layout.json'], last);
    expect(documents, isNot(contains('window.json')));
    expect(
      tester.widget<AppConfirmDialog>(notice).message,
      AppText.strings.settingsExported(name),
    );
  });
}
