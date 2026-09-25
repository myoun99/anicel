import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/media/media_byte_source.dart'
    show MediaFileBytes;
import 'package:anicel/src/services/media/project_media_sources.dart'
    show mediaEntryNameIn, mediaLeftBehind;
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart'
    show parseAnicelZipLayoutFile;
import 'package:anicel/src/services/persistence/anicel_project_archive.dart'
    show anicelMediaEntryNames, anicelMediaEntryPrefix;
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/media_pool.dart';
import 'package:anicel/src/ui/session/project_file.dart';
import 'package:anicel/src/ui/session/project_file_door.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**WHAT A SAVE LEAVES BEHIND, THE ROOM KEEPS** (유저 2026-09-25,
/// board `undo-after-save-reads-the-original`: 「이번 실행의 앱 룸으로 옮겨
/// 둔다」).
///
/// Carry a file, save, take it out of the pool and save again — the file
/// shrinks, which is what 09-13 asked for — then undo the removal. The
/// carry is back, and its bytes had been in the file only: the undo read
/// the original instead, edited by then or gone. The save now hands what
/// it leaves behind to this run's room before it writes.
void main() {
  late Directory root;
  late EditorSessionManager session;

  /// The pool and the file under test, held BY THEIR OWN TYPES —
  /// `tool/mutation_run.dart` picks a file's witnesses by what its tests
  /// import.
  late MediaPool pool;
  late ProjectFile file;
  late ProjectFileDoor door;

  late String path;
  late String projectPath;

  final carried = Uint8List.fromList(
    List<int>.generate(64 * 1024, (i) => (i ~/ 9) & 0xFF),
  );

  /// What the original becomes after the save — so a reader that went to
  /// the original instead of the carried bytes would say so.
  final edited = Uint8List.fromList(
    List<int>.generate(64 * 1024, (i) => (i ~/ 3 + 57) & 0xFF),
  );

  EditorSessionManager aSession(String staged) => EditorSessionManager(
    initialProject: createDefaultProject(),
    mediaStagingStore: MediaStagingStore(
      directoryPath: '${root.path}/$staged',
    ),
    audioConformStore: soundConformStore(),
  );

  Future<void> save({void Function(double)? onProgress}) =>
      door.saveProjectToFile(
        projectPath,
        asked: SaveAsked.byAPerson,
        onProgress: onProgress,
      );

  /// What every reader of [path] gets — the one door they all go through.
  List<int> read() => file.mediaByteSourceFor(path).readSync();

  /// Whether the project file at [archive] still holds [carry]'s entry,
  /// under either spelling.
  bool holds(String archive, MediaCarry carry) {
    final layout = parseAnicelZipLayoutFile(archive);
    return anicelMediaEntryNames(
      carry,
    ).any((name) => layout.entryNamed(name) != null);
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('anicel_left_behind_test');
    session = aSession('Staged');
    pool = session.mediaPool;
    file = session.projectFile;
    door = session.projectDoor;
    path = normalizedMediaPath('${root.path}/take.wav');
    projectPath = '${root.path}/scene.anicel';
    File(path).writeAsBytesSync(carried);
    await pool.addMediaAssets([path], carried: true);
    await save();
    expect(stagedCopyIn(session, path), isNull, reason: 'the premise: saved');
  });

  tearDown(() {
    session.dispose();
    deleteTempQuietly(root);
  });

  test('🚨an undo of the removal reads the bytes that were carried — not '
      'the original edited since', () async {
    final carry = carryIn(session, path)!;
    expect(pool.removeMediaAsset(path), isTrue);
    await save();
    expect(
      holds(projectPath, carry),
      isFalse,
      reason:
          'the file still lets it go — 09-13 「삭제하고 저장해도 파일 크기 '
          '안 줄어든다」',
    );
    File(path).writeAsBytesSync(edited);

    session.undo();

    expect(
      read(),
      carried,
      reason:
          '🪦the file had let it go and nothing else held it: the undo read '
          'the original',
    );
  });

  test('and with the original gone', () async {
    expect(pool.removeMediaAsset(path), isTrue);
    await save();
    File(path).deleteSync();

    session.undo();

    expect(read(), carried);
  });

  test('the save after the undo carries those bytes back into the file, and '
      'the room lets go of its copy', () async {
    expect(pool.removeMediaAsset(path), isTrue);
    await save();
    File(path).deleteSync();
    session.undo();

    await save();

    expect(
      stagedCopyIn(session, path),
      isNull,
      reason: 'absorbed again — 「사본 남으면 진짜 용서안할게」',
    );
    final reopened = aSession('Reopened');
    addTearDown(reopened.dispose);
    await reopened.projectDoor.openProjectFromFile(projectPath);
    expect(reopened.projectFile.mediaByteSourceFor(path).readSync(), carried);
  });

  test('⛔what the write stores is not left behind — only what the file '
      'holds and the write does not', () async {
    final other = normalizedMediaPath('${root.path}/other.wav');
    File(other).writeAsBytesSync(edited);
    await pool.addMediaAssets([other], carried: true);
    await save();
    final kept = carryIn(session, path)!;
    final dropped = carryIn(session, other)!;

    final left = mediaLeftBehind(
      projectFilePath: projectPath,
      mediaInFile: file.mediaInFile,
      mediaToStore: {kept: MediaFileBytes(path)},
    );

    expect(
      [for (final entry in left) '$anicelMediaEntryPrefix${entry.name}'],
      [mediaEntryNameIn(file.mediaInFile, dropped)],
      reason:
          'a copy of what the write stores is made for nothing — the save '
          'retires it the moment it absorbs the carry',
    );
  });

  test('🚨a Save As the picker places leaves behind what the file it '
      'replaces as the project held', () async {
    expect(pool.removeMediaAsset(path), isTrue);
    final placed = '${root.path}/placed.anicel';

    final staged = await door.writeArchiveCopy(
      placed,
      asked: SaveAsked.byAPerson,
    );
    door.adoptPlacedArchive(placed, staged: staged);
    File(path).deleteSync();
    session.undo();

    expect(
      read(),
      carried,
      reason: 'bound to the placed copy, which never held it',
    );
  });

  test('the save\'s bar runs through the copy first, and never '
      'back', () async {
    // Most of the file, so the copy is most of the bar — and a write that
    // reported its own share from zero would be heard going back.
    final random = Random(7);
    final noise = normalizedMediaPath('${root.path}/noise.wav');
    File(noise).writeAsBytesSync(
      Uint8List.fromList(
        List<int>.generate(1 << 20, (_) => random.nextInt(256)),
      ),
    );
    await pool.addMediaAssets([noise], carried: true);
    await save();
    expect(pool.removeMediaAsset(noise), isTrue);
    final heard = <double>[];

    await save(onProgress: heard.add);

    expect(
      heard.first,
      allOf(greaterThan(0), lessThan(1)),
      reason: 'the copy moves the bar — a carried movie is gigabytes',
    );
    for (var i = 1; i < heard.length; i += 1) {
      expect(heard[i], greaterThanOrEqualTo(heard[i - 1]));
    }
    expect(heard.last, 1);
  });
}
