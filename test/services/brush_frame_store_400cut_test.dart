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
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';

/// R22-C verdict lab (400-cut scenario): a TV-scale project — 400 HD
/// cels — must full-save fast, open at archive speed (zero pixel decode,
/// every cel FILE-BACKED with near-zero RAM), and above all INCREMENTAL-
/// save in time proportional to the EDIT, not the project. Prints
/// measured wall times; assertions pin the architecture, not the clock.
///
/// NOT tagged `benchmark`, deliberately. The tag means "this file's POINT
/// is the number, so racing the suite for CPU makes it lie" — and it
/// skips the whole file, assertions included. Every assertion below is a
/// count, a byte total or an emptiness check, none of which the clock can
/// move, and together they are the only place the incremental-save
/// architecture is pinned end to end. Tagging this file by its NAME once
/// took all eleven of them out of CI while the numbers it prints stayed
/// harmless. The printed times are indicative here; read them from a
/// deliberate lone run, not from a suite log.
void main() {
  test(
    '400 HD cels: full save, file-backed open, one-cel incremental save',
    () async {
      const cels = 400;
      const canvasSize = CanvasSize(width: 1920, height: 1080);
      final directory = await Directory.systemTemp.createTemp('qa-400cut');
      addTearDown(() => directory.delete(recursive: true));

      BrushFrameKey key(int i) => BrushFrameKey(
        projectId: const ProjectId('p'),
        trackId: const TrackId('t'),
        cutId: CutId('cut-${i ~/ 4}'),
        layerId: const LayerId('l'),
        frameId: FrameId('f$i'),
      );

      // One inked 256px tile per cel (sparse line art — the realistic cel).
      BitmapSurface inked(int seed) {
        final pixels = Uint8List(256 * 256 * 4);
        for (var i = 0; i < 4096; i += 1) {
          final at = ((i * 97 + seed) % (256 * 256)) * 4;
          pixels[at] = 20;
          pixels[at + 3] = 255;
        }
        return BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 256,
          tiles: {
            TileCoord(x: 2, y: 2): BitmapTile(
              coord: TileCoord(x: 2, y: 2),
              size: 256,
              pixels: pixels,
            ),
          },
        );
      }

      final encodeWatch = Stopwatch()..start();
      final blobs = <BrushFrameKey, AnicelCelBlob>{
        for (var i = 0; i < cels; i += 1)
          key(i): AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key(i), inked(i))),
      };
      encodeWatch.stop();
      var blobBytes = 0;
      for (final blob in blobs.values) {
        blobBytes += blob.bytes.length;
      }

      // COLD LANDING (store side): must be near-instant, zero decode.
      final store = BrushFrameStore();
      final landWatch = Stopwatch()..start();
      store.restoreBaked(blobs);
      landWatch.stop();
      expect(store.coldCelKeys.length, cels);
      expect(store.hotBakedBytes, 0, reason: 'no pixel decode on landing');

      // FULL SAVE: cold blobs pass through byte-identically; afterwards
      // every cel is FILE-BACKED (the .anicel is the disk tier) and the RAM
      // blobs are gone.
      final path = '${directory.path}/tv400.anicel';
      final project = createDefaultProject();
      final saveWatch = Stopwatch()..start();
      await const AnicelFileService().save(
        project: project,
        brushFrameStore: store,
        filePath: path,
      );
      saveWatch.stop();
      final fileBytes = await File(path).length();
      expect(store.fileCelKeys.length, cels);
      expect(store.coldBakedBytes, 0, reason: 'refs replace the RAM blobs');

      // INCREMENTAL SAVE: edit ONE cel — the save must append that cel
      // (+ project.json), not rewrite 400.
      store.storeBakedSurface(key(3), inked(9999));
      expect(store.dirtyCelKeysSinceSave.length, 1);
      final incrementalWatch = Stopwatch()..start();
      await const AnicelFileService().save(
        project: project,
        brushFrameStore: store,
        filePath: path,
      );
      incrementalWatch.stop();
      final incrementalBytes = await File(path).length();
      expect(store.dirtyCelKeysSinceSave, isEmpty);
      expect(
        incrementalBytes - fileBytes,
        lessThan(blobBytes ~/ 10),
        reason:
            'the append is one cel + project.json + directory, nowhere '
            'near a rewrite of 400 cels',
      );

      // OPEN: central-directory walk + per-cel header reads — cels come
      // back file-backed, still zero pixel decode.
      final openWatch = Stopwatch()..start();
      final result = await const AnicelFileService().open(filePath: path);
      openWatch.stop();
      expect(result.cels.length, cels);

      final store2 = BrushFrameStore()..restoreFromFile(result.cels);
      expect(store2.hotBakedBytes, 0);
      expect(store2.coldBakedBytes, 0, reason: 'open holds refs, not bytes');

      // First-access materialization stays per-cel cheap and reads the
      // EDITED pixels for the incrementally saved cel.
      final touchWatch = Stopwatch()..start();
      final surface = store2.bakedSurfaceOrNull(key(3))!;
      touchWatch.stop();
      expect(
        surface.tiles[TileCoord(x: 2, y: 2)]!.pixels,
        inked(9999).tiles[TileCoord(x: 2, y: 2)]!.pixels,
        reason: 'the shadowing entry is the one that opens',
      );

      // ignore: avoid_print
      print(
        'LAB400: cels=$cels encode=${encodeWatch.elapsedMilliseconds}ms '
        'blobBytes=${(blobBytes / 1024).round()}KB '
        'coldLand=${landWatch.elapsedMilliseconds}ms '
        'fullSave=${saveWatch.elapsedMilliseconds}ms '
        'file=${(fileBytes / 1024).round()}KB '
        'incrementalSave=${incrementalWatch.elapsedMilliseconds}ms '
        'open=${openWatch.elapsedMilliseconds}ms '
        'firstTouch=${touchWatch.elapsedMicroseconds}us',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
