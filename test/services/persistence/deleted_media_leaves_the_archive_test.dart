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
          coord: TileCoord(x: 0, y: 0),
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
}
