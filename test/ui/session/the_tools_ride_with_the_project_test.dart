import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:anicel/src/ui/session/project_resume.dart' show ToolChoiceBridge;

import '../../helpers/opened_session.dart';
import '../../helpers/project_scratch_folder.dart';

/// F-123: what the tools were holding rides with the save and is handed back
/// to whoever holds the tools when the project opens.
///
/// The door does not know what a tool is — the shell's tool notifier and the
/// workspace's preset library do — so it carries the choice through the
/// bridge they install, and these pins stand in for them with a fake one.
void main() {
  late Directory directory;
  late String projectPath;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('qa-tools-resume-');
    deleteAfterSessionEnds(directory);
    projectPath = '${directory.path}/scene.anicel';
  });

  test('what the bridge reads at save is what it is handed on open', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.projectDoor.toolChoice = (
      read: () => {'tool': 'eraser', 'fillOpacity': 0.5},
      resume: (_) {},
    );
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    Map<String, Object?>? handed;
    final reopened = await openedSession(
      projectPath,
      before: (session) => session.projectDoor.toolChoice = (
        read: () => const {},
        resume: (saved) => handed = saved,
      ),
    );
    expect(handed, {'tool': 'eraser', 'fillOpacity': 0.5});
    reopened.dispose();
  });

  test('a file saved before tools were kept hands back an EMPTY choice — '
      'resuming nothing changes nothing', () async {
    File(projectPath).writeAsBytesSync(
      buildAnicelArchiveBytes(project: createDefaultProject(), cels: const []),
    );

    Map<String, Object?>? handed;
    final opened = await openedSession(
      projectPath,
      before: (session) => session.projectDoor.toolChoice = (
        read: () => const {},
        resume: (saved) => handed = saved,
      ),
    );
    expect(handed, isEmpty);
    opened.dispose();
  });

  test('🚨I-7: a file read before its tab exists hands the choice to the '
      'bridge the window installs LATER — once, not at every switch', () async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.projectDoor.toolChoice = (
      read: () => {'tool': 'eraser'},
      resume: (_) {},
    );
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    // Read with no bridge: the tab it will show in does not exist yet.
    final read = await openedSession(projectPath);
    addTearDown(read.dispose);

    final handed = <Map<String, Object?>>[];
    ToolChoiceBridge bridge() => (
      read: () => const {},
      resume: handed.add,
    );
    read.projectDoor.toolChoice = bridge();
    expect(handed, [
      {'tool': 'eraser'},
    ], reason: 'the tab came on screen: the tools come back');
    read.projectDoor.toolChoice = bridge();
    expect(handed, hasLength(1), reason: 'coming forward again is no open');
  });
}
