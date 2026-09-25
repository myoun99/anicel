import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/open_project_file.dart';
import 'package:anicel/src/services/persistence/same_file.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import '../../helpers/temp_dir.dart';

/// 🚨ONE answer to 「is this the project file」 (audit 09-25): five
/// spellings of it disagreed about case, and the one that held the file
/// compared the strings whole.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('anicel_same_file'));

  tearDown(() {
    OpenProjectFile.instance.release();
    deleteTempQuietly(root);
  });

  String inRoot(String name) => '${root.path}/$name'.replaceAll(r'\', '/');

  test('the separators never tell two files apart', () {
    expect(
      namesTheSameFile(r'C:\work\cut 01.anicel', 'C:/work/cut 01.anicel'),
      isTrue,
    );
    expect(
      namesTheSameFile('C:/work/cut 01.anicel', 'C:/work/cut 02.anicel'),
      isFalse,
    );
  });

  test('letters in another case are the file where the volume folds case — '
      'and only there', () {
    final file = inRoot('Cut.anicel');
    File(file).writeAsBytesSync([1]);
    final other = inRoot('cut.anicel');
    // What this volume says: a folding one finds the file under the other
    // spelling, a case-sensitive one finds nothing there.
    final folds = File(other).existsSync();

    expect(namesTheSameFile(file, other), folds);
  });

  test('a name nothing answers to is not the same file, in any case', () {
    expect(
      namesTheSameFile(inRoot('Gone.anicel'), inRoot('gone.anicel')),
      isFalse,
      reason:
          'a Save As onto a new name must be one — on a case-sensitive '
          'volume that name is another file',
    );
  });

  test('🚨the held file is let go of when asked in another spelling — a '
      'whole write onto it is not refused by our own handle', () {
    final file = inRoot('held.anicel');
    File(file).writeAsBytesSync([1, 2, 3]);
    final held = OpenProjectFile.instance..hold(file);
    expect(held.isHolding, isTrue, reason: 'the premise');

    held.releaseFor(file.replaceAll('/', r'\'));

    expect(
      held.isHolding,
      isFalse,
      reason: '🪦it compared the strings whole, and kept the file open',
    );
  });

  test('and a read in another spelling reads through the handle it has', () {
    final file = inRoot('held.anicel');
    File(file).writeAsBytesSync([1, 2, 3]);
    final held = OpenProjectFile.instance..hold(file);
    final opens = OpenProjectFile.debugOpens;

    expect(held.readAt(file.replaceAll('/', r'\'), 1, 2), [2, 3]);
    expect(OpenProjectFile.debugOpens, opens, reason: 'not opened again');
  });

  test('🚨a save onto the file the session is bound to, spelled otherwise, '
      'is a save — not a Save As', () async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final file = inRoot('scene.anicel');
    await session.projectDoor.saveProjectToFile(
      file,
      asked: SaveAsked.byAPerson,
    );
    session.projectFile.markDirty();
    final opens = OpenProjectFile.debugOpens;

    await session.projectDoor.saveProjectToFile(
      file.replaceAll('/', r'\'),
      asked: SaveAsked.byAPerson,
    );

    expect(
      OpenProjectFile.debugOpens,
      opens,
      reason:
          'the file it is bound to, written in place — a Save As writes it '
          'whole, letting go of the session\'s own handle and taking it back',
    );
  });
}
