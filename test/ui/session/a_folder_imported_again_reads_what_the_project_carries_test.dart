import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/carried_media_fixture.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// Audit 2026-09-24 (card `carried-bytes-audit-0924`): the cut-folder door
/// reads a file's bytes where every placement door reads them — the
/// project's own copy first. 🪦It baked its cels from the files on disk.
///
/// ↩️It also registered the folder's scans and movie, and asked whether the
/// project held them already, so a folder brought in again staged no second
/// copy. Those are the import window's rows now (F-429-Q4), registered
/// through the pool, which takes no file twice.
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

  testWidgets('a scan the project carries bakes from the project\'s copy, '
      'whatever sits on disk under its name', (tester) async {
    session = aSession();
    final scan = await scanned(tester, 'A1.png');
    await tester.runAsync(
      () => session.mediaPool.importMediaFiles([scan], copyIntoProject: true),
    );
    await saveProject(tester, session, directory);
    OriginalFate.replacedBySomethingElse.befall(scan);

    await tester.runAsync(
      () => session.cutFolderDoor.importCutFolder(folderPath: folder),
    );

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
