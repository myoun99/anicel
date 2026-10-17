import 'dart:io';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

import 'cels_parked_cold.dart';
import 'project_scratch_folder.dart';

/// [cels] kept in [store] as an opened project keeps them: each a stretch of
/// a saved file, cold until it is read ([BrushFrameStore.restoreFromFile]).
/// Answers where each is kept.
///
/// ★Each ref is the one the open path reads off the cel's head — its size,
/// its tiles and its photo index ([AnicelCelBlob.photoPaths]) — so a test
/// keeps a cel the way a project keeps it, photos named and all
/// (`test/architecture/a_test_keeps_a_cel_through_one_helper_test.dart`).
Map<BrushFrameKey, AnicelCelFileRef> keepInAFile(
  BrushFrameStore store,
  Map<BrushFrameKey, BitmapSurface> cels,
) {
  final directory = Directory.systemTemp.createTempSync('qa-kept-cels');
  deleteAfterSessionEnds(directory);
  final refs = <BrushFrameKey, AnicelCelFileRef>{};
  for (final (index, MapEntry(:key, value: surface)) in cels.entries.indexed) {
    final blob = coldBlobOf(key, surface);
    final path = '${directory.path}/cel$index.bin';
    File(path).writeAsBytesSync(blob.bytes);
    refs[key] = AnicelCelFileRef(
      filePath: path,
      dataOffset: 0,
      length: blob.bytes.length,
      canvasSize: blob.canvasSize,
      tileSize: blob.tileSize,
      photoPaths: blob.photoPaths,
    );
  }
  store.restoreFromFile(refs);
  return refs;
}
