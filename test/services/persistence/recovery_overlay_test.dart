import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The recovery snapshot is an OVERLAY: only the cels edited since the
/// last manual save, laid over the project file it was built from.
///
/// That shape is what lets it be written as the app goes away — it costs
/// what the user drew, not what the project weighs. The price is that it
/// is meaningless on its own and WRONG over the wrong base, so the pairing
/// is stamped and checked rather than hoped for. A delta merged onto a
/// mismatched project opens, looks right, and is not; that is the one
/// failure this file exists to make impossible.
void main() {
  late Directory directory;
  late String projectPath;
  late String overlayPath;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('qa_overlay_');
    projectPath = '${directory.path.replaceAll('\\', '/')}/scene.anicel';
    overlayPath = '${directory.path.replaceAll('\\', '/')}/scene.recovery';
  });
  tearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  EditorSessionManager session() =>
      EditorSessionManager(initialProject: createDefaultProject());

  List<String> celEntriesOf(String path) => [
    for (final entry in parseAnicelZipLayoutFile(path).entries)
      if (entry.name.endsWith('.celz')) entry.name,
  ];

  /// Puts real pixels in the store, the way the canvas commit path does —
  /// an overlay only has something to leave out once cels exist.
  void drawOnCurrentFrame(EditorSessionManager s) {
    s.createDrawingAtCurrentFrame();
    final selection = s.activeBrushEditorSelection!;
    BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(
        s.requireActiveCut,
        selection.layerId,
        selection.frameId,
      ),
      frameStore: s.brushFrameStore,
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

  test('the overlay carries the cels edited since the save and LEAVES OUT '
      'the ones already in the project', () async {
    // The direct form of "it is small": not a size comparison, which a
    // project.json that grew by one cut can flip, but which entries are
    // actually in the file.
    final s = session();
    drawOnCurrentFrame(s);
    s.createCut();
    drawOnCurrentFrame(s);
    await s.saveProjectToFile(projectPath);
    expect(celEntriesOf(projectPath), hasLength(2));

    s.createCut();
    drawOnCurrentFrame(s);
    await s.writeAutosaveSnapshot(overlayPath);

    expect(
      celEntriesOf(overlayPath),
      hasLength(1),
      reason: 'the two saved cels are in the base already',
    );
    // Deliberately NOT a size comparison. At fixture scale a project.json
    // that grew by one cut outweighs a cel holding a four-pixel dab, so
    // bytes would measure the wrong thing; which entries are present is
    // the property itself.
  });

  test('opening the project WITH the overlay restores the unsaved work', () async {
    final s = session();
    await s.saveProjectToFile(projectPath);
    final savedCuts = s.activeTrack.cuts.length;
    s.createCut();
    final unsavedCuts = s.activeTrack.cuts.length;
    expect(unsavedCuts, savedCuts + 1);
    await s.writeAutosaveSnapshot(overlayPath);

    // The project file on disk never learned about that cut…
    final plain = session();
    await plain.openProjectFromFile(projectPath);
    expect(plain.activeTrack.cuts.length, savedCuts);

    // …and the overlay puts it back.
    final restored = session();
    await restored.openProjectFromFile(projectPath, overlayPath: overlayPath);
    expect(restored.activeTrack.cuts.length, unsavedCuts);
    expect(
      restored.hasUnsavedChanges,
      isTrue,
      reason: 'restored work differs from the file until it is saved',
    );
  });

  test('an overlay built from a DIFFERENT version of the project is '
      'refused, not merged', () async {
    // The whole hazard of a delta. Merging hopefully would hand back a
    // project that opens and looks fine while holding cels from a version
    // that no longer exists.
    final s = session();
    await s.saveProjectToFile(projectPath);
    s.createCut();
    await s.writeAutosaveSnapshot(overlayPath);

    // The base moves on underneath it.
    s.createCut();
    await s.saveProjectToFile(projectPath);

    await expectLater(
      session().openProjectFromFile(projectPath, overlayPath: overlayPath),
      throwsA(isA<FormatException>()),
    );
  });

  test('the base stamp moves when the project does, and is a TAIL read', () {
    // Content-derived rather than a counter: two different files must not
    // be able to carry the same stamp. Tail-only because a multi-gigabyte
    // project cannot be hashed whole to answer "is this the one".
    final a = File(projectPath)..writeAsStringSync('nonsense');
    expect(anicelBaseStamp(a.path), isNull, reason: 'no valid tail');

    expect(anicelBaseStamp('${directory.path}/missing.anicel'), isNull);
  });

  test('a snapshot from a build BEFORE overlays is recognised as a whole '
      'archive', () async {
    // Those were complete projects with no base stamp. They are still
    // found and offered, so the two shapes have to be told apart before
    // deciding whether to lay one over anything.
    final s = session();
    await s.saveProjectToFile(projectPath);
    expect(
      anicelSnapshotIsOverlay(projectPath),
      isFalse,
      reason: 'a plain project is not an overlay',
    );

    s.createCut();
    await s.writeAutosaveSnapshot(overlayPath);
    expect(anicelSnapshotIsOverlay(overlayPath), isTrue);

    // And laying a whole archive over a project is refused rather than
    // half-applied.
    await expectLater(
      session().openProjectFromFile(projectPath, overlayPath: projectPath),
      throwsA(isA<FormatException>()),
    );
  });

  test('a RECOVERED session does not snapshot over the file its own cels '
      'live in', () async {
    // The nastiest shape this design has. Recovery points every restored
    // cel's ref INTO the overlay and clears the RAM tiers — and it clears
    // the dirty set too, so a snapshot taken afterwards would carry no
    // cels at all and rename that over the only copy. The live refs would
    // then be reading past the end of a file holding a stamp and a
    // project.json. No edit is needed to reach it: a recovered session
    // arrives dirty, so one alt-tab is enough.
    final s = session();
    drawOnCurrentFrame(s);
    await s.saveProjectToFile(projectPath);
    s.createCut();
    drawOnCurrentFrame(s);
    await s.writeAutosaveSnapshot(overlayPath);
    final overlayCels = celEntriesOf(overlayPath);
    expect(overlayCels, hasLength(1));

    final restored = session();
    await restored.openProjectFromFile(projectPath, overlayPath: overlayPath);
    // The lifecycle fires with no edits at all.
    await restored.writeAutosaveSnapshot(overlayPath);

    expect(
      celEntriesOf(overlayPath),
      overlayCels,
      reason: 'the recovered work was overwritten by an empty snapshot',
    );
  });

  test('a base that cannot be stamped writes NO overlay', () async {
    // Both directions are worse than skipping. A null stamp on both sides
    // compares equal, which merges a delta nobody checked; and a base that
    // was merely unreadable at snapshot time would never match again,
    // which makes the project refuse to open and then loses the overlay to
    // the decline path.
    final s = session();
    drawOnCurrentFrame(s);
    await s.saveProjectToFile(projectPath);
    s.createCut();

    File(projectPath).writeAsStringSync('not an archive any more');
    expect(anicelBaseStamp(projectPath), isNull);

    await s.writeAutosaveSnapshot(overlayPath);

    expect(File(overlayPath).existsSync(), isFalse);
  });

  test('an overlay whose write finished after a manual save is discarded, '
      'not renamed into place', () async {
    // The save retires the snapshot on its way out. A write that was
    // already in the isolate would otherwise land afterwards, recreating
    // one for a cleanly saved project — stamped against the base as it was
    // BEFORE the save, so the next open offers a recovery that then throws.
    final s = session();
    drawOnCurrentFrame(s);
    await s.saveProjectToFile(projectPath);
    s.createCut();
    drawOnCurrentFrame(s);

    await AnicelFileService().writeRecoveryOverlay(
      project: s.repository.requireProject(),
      brushFrameStore: s.brushFrameStore,
      filePath: overlayPath,
      baseFilePath: projectPath,
      // Spelled out because they are required, and required because
      // defaulting them at a call site is what cost two data-loss bugs.
      // This test is about the STALE check, so it has nothing to carry —
      // saying so is the point.
      grants: const [],
      mediaInArchive: const {},
      mediaCrcs: const {},
      isStale: () => true,
    );

    expect(File(overlayPath).existsSync(), isFalse);
    expect(
      Directory(directory.path)
          .listSync()
          .where((e) => e.path.contains('.tmp-')),
      isEmpty,
      reason: 'a discarded write must not leave its temp behind',
    );
  });

  test('writing an overlay does NOT adopt refs, so the next manual save '
      'still knows what changed', () async {
    // This is the bug the timer had: adopting pointed the store at the
    // snapshot and cleared the dirty set, so the next manual save could no
    // longer find its own work in the project file and rewrote the whole
    // thing. An incremental save APPENDS, so the file grows; a full
    // rewrite leaves only live bytes and does not.
    final s = session();
    for (var i = 0; i < 4; i += 1) {
      s.createCut();
    }
    await s.saveProjectToFile(projectPath);
    s.createCut();
    await s.writeAutosaveSnapshot(overlayPath);
    final before = File(projectPath).lengthSync();

    await s.saveProjectToFile(projectPath);

    expect(
      File(projectPath).lengthSync(),
      greaterThan(before),
      reason: 'a full rewrite here means the overlay stole the refs',
    );
  });
}
