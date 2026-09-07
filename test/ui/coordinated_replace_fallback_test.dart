import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 실측 (08-26, iPhone + Google Drive): a File Provider can refuse plain
/// in-place writes outright. The save's fallback writes the whole archive
/// app-locally and swaps it over the provider file through the platform's
/// file coordinator — and the session carries on as if the save were
/// ordinary: refs repointed to the target (byte-identical copy, same
/// offsets), dirty flag down, next save incremental again.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_coord_replace_');
  });
  tearDown(() {
    FolderPicker.debugOperatingSystem = null;
    FolderPicker.debugCoordinatedReplacer = null;
    try {
      folder.deleteSync(recursive: true);
    } on Object {
      // Windows handles.
    }
    // The fallback deliberately leaves its staging file for the 30-day
    // sweep; a test must not leave it for the NEXT test.
    final recovery = Directory(AppSave.recoveryDirectory());
    if (recovery.existsSync()) {
      for (final entity in recovery.listSync()) {
        if (entity.path.replaceAll('\\', '/').contains('/replace.tmp-')) {
          try {
            entity.deleteSync();
          } on Object {
            // Windows handles.
          }
        }
      }
    }
  });

  void drawOnCurrentFrame(EditorSessionManager s) {
    s.createDrawingAtCurrentFrame();
    final selection = s.activeBrushEditorSelection!;
    BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(
        s.requireActiveCut,
        selection.layerId,
        selection.frameId,
      ),
      frameStore: s.renderCaches.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: s.requireActiveCut.canvasSize,
        tileSize: 256,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 10, y: 10),
          color: 0xFF000000,
          size: 4,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
  }

  /// A path every plain write refuses: a DIRECTORY sits where the file
  /// would go, so the full rewrite's rename-over throws — the observable
  /// shape of the 실측 (a provider refusing the write). ⚠️ This fixture is
  /// HARSHER than the real Drive in one way: reads through it fail too,
  /// so it can only stand in for the scenario where the refs do NOT point
  /// into the refused file (RAM-resident work — exactly the field case,
  /// where the first save never landed). Whether a REAL provider serves
  /// reads while refusing writes is `C-save-ipad-saveas`'s retest.
  String refusingLocation(String name) {
    final path = '${folder.path.replaceAll('\\', '/')}/$name';
    Directory(path).createSync();
    return path;
  }

  test('🚨 a refused write falls back to the coordinated replace, and the '
      'session carries on as an ordinary save', () async {
    FolderPicker.debugOperatingSystem = 'ios';
    var replaces = 0;
    FolderPicker.debugCoordinatedReplacer = ({
      required String sourcePath,
      required String destinationPath,
    }) async {
      replaces += 1;
      // What the native coordinator does, minus the provider: the
      // destination's content becomes the source's, whole.
      final blocking = Directory(destinationPath);
      if (blocking.existsSync()) {
        blocking.deleteSync(recursive: true);
      }
      File(sourcePath).copySync(destinationPath);
      return true;
    };

    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    drawOnCurrentFrame(s);
    final path = refusingLocation('drive.anicel');

    await s.projectDoor.saveProjectToFile(path);

    expect(replaces, 1);
    final layout = parseAnicelZipLayoutFile(path);
    expect(layout.projectEntry(), isNotNull);
    expect(
      layout.entries.where((e) => e.name.endsWith('.celz')),
      isNotEmpty,
      reason: 'the drawing is in the replaced file',
    );
    expect(s.projectFile.hasUnsavedChanges, isFalse);
    expect(s.projectFile.path, path);

    final refPaths = s.renderCaches.brushFrameStore
        .bakedSnapshotForSave()
        .fileRefs
        .values
        .map((ref) => ref.filePath.replaceAll('\\', '/'))
        .toSet();
    expect(
      refPaths,
      {path},
      reason: 'the copy is byte-identical, so the refs simply repoint — '
          'a session left reading the staging temp dies when the sweep '
          'takes it',
    );

    // The location takes writes now (the fake replaced the directory
    // with a real file): the NEXT save is ordinary — no coordinator.
    drawOnCurrentFrame(s);
    await s.projectDoor.saveProjectToFile(path);
    expect(replaces, 1, reason: 'the fallback is per-refusal, not a mode');
  });

  test('a replace that ALSO fails rethrows loudly and changes nothing', () async {
    FolderPicker.debugOperatingSystem = 'ios';
    FolderPicker.debugCoordinatedReplacer = ({
      required String sourcePath,
      required String destinationPath,
    }) async => false;

    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    drawOnCurrentFrame(s);
    final path = refusingLocation('refused.anicel');

    await expectLater(
      s.projectDoor.saveProjectToFile(path),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      s.projectFile.hasUnsavedChanges,
      isTrue,
      reason: 'nothing landed at the destination, so nothing may claim to',
    );
    expect(
      s.projectFile.path,
      isNull,
      reason: 'a failed first save must not adopt the path either',
    );
  });

  test('desktop refusals stay loud — no coordinator to appeal to', () async {
    // Pinned, not inherited (ios-distribution-setup의 macOS 러너 함정):
    // the macOS CI runner is desktop hardware on a SCOPED platform, so a
    // test that relies on the host being non-scoped takes the wrong
    // branch exactly there.
    FolderPicker.debugOperatingSystem = 'windows';
    FolderPicker.debugCoordinatedReplacer = ({
      required String sourcePath,
      required String destinationPath,
    }) async => fail('desktop must not reach the coordinator');

    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    drawOnCurrentFrame(s);
    final path = refusingLocation('desktop.anicel');

    await expectLater(
      s.projectDoor.saveProjectToFile(path),
      throwsA(isA<FileSystemException>()),
    );
  });
}
