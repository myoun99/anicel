import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/carried_media_fixture.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';

/// Audit 2026-09-24 (card `carried-bytes-audit-0924`): the cut-folder door
/// asks the two questions every placement door asks — whether the project
/// already holds a file, and where a file's bytes are (the project's own
/// copy first). 🪦It staged a second copy of what the project already
/// carried, and baked its cels from the files on disk.
void main() {
  late Directory directory;
  late EditorSessionManager session;
  const root = 'csm_13_069_loeks';
  late String folder;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-folder-again');
    folder = '${directory.path}${Platform.pathSeparator}$root';
  });

  tearDown(() => deleteTempQuietly(directory));

  EditorSessionManager aSession() {
    final made = EditorSessionManager(
      initialProject: createDefaultProject(),
      mediaStagingStore: MediaStagingStore(
        directoryPath: '${directory.path}/Staged',
      ),
      audioConformStore: soundConformStore(),
    );
    addTearDown(made.dispose);
    return made;
  }

  Future<String> scanned(WidgetTester tester, String name) async =>
      normalizedMediaPath(
        (await tester.runAsync(
          () => writeSolidPng(
            directory,
            '$root${Platform.pathSeparator}$name',
            rgba: 0x3366FFFF,
          ),
        ))!,
      );

  Future<void> importTheFolder(WidgetTester tester, {required bool carry}) =>
      tester.runAsync(
        () => session.cutFolderDoor.importCutFolder(
          folderPath: folder,
          copyIntoProject: carry,
        ),
      );

  testWidgets('a folder imported again copies nothing the project already '
      'carries', (tester) async {
    session = aSession();
    // A timesheet scan registers in the pool rather than baking.
    final sheet = await scanned(tester, '069_ts.png');
    await importTheFolder(tester, carry: true);
    expect(
      stagedCopyIn(session, sheet),
      isNotNull,
      reason: 'the premise: carried, it was staged at the import',
    );
    await saveProject(tester, session, directory);
    expect(
      session.mediaStagingStore.holdsAnyCopyOf(sheet),
      isFalse,
      reason: 'the premise: the save absorbed the staged copy',
    );

    await importTheFolder(tester, carry: true);

    expect(
      session.mediaStagingStore.holdsAnyCopyOf(sheet),
      isFalse,
      reason: 'the project already holds it — nothing is copied again',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a scan the project carries bakes from the project\'s copy, '
      'whatever sits on disk under its name', (tester) async {
    session = aSession();
    final scan = await scanned(tester, 'A1.png');
    await tester.runAsync(
      () => session.mediaPool.importMediaFiles([scan], copyIntoProject: true),
    );
    await saveProject(tester, session, directory);
    OriginalFate.replacedBySomethingElse.befall(scan);

    await importTheFolder(tester, carry: false);

    final cut = session.repository
        .requireProject()
        .tracks
        .first
        .cuts
        .lastWhere((cut) => cut.name == '069');
    final ink = cut.layers.firstWhere((layer) => layer.name == 'A');
    session.selectCut(cut.id);
    expect(
      session.layerStack.celHasContentForLayer(ink, 0),
      isTrue,
      reason: 'baked from the carried copy — the file on disk is not a PNG',
    );
    await tester.pumpAndSettle();
  });
}
