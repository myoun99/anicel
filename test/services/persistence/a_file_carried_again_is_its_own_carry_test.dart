import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/wav16_header.dart'
    show wav16HeaderBytes;
import 'package:anicel/src/services/media/project_media_sources.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart'
    show debugVideoDecodeBackend;
import 'package:anicel/src/services/persistence/anicel_project_archive.dart'
    show anicelMediaEntryName;
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/session/media_pool.dart';
import 'package:anicel/src/ui/session/project_file.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import '../../helpers/carried_media_fixture.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**ONE PATH CAN BE CARRIED TWICE, AND EACH CARRY IS ITS OWN BYTES.**
///
/// Remove a carried file from the pool, edit the original, carry the same
/// path again before saving — the flow of fixing a file and bringing it
/// back. The project then knows two sets of bytes for one path: the new
/// carry, and the old one an undo of the removal has to bring back. Every
/// lookup was keyed by the PATH, so the old carry answered first: readers
/// showed the old picture, and the save kept it and retired the new copy
/// (card `recarry-after-remove-reads-the-old`). Flipping the order would
/// have broken the other half — the undo.
///
/// So each carry has a name ([MediaAsset.carriedAs]) that rides the undo
/// with the asset, and the staged copy and the project file's entry are
/// named from it.
void main() {
  late Directory root;
  late EditorSessionManager session;

  /// The pool and the file under test, held BY THEIR OWN TYPES —
  /// `tool/mutation_run.dart` picks a file's witnesses by what its tests
  /// import.
  late MediaPool pool;
  late ProjectFile file;

  late String path;
  late String projectPath;

  final first = Uint8List.fromList(
    List<int>.generate(64 * 1024, (i) => (i ~/ 9) & 0xFF),
  );
  final second = Uint8List.fromList(
    List<int>.generate(64 * 1024, (i) => (i ~/ 5 + 101) & 0xFF),
  );

  /// What the original becomes AFTER the second carry — so a reader that
  /// went to the original instead of the carried bytes would say so.
  final third = Uint8List.fromList(
    List<int>.generate(64 * 1024, (i) => (i ~/ 3 + 57) & 0xFF),
  );

  /// A mono 48k 16-bit WAV [seconds] long — a sound the decoder reads, so
  /// the conform measures it for real.
  Uint8List wavOf({required int seconds}) {
    final samples = Int16List(48000 * seconds);
    for (var i = 0; i < samples.length; i += 1) {
      samples[i] = (i * 37) % 4000 - 2000;
    }
    final data = samples.buffer.asUint8List();
    return Uint8List.fromList([
      ...wav16HeaderBytes(
        dataBytes: data.length,
        sampleRate: 48000,
        channels: 1,
      ),
      ...data,
    ]);
  }

  EditorSessionManager aSession(String staged) => EditorSessionManager(
    initialProject: createDefaultProject(),
    mediaStagingStore: MediaStagingStore(
      directoryPath: '${root.path}/$staged',
    ),
    audioConformStore: soundConformStore(),
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('anicel_recarry_test');
    session = aSession('Staged');
    pool = session.mediaPool;
    file = session.projectFile;
    path = normalizedMediaPath('${root.path}/take.wav');
    projectPath = '${root.path}/scene.anicel';
    File(path).writeAsBytesSync(first);
  });

  tearDown(() {
    session.dispose();
    deleteTempQuietly(root);
  });

  Future<void> save() =>
      session.projectDoor.saveProjectToFile(
        projectPath,
        asked: SaveAsked.byAPerson,
      );

  /// What every reader of [path] gets — the one door they all go through.
  List<int> read() => file.mediaByteSourceFor(path).readSync();

  /// The original edited, then carried again after its removal — and then
  /// edited once more, so what reads [second] read the CARRIED bytes: the
  /// original holds [third] by then (audit 09-25 — it held [second], and a
  /// reader that went to the original passed as well).
  Future<void> carryTheEditAgain() async {
    expect(pool.removeMediaAsset(path), isTrue);
    File(path).writeAsBytesSync(second);
    await pool.addMediaAssets([path], carried: true);
    File(path).writeAsBytesSync(third);
  }

  test('the premise: two carries of one path are two names', () async {
    await pool.addMediaAssets([path], carried: true);
    final once = pool.mediaAssets.single.carriedAs;
    pool.removeMediaAsset(path);
    await pool.addMediaAssets([path], carried: true);

    expect(once, isNotNull);
    expect(pool.mediaAssets.single.carriedAs, allOf(isNotNull, isNot(once)));
  });

  group('saved, removed, carried again before the next save', () {
    setUp(() async {
      await pool.addMediaAssets([path], carried: true);
      await save();
      expect(read(), first, reason: 'the premise: the file holds the first');
      await carryTheEditAgain();
    });

    test('🚨every reader gets the carry the pool names now', () {
      expect(
        read(),
        second,
        reason:
            'the project file still holds the first carry — for an undo — '
            'and asked by path it answered first',
      );
      expect(
        file.projectHoldsMediaBytes(path),
        isTrue,
        reason: 'held — by the staged copy of THIS carry',
      );
      expect(
        file.mediaStoredBytesFor(path),
        stagedCopyIn(session, path)!.storedLength,
        reason: 'the size shown is the size of the bytes that are read',
      );
    });

    test('🚨the save writes the new carry, and the reopened project reads '
        'it with the original gone', () async {
      await save();
      expect(
        stagedCopyIn(session, path),
        isNull,
        reason: 'the save absorbed THIS carry\'s copy',
      );
      File(path).deleteSync();

      final reopened = aSession('Reopened');
      addTearDown(reopened.dispose);
      await reopened.projectDoor.openProjectFromFile(projectPath);

      expect(
        reopened.projectFile.mediaByteSourceFor(path).readSync(),
        second,
        reason:
            'named by the path, the save found the old entry in the file, '
            'wrote nothing, and retired the new copy',
      );
    });

    test('🚨undoing back to the first carry reads the first carry', () {
      session.undo(); // the second import
      session.undo(); // the removal

      expect(pool.mediaAssets.single.carriedAs, isNotNull);
      expect(
        read(),
        first,
        reason: 'its entry is still in the file, under its own name',
      );
    });
  });

  group('carried, removed and carried again, all before a save', () {
    setUp(() async {
      await pool.addMediaAssets([path], carried: true);
      await carryTheEditAgain();
    });

    test('🚨the new carry takes the edited file — not the copy the first '
        'carry left for an undo', () {
      expect(
        read(),
        second,
        reason:
            'the store found the first carry\'s copy under the path and '
            'handed it back as this one',
      );
    });

    test('and undoing back to the first carry reads the first carry', () {
      session.undo();
      session.undo();

      expect(read(), first);
    });

    test('a save then holds the carry the pool names', () async {
      await save();
      File(path).deleteSync();

      final reopened = aSession('Reopened');
      addTearDown(reopened.dispose);
      await reopened.projectDoor.openProjectFromFile(projectPath);

      expect(reopened.projectFile.mediaByteSourceFor(path).readSync(), second);
    });
  });

  test('🚨a file carried, saved, removed and brought back as a LINK reads '
      'its file — not the carry the project file still holds', () async {
    await pool.addMediaAssets([path], carried: true);
    await save();
    pool.removeMediaAsset(path);
    File(path).writeAsBytesSync(second);

    await pool.addMediaAssets([path]);

    expect(pool.mediaAssets.single.carried, isFalse);
    expect(read(), second, reason: 'the user said keep the link');
    expect(file.projectHoldsMediaBytes(path), isFalse);
  });

  test('🚨a PLACEMENT carrying the same path again holds the edited file — '
      'the door asked the pool, not the project file', () async {
    expect(
      await session.importDoors.importSoundFile(
        path: path,
        copyIntoProject: true,
      ),
      isTrue,
    );
    await save();
    pool.removeMediaAsset(path);
    File(path).writeAsBytesSync(second);

    expect(
      await session.importDoors.importSoundFile(
        path: path,
        copyIntoProject: true,
      ),
      isTrue,
    );

    expect(
      stagedCopyIn(session, path),
      isNotNull,
      reason:
          'asked whether the project held the PATH, the door heard yes from '
          'the removed carry and held nothing',
    );
    File(path).deleteSync();
    expect(read(), second);
  });

  test('the size shown asks the readers\' own gate — the file\'s record, not '
      'the directory beside it', () async {
    await pool.addMediaAssets([path], carried: true);
    await save();
    expect(file.mediaStoredBytesFor(path), isNotNull, reason: 'the premise');
    // A record that does not list the entry the file holds: the readers
    // then go to the carry's staged copy or its original, never that entry.
    file.bindToOpenedFile(projectPath, mediaInFile: const {}, unsaved: false);

    expect(
      file.mediaStoredBytesFor(path),
      isNull,
      reason:
          'only the file on disk knows — it is what is read (🪦the column '
          'asked the directory while every reader asked the record, audit '
          '09-25)',
    );
  });

  test('🚨a project opened after another reports ITS media\'s sizes', () async {
    await pool.addMediaAssets([path], carried: true);
    await save();
    expect(file.mediaStoredBytesFor(path), isNotNull, reason: 'measured once');

    final otherPath = normalizedMediaPath('${root.path}/other.wav');
    File(otherPath).writeAsBytesSync(Uint8List(3000));
    final other = aSession('Other');
    addTearDown(other.dispose);
    await other.mediaPool.addMediaAssets([otherPath], carried: true);
    final otherProject = '${root.path}/other.anicel';
    await other.projectDoor.saveProjectToFile(
      otherProject,
      asked: SaveAsked.byAPerson,
    );
    File(otherPath).deleteSync();

    await session.projectDoor.openProjectFromFile(otherProject);

    final carry = carryIn(session, otherPath)!;
    expect(mediaEntryHeld(file.mediaInFile, carry), isTrue);
    expect(
      file.mediaStoredBytesFor(otherPath),
      isNotNull,
      reason:
          'the sizes were cached against saves alone, so an open kept the '
          'LAST file\'s — and this one\'s entry was not in them',
    );
  });

  test('a file holds a carry by the carry\'s own name — not because it holds '
      'another carry of the path', () {
    final one = (poolPath: path, token: 'c1');
    final two = (poolPath: path, token: 'c2');
    expect(
      mediaEntryHeld({anicelMediaEntryName(one, framed: true)}, one),
      isTrue,
    );
    expect(mediaEntryHeld({anicelMediaEntryName(one)}, one), isTrue);
    expect(mediaEntryHeld({anicelMediaEntryName(one)}, two), isFalse);
  });

  test('a carried file whose bytes were never taken is LEFT OUT of a save '
      'beside media the file holds — not refused', () async {
    await pool.addMediaAssets([path], carried: true);
    await save();
    final gone = normalizedMediaPath('${root.path}/never-there.wav');
    await pool.addMediaAssets([gone]);
    expect(await pool.promoteMediaAssetIntoProject(gone), isTrue);
    expect(stagedCopyIn(session, gone), isNull, reason: 'the premise');

    await save();

    expect(file.projectHoldsMediaBytes(gone), isFalse);
    pool.refreshMediaExistence();
    expect(
      pool.missingMediaPaths,
      contains(gone),
      reason: 'a findable absence, for the relink hunt',
    );
  });

  test('🚨the sound a path plays is the carry the pool names — the first '
      'carry\'s conform does not answer for the second', () async {
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      mediaStagingStore: MediaStagingStore(
        directoryPath: '${root.path}/Sounds',
      ),
    );
    addTearDown(s.dispose);
    final sound = normalizedMediaPath('${root.path}/line.wav');
    File(sound).writeAsBytesSync(wavOf(seconds: 1));
    await s.mediaPool.addMediaAssets([sound], carried: true);
    expect(await s.audioConformStore.ensureFor(sound), isNotNull);
    expect(s.audioConformStore.durationSecondsFor(sound), closeTo(1, 0.01));

    s.mediaPool.removeMediaAsset(sound);
    File(sound).writeAsBytesSync(wavOf(seconds: 2));
    await s.mediaPool.addMediaAssets([sound], carried: true);
    await s.audioConformStore.ensureFor(sound);
    expect(
      s.audioConformStore.durationSecondsFor(sound),
      closeTo(2, 0.01),
      reason: 'kept by path, the waveform and playback stayed the old sound',
    );

    s.undo();
    s.undo();
    await s.audioConformStore.ensureFor(sound);
    expect(s.audioConformStore.durationSecondsFor(sound), closeTo(1, 0.01));
  });

  group('a movie on the canvas', () {
    late ClosingVideoBackend movies;

    setUp(() => debugVideoDecodeBackend = movies = ClosingVideoBackend());
    tearDown(() => debugVideoDecodeBackend = null);

    Future<void> placeMovie(
      WidgetTester tester,
      String movie,
      ImportFileMode mode,
    ) async {
      final placed = await tester.runAsync(
        () => session.importDoors.importVideoFile(
          path: movie,
          settings: ImportFileSettings(mode: mode, sound: false),
        ),
      );
      expect(placed, isTrue);
    }

    Future<void> hydrate(WidgetTester tester) => tester.runAsync(
      () => session.movieCels.hydrate(session.requireActiveCut, 0),
    );

    Future<String> aMovie(WidgetTester tester, {int length = 4096}) async =>
        normalizedMediaPath(
          (await tester.runAsync(
            () => writeCarriedMovie(root, length: length),
          ))!,
        );

    testWidgets('🚨a movie carried again shows the NEW carry — and lets go of '
        'the first', (tester) async {
      final movie = await aMovie(tester);
      await placeMovie(tester, movie, ImportFileMode.keepInside);
      await hydrate(tester);
      final first = stagedCopyIn(session, movie)!.path;
      expect(movies.openedAt.last.path, first, reason: 'the premise');

      pool.removeMediaAsset(movie);
      await aMovie(tester, length: 8192);
      await placeMovie(tester, movie, ImportFileMode.keepInside);
      await hydrate(tester);

      final second = stagedCopyIn(session, movie)!.path;
      expect(second, isNot(first), reason: 'the premise: two carries');
      expect(
        movies.openedAt.last.path,
        second,
        reason: 'kept by path, the canvas went on showing the first carry',
      );
      expect(
        movies.closed,
        contains(first),
        reason: 'the first carry\'s document was closed, and its bytes let go',
      );
      await tester.runAsync(() => session.movieCels.dispose());
      await tester.pumpAndSettle();
    });

    testWidgets('a row placed as a LINK and carried afterwards reads the '
        'carry', (tester) async {
      final movie = await aMovie(tester);
      await placeMovie(tester, movie, ImportFileMode.reference);
      await hydrate(tester);
      expect(movies.openedAt.last.path, movie, reason: 'the premise');

      await tester.runAsync(() => pool.promoteMediaAssetIntoProject(movie));
      await hydrate(tester);

      expect(
        movies.openedAt.last.path,
        stagedCopyIn(session, movie)!.path,
        reason: 'opened once, the row read the original for the session',
      );
      await tester.runAsync(() => session.movieCels.dispose());
      await tester.pumpAndSettle();
    });
  });

  test('a carry from before carries had names reads as the path-named one',
      () {
    final legacy = MediaAsset.fromJson({
      'path': path,
      'name': 'take',
      'kind': 'audio',
      'carried': true,
    });
    expect(legacy.carriedAs, '');
    expect(legacy.carried, isTrue);
    expect(
      MediaAsset.fromJson(legacy.toJson()),
      legacy,
      reason: 'and it is written back as that carry',
    );
    expect(
      MediaAsset.fromJson({'path': path, 'name': 'take', 'kind': 'audio'})
          .carriedAs,
      isNull,
    );
  });
}
