import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/open_project_file.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**THE PROJECT FILE CAN VANISH WHILE THE PROJECT IS OPEN.**
///
/// 유저 2026-08-30, on an iPad: open a project, delete the file in the
/// Files app, come back and press Save — 「저장됐다고하는데 어디 된지
/// 모르겠거든?」. Then, precisely: save, delete the file, save again (the
/// file comes back), delete it again, **draw a stroke**, save —
/// `PathNotFoundException: Cannot open file`.
///
/// The stroke is what makes it fail, and the reason is the cel tiers. A
/// successful save turns every cel into a FILE REF and drops its cold
/// blob, "redundant with the file". So after the second delete the
/// untouched cels have their bytes in exactly one place — a file that is
/// no longer there — and the save that reads them to write the new archive
/// opens a path that does not exist.
///
/// ⛔The first re-save works, which is what made this look intermittent:
/// nothing had been adopted as a ref yet at that point.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-vanished');
  });

  tearDown(() => deleteTempQuietly(directory));

  BrushFrameKey key(String project, String frame) => BrushFrameKey(
    projectId: ProjectId(project),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapSurface inked(int value) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = value;
      pixels[i + 3] = 0xFF;
    }
    return BitmapSurface(
      canvasSize: const CanvasSize(width: 8, height: 8),
      tileSize: 8,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          size: 8,
          pixels: pixels,
        ),
      },
    );
  }

  /// The file goes AND the session's descriptor with it — the one way a cel
  /// can still be lost (a cloud provider evicting its local copy). Held,
  /// Windows would refuse the delete, and POSIX would keep the bytes
  /// readable for the save's rescue.
  void takeTheFileAway(String path) {
    OpenProjectFile.instance.release();
    File(path).deleteSync();
  }

  test('🚨saving after the file was deleted, with a stroke since, must not '
      'throw a raw PathNotFoundException', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/vanishing.anicel';
    final store = BrushFrameStore();
    store.storeBakedSurface(key('p', 'f1'), inked(3));
    store.storeBakedSurface(key('p', 'f2'), inked(5));
    final project = createDefaultProject().copyWith(id: const ProjectId('p'));

    // A normal save: both cels become file refs and their cold blobs go.
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    expect(File(path).existsSync(), isTrue);

    // The user deletes it in the Files app.
    takeTheFileAway(path);

    // ...and draws. Only f2 is dirty now; f1's bytes live in the file
    // that is gone.
    store.storeBakedSurface(key('p', 'f2'), inked(9));

    // 🚨This is the press that threw.
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    expect(
      File(path).existsSync(),
      isTrue,
      reason: 'the save must land somewhere, not throw',
    );
  });

  test('and what it writes says which cels it could still reach', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/vanishing.anicel';
    final store = BrushFrameStore();
    store.storeBakedSurface(key('p', 'f1'), inked(3));
    store.storeBakedSurface(key('p', 'f2'), inked(5));
    final project = createDefaultProject().copyWith(id: const ProjectId('p'));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    takeTheFileAway(path);
    store.storeBakedSurface(key('p', 'f2'), inked(9));

    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    final names = {
      for (final entry in parseAnicelZipLayoutFile(path).entries) entry.name,
    };
    expect(
      names,
      contains(anicelCelEntryName(key('p', 'f2'))),
      reason: 'the cel that was in RAM is written',
    );
    expect(
      names,
      contains(anicelCelEntryName(key('p', 'f1'))),
      reason:
          '🚨f1 was clean but still HOT — the bytes the file held are in RAM, '
          'so the save writes them from there instead of losing them',
    );
  });

  test('a save with NO stroke since the delete also lands', () async {
    // The user saw this one work, and it must keep working: nothing has
    // been adopted as a ref that the deleted file backs.
    const service = AnicelFileService();
    final path = '${directory.path}/vanishing.anicel';
    final store = BrushFrameStore();
    store.storeBakedSurface(key('p', 'f1'), inked(3));
    final project = createDefaultProject().copyWith(id: const ProjectId('p'));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    takeTheFileAway(path);

    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    expect(File(path).existsSync(), isTrue);
  });

  test('🚨and it SAYS which cels it could not carry forward', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/vanishing.anicel';
    final store = BrushFrameStore();
    store.storeBakedSurface(key('p', 'f1'), inked(3));
    store.storeBakedSurface(key('p', 'f2'), inked(5));
    final project = createDefaultProject().copyWith(id: const ProjectId('p'));

    expect(
      await service.save(
        project: project,
        brushFrameStore: store,
        filePath: path,
      ),
      isEmpty,
      reason: 'an ordinary save loses nothing, and must say so',
    );

    // f1 cools off to the file alone (a clean file-backed cel's cooling is a
    // free drop), so its only copy is the file about to go. Still hot, it
    // would be written from RAM — see the test that keeps it hot.
    store.hotCelByteBudget = 0;
    takeTheFileAway(path);
    store.storeBakedSurface(key('p', 'f2'), inked(9));
    await store.drainCooling();

    final lost = await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    expect(
      lost,
      {key('p', 'f1')},
      reason:
          '⛔f1 lived only in the deleted file. Writing a project one cel '
          'short WITHOUT saying so is the shape this repo refuses for '
          'media, and a cel is the picture itself',
    );
    expect(
      lost,
      isNot(contains(key('p', 'f2'))),
      reason: 'f2 was in RAM, so it was written',
    );
  });

  test('🚨a second save that APPENDS carries every clean cel in place — and '
      'says it lost nothing (F-72)', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/appending.anicel';
    final store = BrushFrameStore();
    for (final (frame, value) in [('f1', 3), ('f2', 5), ('f3', 7), ('f4', 11)]) {
      store.storeBakedSurface(key('p', frame), inked(value));
    }
    final project = createDefaultProject().copyWith(id: const ProjectId('p'));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    final firstLength = File(path).lengthSync();

    // Drawn on f2 only: the other three stay clean refs into this file.
    store.storeBakedSurface(key('p', 'f2'), inked(9));
    final lost = await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    expect(
      File(path).lengthSync(),
      greaterThan(firstLength),
      reason:
          'fixture: the second save APPENDED — the old f2 stays behind as '
          'dead bytes — rather than rewriting the file',
    );
    expect(
      lost,
      isEmpty,
      reason:
          '⛔the clean cels were carried where they already were. Reporting '
          'them lost told the person, on every save after the first, that '
          'pictures had gone while the file held every one of them',
    );
    expect(
      {for (final entry in parseAnicelZipLayoutFile(path).entries) entry.name},
      containsAll([
        for (final frame in ['f1', 'f2', 'f3', 'f4'])
          anicelCelEntryName(key('p', frame)),
      ]),
    );
  });

  test(
    '🚨a file that is THERE but will not read right now stops the save — '
    'nothing is written one cel short (F-72)',
    () async {
      const service = AnicelFileService();
      final path = '${directory.path}/busy.anicel';
      final store = BrushFrameStore();
      store.storeBakedSurface(key('p', 'f1'), inked(3));
      store.storeBakedSurface(key('p', 'f2'), inked(5));
      final project = createDefaultProject().copyWith(id: const ProjectId('p'));
      await service.save(
        project: project,
        brushFrameStore: store,
        filePath: path,
      );
      final before = File(path).readAsBytesSync();
      store.storeBakedSurface(key('p', 'f2'), inked(9));

      // Another handle locks the whole file: it is there, and every read of
      // it is refused — what a provider in the middle of a sync looks like
      // to anybody reading it.
      // Saved AS a new name while the file f1 lives in is busy. Renaming
      // onto a locked file is refused on its own, so the target is a new
      // file — what stops this save can only be the read.
      final copy = '${directory.path}/busy-copy.anicel';
      final lock = File(path).openSync(mode: FileMode.append);
      lock.lockSync(FileLock.exclusive);
      try {
        await expectLater(
          service.save(
            project: project,
            brushFrameStore: store,
            filePath: copy,
          ),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        lock.unlockSync();
        lock.closeSync();
      }

      expect(
        File(copy).existsSync(),
        isFalse,
        reason: 'no copy one cel short was written',
      );
      expect(
        File(path).readAsBytesSync(),
        before,
        reason: 'and the file f1 lives in stands',
      );
    },
    skip: Platform.isWindows ? false : 'only Windows refuses a locked read',
  );

  test('🚨the session holds the file it saved into — Windows will not let it '
      'be taken away, POSIX keeps its bytes (F-72)', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/held.anicel';
    final store = BrushFrameStore();
    store.storeBakedSurface(key('p', 'f1'), inked(3));
    final project = createDefaultProject().copyWith(id: const ProjectId('p'));

    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    expect(
      OpenProjectFile.instance.heldPath,
      path,
      reason:
          '⛔a full save lets go of the file to rename onto it; taking it back '
          'only at the next cold read left it unheld until then',
    );
    if (Platform.isWindows) {
      expect(
        () => File(path).deleteSync(),
        throwsA(isA<FileSystemException>()),
        reason: 'held, the file cannot be deleted out from under the session',
      );
    }
  });

  test('🚨a name that vanished while the session held the file loses '
      'nothing — its bytes are copied out through the handle (F-72)', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/vanished.anicel';
    final vault = '${directory.path}/where-the-bytes-went.anicel';
    final store = BrushFrameStore();
    for (final (frame, value) in [('f1', 3), ('f3', 7), ('f2', 5)]) {
      store.storeBakedSurface(key('p', frame), inked(value));
    }
    final project = createDefaultProject().copyWith(id: const ProjectId('p'));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    // What a POSIX delete or move leaves: the name gone, our descriptor
    // still reading the bytes. Windows refuses both while we hold the file,
    // so the test moves it and hands the session that descriptor.
    OpenProjectFile.instance.release();
    File(path).renameSync(vault);
    OpenProjectFile.instance.debugHoldAs(vault, path);
    // f1 and f3 cool off to the file alone; the newest, f2, stays hot.
    store.hotCelByteBudget = 0;
    store.storeBakedSurface(key('p', 'f2'), inked(9));
    await store.drainCooling();

    final lost = await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    expect(
      lost,
      isEmpty,
      reason:
          '⛔f1 and f3 lived only in the vanished file — and were still '
          'readable through the descriptor the session held',
    );
    expect(
      {for (final entry in parseAnicelZipLayoutFile(path).entries) entry.name},
      containsAll([
        for (final frame in ['f1', 'f2', 'f3'])
          anicelCelEntryName(key('p', frame)),
      ]),
    );
    final staged = Directory(SessionScratch.stagedFolder());
    expect(
      staged.existsSync()
          ? staged.listSync().where((e) => e.path.contains('rescued-'))
          : const <FileSystemEntity>[],
      isEmpty,
      reason: 'the rescue copy goes the moment no ref reads from it',
    );
    expect(OpenProjectFile.instance.heldPath, path);
  });

  test('🚨with the descriptor gone too, a picture still in RAM is written '
      'from there — lost means not in memory either (F-72)', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/still-hot.anicel';
    final store = BrushFrameStore();
    store.storeBakedSurface(key('p', 'f1'), inked(3));
    store.storeBakedSurface(key('p', 'f2'), inked(5));
    final project = createDefaultProject().copyWith(id: const ProjectId('p'));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    expect(
      store.isCelFileBacked(key('p', 'f1')),
      isTrue,
      reason: 'fixture: f1 is a clean ref into the file, and still hot',
    );
    takeTheFileAway(path);

    final lost = await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    expect(
      lost,
      isEmpty,
      reason:
          '⛔both pictures were still in RAM. Reading the clean one from its '
          'ref alone reported it lost while the same bytes sat in memory',
    );
    expect(
      {for (final entry in parseAnicelZipLayoutFile(path).entries) entry.name},
      containsAll([
        anicelCelEntryName(key('p', 'f1')),
        anicelCelEntryName(key('p', 'f2')),
      ]),
    );
  });

  test('🚨a cel a save could not carry lets go of its old place — the file '
      'at that path is a different one now (F-72)', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/replaced.anicel';
    final store = BrushFrameStore();
    for (final (frame, value) in [('f1', 3), ('f3', 7), ('f2', 5)]) {
      store.storeBakedSurface(key('p', frame), inked(value));
    }
    final project = createDefaultProject().copyWith(id: const ProjectId('p'));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    // f1 and f3 cool off to the file alone (a clean file-backed cel's
    // cooling is a free drop); the newest, f2, stays hot.
    store.hotCelByteBudget = 0;
    takeTheFileAway(path);
    store.storeBakedSurface(key('p', 'f2'), inked(9));
    await store.drainCooling();
    expect(
      await service.save(
        project: project,
        brushFrameStore: store,
        filePath: path,
      ),
      {key('p', 'f1'), key('p', 'f3')},
      reason: 'fixture: the two cels that lived only in the file that went',
    );

    // Drawn on f2 again, so this save APPENDS onto the file the last one
    // wrote at the same path.
    store.storeBakedSurface(key('p', 'f2'), inked(11));
    final lost = await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );

    final names = {
      for (final entry in parseAnicelZipLayoutFile(path).entries) entry.name,
    };
    for (final frame in ['f1', 'f3']) {
      expect(
        names,
        isNot(contains(anicelCelEntryName(key('p', frame)))),
        reason:
            '⛔$frame is gone. Carried from its old offset, the index named '
            'whatever sits there in the new file as $frame',
      );
      expect(store.celHasRenderableContent(key('p', frame)), isFalse);
    }
    expect(names, contains(anicelCelEntryName(key('p', 'f2'))));
    expect(lost, isEmpty);
  });
}
