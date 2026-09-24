import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart'
    show debugVideoDecodeBackend;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/session/project_file.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import '../../helpers/carried_media_fixture.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**A READER THAT KEEPS READING FOLLOWS WHAT THE SAVE ABSORBED.**
///
/// The first save after a file is carried moves its bytes into the project
/// file and retires the staged copy — but a copy a reader holds is only
/// retired when the reader lets go, and a canvas's movie row holds for the
/// whole session. So the copy stayed on disk beside the entry that replaced
/// it until the app quit, and an open viewer kept one for as long as it
/// showed (card `canvas-holds-staged-for-session`; 유저 08-27: 「사본 남으면
/// 진짜 용서안할게」). Now the hold says when its bytes moved
/// (`HeldMediaBytes.moved`), and the reader opens again on the new answer
/// before it lets go of the old one.
void main() {
  late Directory directory;
  late ClosingVideoBackend movies;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-follow');
    debugVideoDecodeBackend = movies = ClosingVideoBackend();
  });

  tearDown(() {
    debugVideoDecodeBackend = null;
    deleteTempQuietly(directory);
  });

  /// The file under test, held BY ITS OWN TYPE — `tool/mutation_run.dart`
  /// picks a file's witnesses by what its tests import.
  ProjectFile fileOf(EditorSessionManager session) => session.projectFile;

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 60 && !done(); i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  group('the hold says when its bytes moved', () {
    testWidgets('a staged copy the save absorbs — moved', (tester) async {
      final (:session, :path) = await carrying(
        tester,
        directory,
        writeCarriedMovie,
      );
      final held = (await tester.runAsync(
        () => fileOf(session).holdMediaBytes(path),
      ))!;
      var moved = false;
      unawaited(held.moved.then((_) => moved = true));

      await saveProject(tester, session, directory);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(moved, isTrue);
      held.release();
    });

    testWidgets('bytes the file already holds — not moved by another save', (
      tester,
    ) async {
      final (:session, :path) = await carrying(
        tester,
        directory,
        writeCarriedMovie,
      );
      await saveProject(tester, session, directory);
      final held = (await tester.runAsync(
        () => fileOf(session).holdMediaBytes(path),
      ))!;
      var moved = false;
      unawaited(held.moved.then((_) => moved = true));

      await saveProject(tester, session, directory);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(moved, isFalse);
      held.release();
    });

    testWidgets('bytes the file holds, saved as another file — moved to it', (
      tester,
    ) async {
      final (:session, :path) = await carrying(
        tester,
        directory,
        writeCarriedMovie,
      );
      await saveProject(tester, session, directory);
      final held = (await tester.runAsync(
        () => fileOf(session).holdMediaBytes(path),
      ))!;
      var moved = false;
      unawaited(held.moved.then((_) => moved = true));

      final elsewhere = normalizedMediaPath('${directory.path}/as.anicel');
      await tester.runAsync(
        () => session.projectDoor.saveProjectToFile(
          elsewhere,
          asked: SaveAsked.byAPerson,
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(
        moved,
        isTrue,
        reason: 'the entry of the file left behind is not the answer now',
      );
      held.release();
    });

    testWidgets('a hold given back — never told', (tester) async {
      final (:session, :path) = await carrying(
        tester,
        directory,
        writeCarriedMovie,
      );
      final held = (await tester.runAsync(
        () => fileOf(session).holdMediaBytes(path),
      ))!;
      var moved = false;
      unawaited(held.moved.then((_) => moved = true));
      held.release();

      await saveProject(tester, session, directory);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(moved, isFalse, reason: 'nobody is reading it to be told');
    });

    testWidgets('a file the pool points at — never moved', (tester) async {
      final (:session, path: _) = await carrying(
        tester,
        directory,
        writeCarriedMovie,
      );
      final linked = normalizedMediaPath(
        (await tester.runAsync(() => writeCarriedPicture(directory)))!,
      );
      await tester.runAsync(() => session.mediaPool.addMediaAssets([linked]));
      final held = (await tester.runAsync(
        () => fileOf(session).holdMediaBytes(linked),
      ))!;
      var moved = false;
      unawaited(held.moved.then((_) => moved = true));

      await saveProject(tester, session, directory);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(moved, isFalse);
      held.release();
    });
  });

  /// A movie carried and placed on the canvas, its row shown there, before
  /// any save — and how many closes getting there took: the placement reads
  /// the file once for itself, so a close counted before that is not the
  /// row's.
  Future<
    ({EditorSessionManager session, String path, String staged, int closes})
  >
  placedOnTheCanvas(WidgetTester tester) async {
    final (:session, :path) = await carrying(
      tester,
      directory,
      writeCarriedMovie,
    );
    final placed = await tester.runAsync(
      () => session.importDoors.importVideoFile(
        path: path,
        settings: const ImportFileSettings(
          mode: ImportFileMode.keepInside,
          sound: false,
        ),
      ),
    );
    expect(placed, isTrue, reason: 'the premise');
    await tester.runAsync(
      () => session.movieCels.hydrate(session.requireActiveCut, 0),
    );
    final staged = stagedCopyIn(session, path)!.path;
    expect(movies.openedAt.last.path, staged, reason: 'the premise');
    return (
      session: session,
      path: path,
      staged: staged,
      closes: movies.closed.length,
    );
  }

  testWidgets('🚨a movie row placed before the first save follows it onto the '
      'project file — and the staged copy goes', (tester) async {
    final (:session, path: _, :staged, :closes) = await placedOnTheCanvas(
      tester,
    );

    await saveProject(tester, session, directory);
    await settle(tester, () => !File(staged).existsSync());

    expect(
      File(staged).existsSync(),
      isFalse,
      reason: 'held for the session, the copy stayed until the app quit',
    );
    expect(
      movies.openedAt.last.path,
      fileOf(session).path,
      reason: 'opened again on the entry the save wrote',
    );
    expect(movies.closed.skip(closes), contains(staged));
    expect(fileOf(session).heldArchiveEntries, hasLength(1));

    await tester.runAsync(() => session.movieCels.dispose());
    await tester.pumpAndSettle();
  });

  testWidgets('a movie row follows again when the project is saved as '
      'another file', (tester) async {
    final (:session, path: _, :staged, closes: _) = await placedOnTheCanvas(
      tester,
    );
    await saveProject(tester, session, directory);
    await settle(tester, () => !File(staged).existsSync());
    final first = fileOf(session).path!;
    expect(movies.openedAt.last.path, first, reason: 'the premise');

    final elsewhere = normalizedMediaPath('${directory.path}/as.anicel');
    await tester.runAsync(
      () => session.projectDoor.saveProjectToFile(
        elsewhere,
        asked: SaveAsked.byAPerson,
      ),
    );
    await settle(tester, () => movies.openedAt.last.path == elsewhere);

    expect(movies.openedAt.last.path, elsewhere);
    expect(
      movies.closed.last,
      first,
      reason: 'the file left behind is let go of',
    );

    await tester.runAsync(() => session.movieCels.dispose());
    await tester.pumpAndSettle();
  });

  testWidgets('a movie row whose new answer will not open keeps reading '
      'where it was', (tester) async {
    var refused = 0;
    debugVideoDecodeBackend = movies = ClosingVideoBackend(
      refuses: (path) {
        final isTheFile = path.endsWith('project.anicel');
        refused += isTheFile ? 1 : 0;
        return isTheFile;
      },
    );
    final (:session, :path, :staged, :closes) = await placedOnTheCanvas(
      tester,
    );

    await saveProject(tester, session, directory);
    await settle(tester, () => refused > 0);
    await tester.pump();

    expect(refused, greaterThan(0), reason: 'the premise: it tried');
    expect(
      movies.closed.skip(closes),
      isNot(contains(staged)),
      reason: 'nothing is gained by losing the reader that still reads',
    );
    expect(session.movieCels.factsFor(path), isNotNull);
    // Told once: the next save finds the hold it already told, and saves.
    await saveProject(tester, session, directory);
    expect(fileOf(session).failedCopy, isNull, reason: 'the file took it');

    await tester.runAsync(() => session.movieCels.dispose());
    await tester.pumpAndSettle();
  });
}
