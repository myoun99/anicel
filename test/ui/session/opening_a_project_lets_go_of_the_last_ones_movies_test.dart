import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import '../../helpers/carried_media_fixture.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/temp_dir.dart';
import '../../models/import/tvpp_test_builder.dart';

/// Audit 2026-09-24, card `carried-bytes-audit-0924` ①.
///
/// The canvas keeps a movie row's movie open by PATH for the life of the
/// session, and since the carried-bytes law a path answers the project's
/// OWN copy. Opening another project in the same session left the last
/// project's movies open: a row of the new project with the same path
/// decoded the LAST project's bytes, and the last project's file stayed
/// open until the app quit.
void main() {
  late Directory directory;
  late ReadingVideoBackend movies;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-lets-go');
    debugVideoDecodeBackend = movies = ReadingVideoBackend();
  });

  tearDown(() {
    debugVideoDecodeBackend = null;
    deleteTempQuietly(directory);
  });

  /// A session carrying the movie at [movie] as it is NOW, placed as a
  /// reference row and saved to [projectPath].
  Future<EditorSessionManager> carriedAndSaved(
    WidgetTester tester, {
    required String movie,
    required String projectPath,
    required String staging,
  }) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      mediaStagingStore: MediaStagingStore(directoryPath: staging),
      audioConformStore: soundConformStore(),
    );
    addTearDown(session.dispose);
    session.playbackRig.prerenderScheduler.beginInputHold();
    await tester.runAsync(() async {
      await session.mediaPool.importMediaFiles([movie], copyIntoProject: true);
      await session.importDoors.importVideoFile(
        path: movie,
        settings: const ImportFileSettings(
          mode: ImportFileMode.keepInside,
          sound: false,
        ),
      );
      await session.projectDoor.saveProjectToFile(
        projectPath,
        asked: SaveAsked.byAPerson,
      );
    });
    return session;
  }

  testWidgets('a row of the project opened next, with the same path, reads '
      'THAT project\'s copy — not the last one\'s', (tester) async {
    final movie = normalizedMediaPath(
      (await tester.runAsync(() => writeCarriedMovie(directory)))!,
    );
    final first = normalizedMediaPath('${directory.path}/first.anicel');
    final second = normalizedMediaPath('${directory.path}/second.anicel');
    final session = await carriedAndSaved(
      tester,
      movie: movie,
      projectPath: first,
      staging: '${directory.path}/StagedFirst',
    );
    // The same path, other bytes — carried by ANOTHER project.
    await tester.runAsync(
      () => written(directory, 'take.mp4', [
        ...movieMagic.codeUnits,
        ...noise(2048).reversed,
      ]),
    );
    await carriedAndSaved(
      tester,
      movie: movie,
      projectPath: second,
      staging: '${directory.path}/StagedSecond',
    );
    movies.openedAt.clear();
    await tester.runAsync(
      () => session.movieCels.hydrate(session.requireActiveCut, 0),
    );
    expect(
      movies.openedAt,
      isEmpty,
      reason: 'the premise: the canvas keeps the movie it has open',
    );

    await tester.runAsync(
      () => session.projectDoor.openProjectFromFile(second),
    );
    await tester.runAsync(
      () => session.movieCels.hydrate(session.requireActiveCut, 0),
    );

    expect(
      movies.openedAt.map((opened) => opened.path),
      [second],
      reason: 'the row of the project now open reads that project',
    );
    expect(
      session.requireActiveCut.layers.where(isMovieReference),
      isNotEmpty,
      reason: 'the premise: the opened project has a movie row',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a .tvpp opened in its place lets go of them too — the '
      'other door that replaces the whole project', (tester) async {
    final movie = normalizedMediaPath(
      (await tester.runAsync(() => writeCarriedMovie(directory)))!,
    );
    final path = normalizedMediaPath('${directory.path}/held.anicel');
    final session = await carriedAndSaved(
      tester,
      movie: movie,
      projectPath: path,
      staging: '${directory.path}/Staged',
    );
    await tester.runAsync(() => session.projectDoor.openProjectFromFile(path));
    await tester.runAsync(
      () => session.movieCels.hydrate(session.requireActiveCut, 0),
    );
    expect(
      session.projectFile.heldArchiveEntries,
      isNotEmpty,
      reason: 'the premise: the canvas holds the entry it reads',
    );

    final b = TvppBuilder()
      ..projectProperties(cameraWidth: 64, cameraHeight: 48)
      ..clipProperties('next')
      ..clipHeader(width: 64, height: 48)
      ..layerHead('A', end: 0, count: 1, layerId: 901)
      ..layerExt(const {})
      ..zchkSlot(srawRecord(List<int>.filled(64 * 48, 0), 64, 48))
      ..clipConfig();
    final tvpp = '${directory.path}${Platform.pathSeparator}next.tvpp';
    File(tvpp).writeAsBytesSync(b.bytes);
    await tester.runAsync(() async {
      expect(await session.tvppDoor.openAsProject(tvppPath: tvpp), isNotNull);
      // The letting go is not awaited by the door; give it its turn.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    expect(
      session.projectFile.heldArchiveEntries,
      isEmpty,
      reason: 'the project it replaced is let go of, movies and all',
    );
    await tester.pumpAndSettle();
  });
}
