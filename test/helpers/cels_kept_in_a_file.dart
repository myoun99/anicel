import 'dart:io';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

import 'project_scratch_folder.dart';

/// [cels] kept in [store] as an opened project keeps them: each a stretch of
/// a saved file, cold until it is read ([BrushFrameStore.restoreFromFile]).
/// Answers where each is kept.
Map<BrushFrameKey, AnicelCelFileRef> keepInAFile(
  BrushFrameStore store,
  Map<BrushFrameKey, BitmapSurface> cels,
) {
  final directory = Directory.systemTemp.createTempSync('qa-kept-cels');
  deleteAfterSessionEnds(directory);
  final refs = <BrushFrameKey, AnicelCelFileRef>{};
  for (final (index, MapEntry(:key, value: surface)) in cels.entries.indexed) {
    final blob = AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, surface));
    final path = '${directory.path}/cel$index.bin';
    File(path).writeAsBytesSync(blob.bytes);
    refs[key] = AnicelCelFileRef(
      filePath: path,
      dataOffset: 0,
      length: blob.bytes.length,
      canvasSize: surface.canvasSize,
      tileSize: blob.tileSize,
      photoPaths: const [],
    );
  }
  store.restoreFromFile(refs);
  return refs;
}
