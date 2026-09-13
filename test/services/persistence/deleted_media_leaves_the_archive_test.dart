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
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';

/// Media the project no longer carries LEAVES the central directory with
/// the next incremental save.
///
/// An entry nothing named was invisible garbage: the compaction maths
/// counted it as ACTIVE media — raising the very floor that suppresses
/// compaction, so a deleted 500MB track could sit in the file for ever —
/// and worse, the live name silently reattached a RE-imported same-path
/// asset to the OLD bytes: the append's presence check skips streaming
/// when the name already exists, so re-recorded audio kept playing the
/// old take while project.json claimed the new one.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-media-rm');
  });

  tearDown(() => directory.delete(recursive: true));

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapSurface inked(int seed) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 31 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: const CanvasSize(width: 16, height: 16),
      tileSize: 8,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          size: 8,
          pixels: pixels,
        ),
      },
    );
  }

  test('a removed asset\'s entry is gone after the next incremental save, '
      'and a re-import of the same path streams the NEW bytes', () async {
    const service = AnicelFileService();
    final path = '${directory.path}/project.anicel';
    final audioPath = '${directory.path.replaceAll('\\', '/')}/take.wav';
    final oldBytes = List<int>.filled(200, 1);
    File(audioPath).writeAsBytesSync(oldBytes, flush: true);
    final entryName = anicelMediaEntryName(audioPath);

    final project = createDefaultProject();
    final store = BrushFrameStore();
    store.storeBakedSurface(key('f1'), inked(3));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
      mediaToStore: {audioPath: MediaFileBytes(audioPath)},
    );
    expect(parseAnicelZipLayoutFile(path).entryNamed(entryName), isNotNull);

    // The asset leaves the pool; the next save is INCREMENTAL (one edited
    // cel) and must take the entry with it.
    store.storeBakedSurface(key('f1'), inked(5));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    expect(
      parseAnicelZipLayoutFile(path).entryNamed(entryName),
      isNull,
      reason: 'an entry nothing names must not stay a live central-'
          'directory row — it inflated the compaction floor and waited to '
          'reattach itself to a re-import',
    );

    // Re-import, same path, DIFFERENT content (a re-recorded take).
    final newBytes = List<int>.filled(200, 9);
    File(audioPath).writeAsBytesSync(newBytes, flush: true);
    store.storeBakedSurface(key('f1'), inked(7));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
      mediaToStore: {audioPath: MediaFileBytes(audioPath)},
    );

    final entry = parseAnicelZipLayoutFile(path).entryNamed(entryName)!;
    final raf = File(path).openSync();
    try {
      raf.setPositionSync(entry.dataOffset);
      expect(
        raf.readSync(entry.length),
        newBytes,
        reason: 'the re-imported content, not the deleted take\'s bytes',
      );
    } finally {
      raf.closeSync();
    }
  });

  /// 🚨THE SAVE THAT DROPS THE BYTES IS THE ONE THAT RECLAIMS THEM. The
  /// compaction ratio used to be judged on the directory the save FOUND,
  /// with the dropped media still named in it — so the deleting save
  /// appended and the file shrank only on the save after (유저 2026-09-13,
  /// a 157MB PDF: 「삭제하고 저장해도 안 줄어든다 … 두 번째 저장 시
  /// 줄어드네」). One rule, the ratio, whatever the size: what leaves this
  /// save is counted before a byte is written.
  test('the save that drops a carried asset compacts when what leaves '
      'crosses the ratio — the file shrinks on THAT save, not the next',
      () async {
    const service = AnicelFileService();
    final path = '${directory.path}/project.anicel';
    final moviePath = '${directory.path.replaceAll('\\', '/')}/big.mp4';
    final movieBytes = List<int>.filled(64 * 1024, 7);
    File(moviePath).writeAsBytesSync(movieBytes, flush: true);
    final entryName = anicelMediaEntryName(moviePath);

    final project = createDefaultProject();
    final store = BrushFrameStore();
    store.storeBakedSurface(key('f1'), inked(3));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
      mediaToStore: {moviePath: MediaFileBytes(moviePath)},
    );
    expect(File(path).lengthSync(), greaterThan(movieBytes.length));

    // The asset leaves the pool; one cel is edited so this is the ordinary
    // incremental save — and this save is where the file shrinks.
    store.storeBakedSurface(key('f1'), inked(5));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    expect(parseAnicelZipLayoutFile(path).entryNamed(entryName), isNull);
    expect(
      File(path).lengthSync(),
      lessThan(movieBytes.length),
      reason: 'the dropped bytes were most of the file — the deleting save '
          'must compact, not leave them for the save after',
    );
  });
}
