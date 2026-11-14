import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// [ops] — a frame grid tile's op stream — drawn by the engine's tile pass
/// over clear into a tile [width] × [height]: the tile's pixels, straight
/// RGBA8, as the store's tiles keep theirs ([GpuGridPicture.read]).
Uint8List gridTileDrawn(int width, int height, Int32List ops) {
  final picture = _batch.picture(width, height);
  try {
    _batch.draw(picture, ops);
    return picture.read();
  } finally {
    picture.free();
  }
}

/// One batch for the test file: it compiles its pipeline once a format.
final GpuGridBatch _batch = GpuGridBatch(appGpuEngine);
