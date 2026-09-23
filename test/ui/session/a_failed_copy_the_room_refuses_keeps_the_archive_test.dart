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
/// work there is — so it stays where it is, on every road.
///
/// ⚠️A file of its own: the room is this test isolate's, and blocking its
/// folder of failed copies refuses every failed copy written after it.
void main() {
  late Directory folder;
  late File blocker;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('anicel-room-refuses');
    // A FILE where the room's folder of failed copies would go: the folder
    // each failed copy is written into cannot be made, on every platform.
    blocker = File(SessionScratch.unsavedFolder())..writeAsStringSync('x');
  });

  tearDown(() {
    FolderPicker.debugOperatingSystem = null;
    FolderPicker.debugCoordinatedReplacer = null;
    blocker.deleteSync();
    deleteTempQuietly(folder);
  });

  /// A drawn session's save into a location that refuses it, on the road
  /// [operatingSystem] takes — and what it answered.
  Future<({EditorSessionManager session, String path, SaveFailure? failure})>
  refusedSave(String operatingSystem) async {
    FolderPicker.debugOperatingSystem = operatingSystem;
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
    return (session: s, path: path, failure: failure);
  }

  List<String> besideTheFile(String path) => [
    for (final entity in folder.listSync())
      if (entity.path.replaceAll('\\', '/').startsWith('$path.tmp-'))
        entity.path,
  ];

  test('🎯the room refuses the failed copy too — the archive the refused '
      'save wrote stays beside the file, and nothing is offered', () async {
    final (:session, :path, :failure) = await refusedSave('windows');

    expect(failure?.error, isA<SaveNotSwappedIn>());
    expect(failure?.failedCopy, isNull);
    expect(failure?.copyError, isNotNull);
    expect(
      besideTheFile(path),
      hasLength(1),
      reason: 'it may be the only complete copy of the work left',
    );
    expect(session.failedSaveCopies.entries, isEmpty);
    expect(session.projectFile.failedCopy, isNull);
    expect(session.projectFile.hasUnsavedChanges, isTrue);
  });

  test('🚨the road with no coordinator (Android) keeps it too — the second '
      'archive it wrote in the room does not license the first to go', () async {
    // Answers false, as a platform with no coordinator does.
    FolderPicker.debugCoordinatedReplacer = ({
      required String sourcePath,
      required String destinationPath,
    }) async => false;
    final (:session, :path, :failure) = await refusedSave('android');
    addTearDown(() {
      for (final entity in Directory(SessionScratch.stagedFolder()).listSync()) {
        if (entity.path.contains('replace.tmp-')) {
          try {
            entity.deleteSync();
          } on FileSystemException {
            // Windows handles: the session still reads from it.
          }
        }
      }
    });

    expect(failure?.cause, SaveFailureCause.replaceRefused);
    expect(failure?.failedCopy, isNull);
    expect(
      besideTheFile(path),
      hasLength(1),
      reason: 'the failed copy never landed, so nothing it would have made '
          'safe goes',
    );
    expect(session.projectFile.hasUnsavedChanges, isTrue);
  });
}
