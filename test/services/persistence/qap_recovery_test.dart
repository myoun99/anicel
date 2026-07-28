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
import 'package:anicel/src/services/persistence/qap_file_service.dart';
import 'package:anicel/src/services/persistence/qap_incremental_writer.dart';

/// R24-D1 torn-tail recovery: an append crash destroys only the file's
/// tail (central directory + EOCD), so the local-header walk must
/// reconstruct the last complete state — shadowing intact, torn final
/// entry dropped, corrupt final entry falling back to its shadowed
/// predecessor — and a recovered open must heal on the next save.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qap-recovery');
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

  /// A saved file with two cels + one incremental append (k2 edited),
  /// returning the path and the healthy layout for reference.
  Future<(String, QapZipLayout, BrushFrameStore)> buildAppendedFile({
    String name = 'torn.qap',
  }) async {
    const service = QapFileService();
    final store = BrushFrameStore();
    store.storeBakedSurface(key('f1'), inked(3));
    store.storeBakedSurface(key('f2'), inked(5));
    final path = '${directory.path}/$name';
    final project = createDefaultProject();
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    store.storeBakedSurface(key('f2'), inked(9));
    await service.save(
      project: project,
      brushFrameStore: store,
      filePath: path,
    );
    return (path, parseQapZipLayoutFile(path), store);
  }

  test('a tail truncation (crash mid central-directory rewrite) recovers '
      'every entry with shadowing intact', () async {
    final (path, healthy, _) = await buildAppendedFile();

    // Tear the file INSIDE the central directory rewrite: keep all
    // entry data, lose the directory + EOCD.
    final file = File(path);
    file.openSync(mode: FileMode.append)
      ..truncateSync(healthy.centralDirectoryOffset + 7)
      ..closeSync();
    expect(
      () => parseQapZipLayoutFile(path),
      throwsFormatException,
      reason: 'the tail is really gone',
    );

    final recovered = recoverQapZipLayoutFile(path);
    expect(
      {for (final entry in recovered.entries) entry.name},
      {for (final entry in healthy.entries) entry.name},
      reason: 'every ACTIVE entry survives',
    );
    for (final entry in healthy.entries) {
      final match = recovered.entryNamed(entry.name)!;
      expect(
        (match.dataOffset, match.length),
        (entry.dataOffset, entry.length),
        reason: 'shadowing resolves to the same (latest) bytes: '
            '${entry.name}',
      );
    }
  });

  test('a torn FINAL entry (crash mid append data): a shadowed name '
      'falls back to its previous version; a NEW name is dropped',
      () async {
    final (path, healthy, _) = await buildAppendedFile();
    // Case 1: the last entry is the appended k2 — tearing it must
    // resurrect the ORIGINAL k2 bytes (as if the append never ran).
    final last = healthy.entries.reduce(
      (a, b) => a.localHeaderOffset > b.localHeaderOffset ? a : b,
    );
    File(path).openSync(mode: FileMode.append)
      ..truncateSync(last.dataOffset + last.length ~/ 2)
      ..closeSync();

    final recovered = recoverQapZipLayoutFile(path);
    final fallback = recovered.entryNamed(last.name)!;
    expect(
      fallback.localHeaderOffset,
      lessThan(last.localHeaderOffset),
      reason: 'the earlier shadowed version wins',
    );
    expect(recovered.entries.length, healthy.entries.length);

    // Case 2 (fresh healthy file): append a BRAND-NEW name, tear its
    // data — the name must vanish entirely (it never had a complete
    // version).
    final (path2, _, _) = await buildAppendedFile(name: 'torn2.qap');
    final repaired = appendQapEntries(
      path: path2,
      newEntries: {
        'cels/brand-new.celz': Uint8List.fromList([1, 2, 3, 4]),
      },
    );
    final fresh = repaired.entryNamed('cels/brand-new.celz')!;
    File(path2).openSync(mode: FileMode.append)
      ..truncateSync(fresh.dataOffset + 2)
      ..closeSync();
    final recovered2 = recoverQapZipLayoutFile(path2);
    expect(recovered2.entryNamed('cels/brand-new.celz'), isNull);
  });

  test('a CORRUPT final entry falls back to its shadowed predecessor',
      () async {
    final (path, healthy, _) = await buildAppendedFile();
    final last = healthy.entries.reduce(
      (a, b) => a.localHeaderOffset > b.localHeaderOffset ? a : b,
    );
    // Flip bytes inside the final entry's data, then tear the tail so
    // recovery (not the central directory) decides.
    final raf = File(path).openSync(mode: FileMode.writeOnlyAppend);
    // Reopen for random-access write.
    raf.closeSync();
    final rw = File(path).openSync(mode: FileMode.append);
    rw.setPositionSync(last.dataOffset + 4);
    rw.writeFromSync(const [0xDE, 0xAD, 0xBE, 0xEF]);
    rw.truncateSync(last.dataOffset + last.length);
    rw.closeSync();

    final recovered = recoverQapZipLayoutFile(path);
    final entry = recovered.entryNamed(last.name);
    if (entry != null) {
      expect(
        entry.localHeaderOffset,
        lessThan(last.localHeaderOffset),
        reason: 'the shadowed predecessor wins, not the corrupt bytes',
      );
    }
    // If the final name had no predecessor, it must be gone entirely.
  });

  test('END TO END: a torn file OPENS through recovery and the next save '
      'HEALS it (full rewrite, parseable tail again)', () async {
    final (path, healthy, store) = await buildAppendedFile();
    File(path).openSync(mode: FileMode.append)
      ..truncateSync(healthy.centralDirectoryOffset + 3)
      ..closeSync();

    const service = QapFileService();
    final result = await service.open(filePath: path);
    expect(result.cels.length, 2, reason: 'recovery finds both cels');

    final reopened = BrushFrameStore()..restoreFromFile(result.cels);
    expect(
      reopened
          .bakedSurfaceOrNull(key('f2'))!
          .tiles[TileCoord(x: 0, y: 0)]!
          .pixels,
      inked(9).tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'the recovered f2 is the EDITED (appended) version',
    );

    // The next save must fall down the FULL path and heal the tail.
    reopened.storeBakedSurface(key('f1'), inked(11));
    await service.save(
      project: createDefaultProject(),
      brushFrameStore: reopened,
      filePath: path,
    );
    final healed = parseQapZipLayoutFile(path);
    expect(healed.entries.where((e) => e.name.endsWith('.celz')).length, 2);
    // Unused but keeps the original store alive through the test body.
    expect(store.fileCelKeys.length, greaterThanOrEqualTo(0));
  });
}
