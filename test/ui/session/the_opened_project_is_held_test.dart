import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/open_project_file.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart';

import '../../helpers/project_scratch_folder.dart';

/// 🚨★★★**AN OPENED PROJECT IS HELD FROM THE MOMENT IT OPENS.** The session's
/// hold on the `.anicel` is what keeps a clean cel's only copy from being
/// deleted or moved out from under it ([OpenProjectFile]) — and it used to
/// begin at the first cel READ, so a project that opened on an empty cut, or
/// one nobody had scrolled to a drawing in yet, was not held at all (F-72
/// follow-up, 2026-09-11).
void main() {
  test('opening a project holds its file before anything reads it', () async {
    final directory = Directory.systemTemp.createTempSync('anicel-held-open');
    deleteAfterSessionEnds(directory);
    final path = '${directory.path}${Platform.pathSeparator}opened.anicel';
    final writer = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(writer.dispose);
    await writer.projectDoor.saveProjectToFile(
      path,
      asked: SaveAsked.byAPerson,
    );
    OpenProjectFile.instance.release();

    final reader = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(reader.dispose);
    await reader.projectDoor.openProjectFromFile(path);

    expect(OpenProjectFile.instance.heldPath, path);
  });
}
