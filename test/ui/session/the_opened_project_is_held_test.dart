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
///
/// …and a CLOSED one lets go of what it held — its own, and only its own,
/// since the process holds a file per open project (I-7).
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
    OpenProjectFile.instance.releaseFor(path);

    final reader = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(reader.dispose);
    await reader.projectDoor.openProjectFromFile(path);

    expect(OpenProjectFile.instance.isHolding(path), isTrue);
  });

  /// `the_project_file_stays_open_test` used to pin 「reading another file
  /// lets the first go」; with a project per tab the first may still be open,
  /// so letting go belongs to the project closing — this.
  test('a closed project lets go of ITS file — and not another open '
      'project\'s (I-7)', () async {
    final directory = Directory.systemTemp.createTempSync('anicel-held-close');
    deleteAfterSessionEnds(directory);
    final pathA = '${directory.path}${Platform.pathSeparator}a.anicel';
    final pathB = '${directory.path}${Platform.pathSeparator}b.anicel';
    final a = EditorSessionManager(initialProject: createDefaultProject());
    final b = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(b.dispose);
    await a.projectDoor.saveProjectToFile(pathA, asked: SaveAsked.byAPerson);
    await b.projectDoor.saveProjectToFile(pathB, asked: SaveAsked.byAPerson);
    expect(
      OpenProjectFile.instance.isHolding(pathA),
      isTrue,
      reason: 'premise: a save holds the file its project is bound to',
    );
    expect(OpenProjectFile.instance.isHolding(pathB), isTrue);

    a.dispose();

    expect(
      OpenProjectFile.instance.isHolding(pathA),
      isFalse,
      reason: 'a closed project has no reason to keep its file undeletable — '
          'and a project with no cels holds its file too, by its save',
    );
    expect(
      OpenProjectFile.instance.isHolding(pathB),
      isTrue,
      reason: 'the other tab\'s file is not the closing one\'s to let go',
    );
  });

  test('opening a different file lets go of the one this session held — '
      'and only that one (I-7)', () async {
    final directory = Directory.systemTemp.createTempSync('anicel-held-swap');
    deleteAfterSessionEnds(directory);
    final pathA = '${directory.path}${Platform.pathSeparator}a.anicel';
    final pathB = '${directory.path}${Platform.pathSeparator}b.anicel';
    final pathC = '${directory.path}${Platform.pathSeparator}c.anicel';
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final other = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(other.dispose);
    await session.projectDoor.saveProjectToFile(
      pathA,
      asked: SaveAsked.byAPerson,
    );
    await other.projectDoor.saveProjectToFile(
      pathC,
      asked: SaveAsked.byAPerson,
    );
    final writer = EditorSessionManager(initialProject: createDefaultProject());
    await writer.projectDoor.saveProjectToFile(
      pathB,
      asked: SaveAsked.byAPerson,
    );
    writer.dispose();

    await session.projectDoor.openProjectFromFile(pathB);

    expect(OpenProjectFile.instance.isHolding(pathB), isTrue);
    expect(
      OpenProjectFile.instance.isHolding(pathA),
      isFalse,
      reason: 'the file this session moved on from, whether or not any cel '
          'of it was ever read',
    );
    expect(
      OpenProjectFile.instance.isHolding(pathC),
      isTrue,
      reason: 'another open project\'s file is not this open\'s to let go',
    );
  });

  test('a SAVE AS lets go of the file it left — the same law as an open '
      '(I-7: a handle per file, so binding elsewhere lets nothing go by '
      'itself)', () async {
    final directory = Directory.systemTemp.createTempSync('anicel-held-as');
    deleteAfterSessionEnds(directory);
    final first = '${directory.path}${Platform.pathSeparator}first.anicel';
    final second = '${directory.path}${Platform.pathSeparator}second.anicel';
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await session.projectDoor.saveProjectToFile(
      first,
      asked: SaveAsked.byAPerson,
    );
    expect(OpenProjectFile.instance.isHolding(first), isTrue, reason: 'CONTROL');

    await session.projectDoor.saveProjectToFile(
      second,
      asked: SaveAsked.byAPerson,
    );

    expect(OpenProjectFile.instance.isHolding(second), isTrue);
    expect(
      OpenProjectFile.instance.isHolding(first),
      isFalse,
      reason: 'every cel moved onto the new file; nothing reads the old one',
    );
    File(first).deleteSync();
  });
}
