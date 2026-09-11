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

  tearDown(() => directory.delete(recursive: true));

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
    File(path).deleteSync();

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
    File(path).deleteSync();
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
    // ⚠️f1 is not asserted either way here: its bytes were only in the
    // deleted file, and what the save should DO about that is the
    // decision this test exists to pin once it is made.
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
    File(path).deleteSync();

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

    File(path).deleteSync();
    store.storeBakedSurface(key('p', 'f2'), inked(9));

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
}
