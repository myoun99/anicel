import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/save_failure.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/temp_dir.dart';

/// 🚨**WHAT A REFUSED SAVE WROTE GOES ONLY ONCE THE WORK IS SAFE IN THE
/// FAILED COPY — NEVER BEFORE.**
///
/// When the room will not take the failed copy either, the archive the
/// refused save left beside the file may be the only complete copy of the
/// work there is — so it stays where it is.
///
/// ⚠️A file of its own: the room is this test isolate's, and blocking its
/// folder of failed copies refuses every failed copy written after it.
void main() {
  late Directory folder;
  late File blocker;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('anicel-room-refuses');
    FolderPicker.debugOperatingSystem = 'windows';
    // A FILE where the room's folder of failed copies would go: the folder
    // each failed copy is written into cannot be made, on every platform.
    blocker = File(SessionScratch.unsavedFolder())..writeAsStringSync('x');
  });

  tearDown(() {
    FolderPicker.debugOperatingSystem = null;
    blocker.deleteSync();
    deleteTempQuietly(folder);
  });

  test('🎯the room refuses the failed copy too — the archive the refused '
      'save wrote stays beside the file, and nothing is offered', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    drawOnCurrentFrame(s);
    final path = '${folder.path.replaceAll('\\', '/')}/project.anicel';
    Directory(path).createSync();

    SaveFailure? failure;
    try {
      await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    } on SaveFailure catch (refused) {
      failure = refused;
    }

    expect(failure?.error, isA<SaveNotSwappedIn>());
    expect(failure?.failedCopy, isNull);
    expect(failure?.copyError, isNotNull);
    expect(
      [
        for (final entity in folder.listSync())
          if (entity.path.replaceAll('\\', '/').startsWith('$path.tmp-'))
            entity.path,
      ],
      hasLength(1),
      reason: 'it may be the only complete copy of the work left',
    );
    expect(s.failedSaveCopies.entries, isEmpty);
    expect(s.projectFile.failedCopy, isNull);
    expect(s.projectFile.hasUnsavedChanges, isTrue);
  });
}
