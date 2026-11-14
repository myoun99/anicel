import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// [ops] — a frame grid tile's op stream — drawn by the engine's tile pass
/// over clear into a tile [width] × [height], its letters read from
/// [atlas]: the tile's pixels, straight RGBA8, as the store's tiles keep
/// theirs ([GpuGridPicture.read]).
Uint8List gridTileDrawn(
  int width,
  int height,
  Int32List ops, {
  GpuGridAtlas? atlas,
}) {
  final picture = GpuGridPicture(appGpuEngine, width, height);
  try {
    _grid.draw(picture, ops, atlas: atlas);
    return picture.read();
  } finally {
    picture.free();
  }
}

/// One pass for the test file: it compiles its pipeline once a format.
final GpuGrid _grid = GpuGrid(appGpuEngine);
