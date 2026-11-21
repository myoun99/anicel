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
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cels_parked_cold.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨A cel that lives in the run's room alone — an imported cel, parked as
/// it lands, no pixel of it in the RAM — is the picture it was once saved
/// and opened again, and the save writes its park's bytes into the archive
/// as they are: the room's bytes are the archive's own form, pressed
/// already (관제 2026-11-21 09:41 on card
/// cel-originals-are-held-twice-in-ram-and-on-the-gpu, ① and ③ — no pin
/// held this road).
///
/// ⚠️The bytes cannot tell a write-through from a press again: the press is
/// the same and lands the same bytes. That the save does not read a cel
/// with a park back and press it is the snapshot's to say — it hands such a
/// cel over as its park alone (test/services/
/// a_cel_made_hot_keeps_its_park_test.dart, 'not as a hot cel to press
/// again').
void main() {
  const canvasSize = CanvasSize(
    width: defaultCelTileSize,
    height: defaultCelTileSize,
  );
  final origin = TileCoord(x: 0, y: 0);

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  /// A cel of one tile, drawn on: not of one colour, so its bytes weigh.
  Uint8List pixelsOf(int seed) {
    final pixels = Uint8List(BitmapTile.bytesFor(defaultCelTileSize));
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = (seed * 20 + i ~/ 4) % 251;
      pixels[i + 3] = 255;
    }
    return pixels;
  }

  BitmapSurface ink(int seed) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: defaultCelTileSize,
    tiles: {
      origin: BitmapTile(size: defaultCelTileSize, pixels: pixelsOf(seed)),
    },
  );

  test('🚨a parked cel, saved and opened again, is its picture — its '
      "park's bytes in the archive as they are", () async {
    final store = BrushFrameStore();
    final parked = key('parked');
    parkCold(store, {parked: ink(3)});
    expect(store.hotBakedSurfaceOrNull(parked), isNull, reason: '⛔premise');
    // Read now: once saved, a cel is kept by the file, and its park goes.
    final parkBytes = File(
      store.bakedSnapshotForSave().cold[parked]!.filePath,
    ).readAsBytesSync();
    final folder = Directory.systemTemp.createTempSync('parked-saved');
    deleteAfterSessionEnds(folder);
    final path = '${folder.path}/parked.anicel';

    await const AnicelFileService().save(
      project: createDefaultProject(),
      brushFrameStore: store,
      filePath: path,
    );

    final layout = readAnicelZipLayoutFile(path);
    final archive = File(path).readAsBytesSync();
    final entry = layout.entryNamed(anicelCelEntryName(parked))!;
    expect(
      archive.sublist(entry.dataOffset, entry.dataOffset + entry.length),
      parkBytes,
    );
    final opened = await const AnicelFileService().open(filePath: path);
    final reopened = BrushFrameStore()..restoreFromFile(opened.cels);
    expect(
      reopened
          .bakedSurfaceOrNull(parked)!
          .tiles[origin]!
          .readPixels((_, pixels) => Uint8List.fromList(pixels)),
      pixelsOf(3),
    );
  });
}
