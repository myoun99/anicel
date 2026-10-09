import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// 🗣️유저 10-09: 「애초에 프로젝트이름=파일이름아닌가? 애니셀이든 뭐든」 — a
/// project is called what its file is called. The name the exports, the
/// sheets' titles and Save As read follows the file its session is bound
/// to, as its tab does. ↩️It was set once, when the project was made: a new
/// project saved as `cut12.anicel` still exported as 「Untitled Project」.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('anicel-named-as-file');
    FolderPicker.debugOperatingSystem = 'windows';
  });

  tearDown(() {
    FolderPicker.debugOperatingSystem = null;
    deleteTempQuietly(folder);
  });

  String at(String name) => '${folder.path.replaceAll('\\', '/')}/$name';

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  test('🎯a new project saved as cut12.anicel is called cut12 — and, saved '
      'again elsewhere, by that file\'s name', () async {
    final s = session();
    expect(s.repository.requireProject().name, isNot('cut12'));

    await s.projectDoor.saveProjectToFile(
      at('cut12.anicel'),
      asked: SaveAsked.byAPerson,
    );
    expect(s.repository.requireProject().name, 'cut12');
    expect(
      s.projectFile.hasUnsavedChanges,
      isFalse,
      reason: 'the name is the file\'s, not an edit to save',
    );

    await s.projectDoor.saveProjectToFile(
      at('cut12 v2.anicel'),
      asked: SaveAsked.byAPerson,
    );
    expect(s.repository.requireProject().name, 'cut12 v2');
  });

  test('a file opened is called by its own name, whatever name it was '
      'saved with', () {
    final s = session();

    s.projectFile.bindToOpenedFile(
      at('renamed on disk.anicel'),
      mediaInFile: const {},
      fontsInFile: const {},
      unsaved: false,
    );

    expect(s.repository.requireProject().name, 'renamed on disk');
  });
}
