import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/persistence/save_failure.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuReadFailed;

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/temp_dir.dart';

/// 🚨A save whose drawing the engine would not give back is not a file's
/// refusal: it is told by its own name, no failed copy is tried (it would
/// ask for the same bytes), and nothing says the work was saved (저장's
/// review of the flip lane, 11-09).
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('anicel-engine-read');
  });

  tearDown(() {
    EngineTileLedger.debugBeforeRead = null;
    deleteTempQuietly(folder);
  });

  String at(String name) => '${folder.path.replaceAll('\\', '/')}/$name';

  EditorSessionManager drawnSession() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    drawOnCurrentFrame(s);
    return s;
  }

  void refuseEveryRead() =>
      EngineTileLedger.debugBeforeRead = (_) => throw GpuReadFailed('lost');

  Future<SaveFailure> failureOf(Future<void> save) async {
    try {
      await save;
    } on SaveFailure catch (failure) {
      return failure;
    }
    fail('the save was expected to fail');
  }

  test('a first save: told by name, no failed copy, no half file, and '
      'still unsaved', () async {
    final s = drawnSession();
    final path = at('project.anicel');
    refuseEveryRead();

    final failure = await failureOf(
      s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson),
    );

    expect(failure.cause, SaveFailureCause.engineRead);
    expect(failure.error, isA<GpuReadFailed>());
    expect(failure.failedCopy, isNull);
    expect(failure.copyError, isNull, reason: 'none was tried');
    expect(s.projectFile.failedCopy, isNull);
    expect(s.failedSaveCopies.entries, isEmpty);
    expect(folder.listSync(), isEmpty, reason: 'nothing beside the file');
    expect(s.projectFile.hasUnsavedChanges, isTrue);
  });

  test('over a saved file: the file stays as it was', () async {
    final s = drawnSession();
    final path = at('project.anicel');
    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    final before = File(path).readAsBytesSync();
    drawOnCurrentFrame(s);
    refuseEveryRead();

    final failure = await failureOf(
      s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson),
    );

    expect(failure.cause, SaveFailureCause.engineRead);
    expect(File(path).readAsBytesSync(), before);
    expect(folder.listSync(), hasLength(1), reason: 'only the file');
    expect(s.projectFile.hasUnsavedChanges, isTrue);
  });
}
