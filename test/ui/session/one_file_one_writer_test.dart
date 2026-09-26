import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file.dart';
import 'package:anicel/src/ui/session/project_file_door.dart';

import '../../helpers/project_scratch_folder.dart';

/// ONE FILE, ONE WRITER (I-7): with a project per tab, two sessions bound
/// to one archive would each append to a tail the other is extending. The
/// Save As window refuses another tab's file in words; the DOOR refuses it
/// on its own, for every save that did not come through that window.
void main() {
  late Directory folder;
  late String taken;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_one_writer_');
    deleteAfterSessionEnds(folder);
    taken = '${folder.path.replaceAll(r'\', '/')}/Taken.anicel';
  });

  EditorSessionManager sessionBeside() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      fileIsOpenElsewhere: (path) => path == taken,
    );
    addTearDown(session.dispose);
    return session;
  }

  test('a save onto another open project\'s file is refused before a byte '
      'is written, and binds nothing', () async {
    final session = sessionBeside();
    await expectLater(
      session.projectDoor.saveProjectToFile(
        taken,
        asked: SaveAsked.byAPerson,
      ),
      throwsA(isA<FileOpenInAnotherProject>()),
    );
    expect(File(taken).existsSync(), isFalse);
    expect(session.projectFile.path, isNull);
  });

  test('a placed archive at another open project\'s file is not adopted',
      () {
    final session = sessionBeside();
    expect(
      () => session.projectDoor.adoptPlacedArchive(
        taken,
        staged: (mediaInFile: const <String>{}, cleanAsOf: 0),
      ),
      throwsA(isA<FileOpenInAnotherProject>()),
    );
    expect(session.projectFile.path, isNull);
  });

  test('a file no other project holds saves as it always did', () async {
    final session = sessionBeside();
    final free = '${folder.path.replaceAll(r'\', '/')}/Free.anicel';
    await session.projectDoor.saveProjectToFile(
      free,
      asked: SaveAsked.byAPerson,
    );
    expect(File(free).existsSync(), isTrue, reason: 'CONTROL');
    expect(session.projectFile.path, free);
  });
}
