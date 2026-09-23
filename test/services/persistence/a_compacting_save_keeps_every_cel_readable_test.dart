import 'dart:io';
import 'dart:typed_data';

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
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★A SAVE THAT PACKS THE FILE MOVES BYTES THE SESSION READS FROM.
///
/// After a project opens, every cel is a ref — path, offset, length — and
/// the picture is read from the `.anicel` the first time it is shown. The
/// in-place compaction (유저 2026-09-23, deleting-save-compacts-Q1) slides
/// those very bytes down, in another isolate, while the session keeps
/// going. A ref left at the old offset reads whatever landed there, and the
/// next save would write that back as the cel.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-packing-save');
  });

  tearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // A locked file on Windows must not fail the suite.
    }
  });

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
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
    );
  }

  Uint8List pixelsOf(BitmapSurface? surface) =>
      surface!.tiles[TileCoord(x: 0, y: 0)]!.pixels;

  /// Six cels saved, a big hole made behind them, and the file opened the
  /// way the app opens it — every cel a ref, nothing in RAM. The next save
  /// is past the garbage ratio, so it packs.
  Future<(String, BrushFrameStore)> openedOverAHole() async {
    const service = AnicelFileService();
    final path = '${directory.path}/project.anicel';
    final first = BrushFrameStore();
    for (var i = 0; i < 6; i += 1) {
      first.storeBakedSurface(key('f$i'), inked(i + 1));
    }
    await service.save(
      project: createDefaultProject(),
      brushFrameStore: first,
      filePath: path,
    );
    appendAnicelEntries(
      path: path,
      newEntries: {'junk.bin': Uint8List(64 * 1024)},
    );
    appendAnicelEntries(
      path: path,
      newEntries: const {},
      removeNames: const {'junk.bin'},
    );
    final opened = await service.open(filePath: path);
    return (path, BrushFrameStore()..restoreFromFile(opened.cels));
  }

  test('🎯every clean cel still reads its own picture after a save that '
      'packed the file', () async {
    final (path, store) = await openedOverAHole();
    final before = File(path).lengthSync();

    store.storeBakedSurface(key('f0'), inked(50));
    final lost = await const AnicelFileService().save(
      project: createDefaultProject(),
      brushFrameStore: store,
      filePath: path,
    );

    expect(lost, isEmpty);
    expect(
      File(path).lengthSync(),
      lessThan(before - 32 * 1024),
      reason: 'fixture: this save packed the file',
    );
    expect(pixelsOf(store.bakedSurfaceOrNull(key('f0'))), pixelsOf(inked(50)));
    for (var i = 1; i < 6; i += 1) {
      expect(
        pixelsOf(store.bakedSurfaceOrNull(key('f$i'))),
        pixelsOf(inked(i + 1)),
        reason: 'f$i was never touched — its bytes moved and its ref with '
            'them',
      );
    }
  });

  test('🚨the refs move BEFORE the bytes they left are written over — even '
      'when the session does not adopt the save', () async {
    // `adoptRefs: false` takes adoption out of the picture: whatever the
    // refs say afterwards, only the moves announced DURING the save can
    // have put there.
    final (path, store) = await openedOverAHole();
    // A rekeyed cel keeps pointing at the bytes of its OLD name, and this
    // save takes that name out of the directory — the push-down is free to
    // write over them. Its ref has to follow its picture to the entry this
    // save writes for its new key before that happens.
    store.rekeyFrames([(key('f0'), key('f9'))]);
    final before = File(path).lengthSync();

    await const AnicelFileService().save(
      project: createDefaultProject(),
      brushFrameStore: store,
      filePath: path,
      adoptRefs: false,
    );

    expect(
      File(path).lengthSync(),
      lessThan(before - 32 * 1024),
      reason: 'fixture: this save packed the file',
    );
    expect(
      pixelsOf(store.bakedSurfaceOrNull(key('f9'))),
      pixelsOf(inked(1)),
      reason: 'the rekeyed cel reads the picture it moved with',
    );
    for (var i = 1; i < 6; i += 1) {
      expect(
        pixelsOf(store.bakedSurfaceOrNull(key('f$i'))),
        pixelsOf(inked(i + 1)),
        reason: 'f$i',
      );
    }
  });
}
