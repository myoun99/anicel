import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/save_failure.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**A SAVE THE FILE REFUSES STILL LANDS — IN THE FAILED COPY.**
///
/// 🗣️유저 2026-09-23 (whole-write-temp-beside-the-file): Q1 「지금대로 +
/// 실패 시 앱 룸으로 옮겨 보관」, Q2 「이번 실행 동안만 — 앱을 닫으면
/// 사라진다」, then 「실패하면 앱컨테이너에 같은파일로 계속 증분저장? …
/// 해당파일 지정해서 백업할수있게」.
///
/// The refusing file is a DIRECTORY standing where the file would go: every
/// write's rename-over throws there, on every platform — the observable
/// shape of a file another program holds.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('anicel-failed-copy');
    // Pinned: a desktop, with no coordinator to appeal to.
    FolderPicker.debugOperatingSystem = 'windows';
  });

  tearDown(() {
    FolderPicker.debugOperatingSystem = null;
    deleteTempQuietly(folder);
  });

  String refusingLocation(String name) {
    final path = '${folder.path.replaceAll('\\', '/')}/$name';
    Directory(path).createSync();
    return path;
  }

  EditorSessionManager drawnSession() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    drawOnCurrentFrame(s);
    return s;
  }

  Future<SaveFailure> failureOf(Future<void> save) async {
    try {
      await save;
    } on SaveFailure catch (failure) {
      return failure;
    }
    fail('the save was expected to be refused');
  }

  bool holdsADrawing(String archive) => parseAnicelZipLayoutFile(
    archive,
  ).entries.any((entry) => entry.name.endsWith('.celz'));

  List<String> straysBeside(String path) => [
    for (final entity in Directory(path).parent.listSync())
      if (entity.path.replaceAll('\\', '/').startsWith('$path.tmp-'))
        entity.path,
  ];

  test('🎯a save the file refuses lands in ONE failed copy in the run\'s '
      'room — and nothing is left beside the user\'s file', () async {
    final s = drawnSession();
    final path = refusingLocation('project.anicel');

    final failure = await failureOf(
      s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson),
    );

    final copy = failure.failedCopy!;
    expect(failure.error, isA<SaveNotSwappedIn>());
    expect(
      copy.replaceAll('\\', '/'),
      startsWith(SessionScratch.unsavedFolder()),
    );
    expect(holdsADrawing(copy), isTrue, reason: 'the work is in it');
    expect(straysBeside(path), isEmpty, reason: 'Q1: 원본 옆에 두지 않는다');
    expect(s.projectFile.failedCopy, copy);
    expect(s.failedSaveCopies.entries.map((e) => e.copyPath), [copy]);
    expect(
      s.projectFile.hasUnsavedChanges,
      isTrue,
      reason: 'the project file still does not have it',
    );
  });

  test('🚨the clock keeps the SAME failed copy current and never asks the '
      'file that refused — a person\'s save does', () async {
    final s = drawnSession();
    final path = refusingLocation('project.anicel');
    final copy = (await failureOf(
      s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson),
    )).failedCopy!;
    final before = File(copy).lengthSync();

    drawOnCurrentFrame(s);
    s.projectFile.markDirty();
    // Asking the refusing file would fail again and be TOLD; the clock
    // writes the failed copy and says nothing.
    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byTheClock);

    expect(s.projectFile.failedCopy, copy, reason: 'the same file');
    expect(File(copy).lengthSync(), isNot(before), reason: 'written again');
    expect(s.projectFile.failedCopyIsCurrent, isTrue);
    expect(Directory(path).existsSync(), isTrue, reason: 'untouched');

    // A person's save asks the file again, and is told again.
    drawOnCurrentFrame(s);
    s.projectFile.markDirty();
    final again = await failureOf(
      s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson),
    );
    expect(again.failedCopy, copy, reason: 'still the one failed copy');
  });

  test('a tick with nothing new for the failed copy writes nothing', () async {
    final s = drawnSession();
    final path = refusingLocation('project.anicel');
    final copy = (await failureOf(
      s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson),
    )).failedCopy!;
    final bytes = File(copy).readAsBytesSync();

    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byTheClock);

    expect(File(copy).readAsBytesSync(), bytes);
  });

  test('🎯the first save the file takes lets the failed copy go', () async {
    final s = drawnSession();
    final path = refusingLocation('project.anicel');
    final copy = (await failureOf(
      s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson),
    )).failedCopy!;

    Directory(path).deleteSync();
    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);

    expect(holdsADrawing(path), isTrue, reason: 'the file has the work now');
    expect(s.projectFile.hasUnsavedChanges, isFalse);
    expect(s.projectFile.failedCopy, isNull);
    expect(
      File(copy).existsSync(),
      isFalse,
      reason: '다음 저장이 성공하면 지운다 — once nothing reads from it',
    );
    expect(s.failedSaveCopies.entries, isEmpty);
    expect(
      s.failedSaveCopies.projectOf(copy),
      isNull,
      reason: 'superseded, not merely gone — a copy something still reads '
          'from is not offered for a backup either',
    );
  });

  test('a failed copy outlives its binding — another project in the same '
      'run can still back it up', () async {
    final s = drawnSession();
    final path = refusingLocation('project.anicel');
    final copy = (await failureOf(
      s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson),
    )).failedCopy!;

    s.projectFile.bindToOpenedFile(
      '${folder.path}/another.anicel',
      entryNames: const {},
      unsaved: false,
    );

    expect(s.projectFile.failedCopy, isNull, reason: 'not this binding\'s');
    expect(s.failedSaveCopies.entries.map((e) => e.copyPath), [copy]);
    expect(File(copy).existsSync(), isTrue);
  });

  test('🎯a backup is the failed copy, brought up to date first — and the '
      'session stays where it saves', () async {
    final s = drawnSession();
    final path = refusingLocation('project.anicel');
    final copy = (await failureOf(
      s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson),
    )).failedCopy!;
    drawOnCurrentFrame(s);
    s.projectFile.markDirty();
    final destination = '${folder.path.replaceAll('\\', '/')}/kept.anicel';

    await s.projectDoor.backUpFailedCopy(copy, destination);

    expect(
      s.projectFile.failedCopyIsCurrent,
      isTrue,
      reason: 'the pen was ahead of the failed copy, and the backup waited '
          'for it to catch up',
    );
    expect(File(destination).readAsBytesSync(), File(copy).readAsBytesSync());
    expect(holdsADrawing(destination), isTrue);
    expect(straysBeside(destination), isEmpty);
    expect(s.projectFile.failedCopy, copy, reason: 'not moved to the backup');
  });
}
