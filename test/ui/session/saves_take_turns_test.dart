import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import '../../helpers/placed_sound_conform.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**TWO WRITERS NEVER APPEND TO ONE FILE AT ONCE** — audit
/// 2026-09-24, card `carried-bytes-audit-0924` ⑤.
///
/// The clock stood down for a person (a tick that comes due during a save
/// skips it), and a person did not stand down for the clock: Save pressed
/// while a tick's save ran started a second writer on the same archive —
/// the torn tail the in-flight flag exists to prevent. A save that carries
/// a big movie runs for tens of seconds.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-saves-take-turns');
  });

  tearDown(() => deleteTempQuietly(directory));

  testWidgets('Save pressed while another save runs waits for it to end', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      mediaStagingStore: MediaStagingStore(
        directoryPath: '${directory.path}/Staged',
      ),
      audioConformStore: soundConformStore(),
    );
    addTearDown(session.dispose);
    final path = normalizedMediaPath('${directory.path}/project.anicel');
    await tester.runAsync(
      () => session.projectDoor.saveProjectToFile(
        path,
        asked: SaveAsked.byAPerson,
      ),
    );
    final file = session.projectFile;

    // A save in flight — the clock's, as far as this press can tell.
    file.beginSave();
    var landed = false;
    late final Future<void> pressed;
    // Started in the real zone: its file work cannot finish in fake time.
    await tester.runAsync(() async {
      pressed = session.projectDoor
          .saveProjectToFile(path, asked: SaveAsked.byAPerson)
          .then((_) => landed = true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    expect(landed, isFalse, reason: 'it waits for the save in flight');

    file.endSave();
    await tester.runAsync(() => pressed);

    expect(landed, isTrue, reason: 'and then it is the one that writes');
    expect(file.autosaveShouldStandDown, isFalse, reason: 'and lets go');
  });
}
