import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import '../../helpers/carried_media_fixture.dart';
import '../../helpers/opened_session.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';

/// Audit 2026-09-24, card `carried-bytes-audit-0924` ①.
///
/// The canvas keeps a movie row's movie open by PATH for the life of the
/// session, and since the carried-bytes law a path answers the project's
/// OWN copy. While an open REPLACED the project of its session, the last
/// project's movies stayed open: a row of the new project with the same
/// path decoded the LAST project's bytes, and the last project's file stayed
/// open until the app quit.
///
/// A file opens as a session of its own now (I-7), so what is left to pin is
/// the two halves of 「a project's movies are its own」: a project open in
/// another tab reads ITS copy under the same path, and a project that
/// closes lets go of every movie it opened.
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

  EditorSessionManager aSession(String staging, [Project? project]) =>
      EditorSessionManager(
        initialProject: project ?? createDefaultProject(),
        mediaStagingStore: MediaStagingStore(directoryPath: staging),
        audioConformStore: soundConformStore(),
      );

  /// The session [path] opens as, staging in a folder of its own.
  Future<EditorSessionManager> opened(WidgetTester tester, String path) async =>
      (await tester.runAsync(
        () => openedSession(
          path,
          make: (project) =>
              aSession('${directory.path}/StagedOpened', project),
        ),
      ))!;

  /// A session carrying the movie at [movie] as it is NOW, placed as a
  /// reference row and saved to [projectPath].
  Future<EditorSessionManager> carriedAndSaved(
    WidgetTester tester, {
    required String movie,
    required String projectPath,
    required String staging,
  }) async {
    final session = aSession(staging);
    addTearDown(session.dispose);
    session.playbackRig.prerenderScheduler.beginInputHold();
    String? staged;
    await tester.runAsync(() async {
      await session.mediaPool.importMediaFiles([movie], copyIntoProject: true);
      staged = stagedCopyIn(session, movie)?.path;
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
    // The row it placed follows its bytes from the staged copy onto the file
    // the save wrote (`a_reader_follows_what_the_save_absorbed_test`), and
    // the copy goes from the disk once it has — let that land before
    // anything counts the opens the one decoder here has seen.
    // ⛔Nothing staged would pass the wait below without waiting for
    // anything (audit 09-25): the import is what staged it.
    expect(staged, isNotNull, reason: 'the premise: the import staged it');
    bool followed() => !File(staged!).existsSync();
    for (var i = 0; i < 60 && !followed(); i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(followed(), isTrue, reason: 'the premise');
    return session;
  }

  testWidgets('a row of the project open in another tab, with the same '
      'path, reads THAT project\'s copy', (tester) async {
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

    final next = await opened(tester, second);
    addTearDown(next.dispose);
    await tester.runAsync(
      () => next.movieCels.hydrate(next.requireActiveCut, 0),
    );

    expect(
      movies.openedAt.map((opened) => opened.path),
      [second],
      reason: 'the row of the project opened in a tab of its own reads that '
          'project',
    );
    expect(
      next.requireActiveCut.layers.where(isMovieReference),
      isNotEmpty,
      reason: 'the premise: the opened project has a movie row',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('🚨a project that CLOSES lets go of every movie it opened',
      (tester) async {
    final movie = normalizedMediaPath(
      (await tester.runAsync(() => writeCarriedMovie(directory)))!,
    );
    final path = normalizedMediaPath('${directory.path}/held.anicel');
    await carriedAndSaved(
      tester,
      movie: movie,
      projectPath: path,
      staging: '${directory.path}/Staged',
    );
    final session = await opened(tester, path);
    await tester.runAsync(
      () => session.movieCels.hydrate(session.requireActiveCut, 0),
    );
    final file = session.projectFile;
    expect(
      file.heldArchiveEntries,
      isNotEmpty,
      reason: 'the premise: the canvas holds the entry it reads',
    );

    await tester.runAsync(() async {
      session.dispose();
      // The letting go is not awaited by the close; give it its turn.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    expect(
      file.heldArchiveEntries,
      isEmpty,
      reason: 'a tab that closes keeps nothing of its project open (audit '
          '09-25: nothing pinned the letting go)',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('⑧ a movie that will not close does not keep the others open',
      (tester) async {
    final decoder = _OneCloseThrows();
    debugVideoDecodeBackend = movies = decoder;
    final path = normalizedMediaPath('${directory.path}/two.anicel');
    final one = normalizedMediaPath(
      (await tester.runAsync(() => writeCarriedMovie(directory)))!,
    );
    final two = normalizedMediaPath(
      (await tester.runAsync(
        () => written(directory, 'other.mp4', [
          ...movieMagic.codeUnits,
          ...noise(2048).reversed,
        ]),
      ))!,
    );
    final writer = aSession('${directory.path}/Staged');
    addTearDown(writer.dispose);
    writer.playbackRig.prerenderScheduler.beginInputHold();
    await tester.runAsync(() async {
      await writer.mediaPool.importMediaFiles(
        [one, two],
        copyIntoProject: true,
      );
      for (final movie in [one, two]) {
        await writer.importDoors.importVideoFile(
          path: movie,
          settings: const ImportFileSettings(
            mode: ImportFileMode.keepInside,
            sound: false,
          ),
        );
      }
      await writer.projectDoor.saveProjectToFile(
        path,
        asked: SaveAsked.byAPerson,
      );
    });
    final session = await opened(tester, path);
    addTearDown(session.dispose);
    await tester.runAsync(
      () => session.movieCels.hydrate(session.requireActiveCut, 0),
    );
    expect(
      session.projectFile.heldArchiveEntries,
      hasLength(2),
      reason: 'the premise: the canvas holds both',
    );

    decoder.armed = true;
    await tester.runAsync(() => session.movieCels.dispose());

    expect(
      session.projectFile.heldArchiveEntries,
      isEmpty,
      reason: 'the first close threw, and the second was closed all the same',
    );
    await tester.pumpAndSettle();
  });
}

/// A decoder whose next close fails once [armed] — antivirus, a lost
/// handle.
class _OneCloseThrows extends ReadingVideoBackend {
  bool armed = false;

  @override
  Future<void> close(int token) async {
    if (armed) {
      armed = false;
      throw StateError('will not close');
    }
  }
}
