import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

/// A frame grid's tile as the engine keeps it ([GpuGridPicture]), freed
/// once nothing holds it: the tile store that keeps it, and each row that
/// laid it on its grid's screen, till the row lays again
/// (timeline_grid_screen.dart).
///
/// 🚨A screen lays what its rows laid at every scroll, a row long after
/// the store let its tile go — and a picture freed under a screen is a
/// texture gone under the GPU. ↩️A tile was a `ui.Image`, which the
/// engine counted for every picture that drew it.
final class TimelineGridTilePicture {
  TimelineGridTilePicture(this.picture);

  final GpuGridPicture picture;
  int _holds = 1;

  int get width => picture.width;
  int get height => picture.height;

  /// How many hold it: 0 once it is freed.
  @visibleForTesting
  int get debugHolds => _holds;

  void hold() {
    assert(_holds > 0, 'a tile held after it was freed');
    _holds += 1;
  }

  void letGo() {
    assert(_holds > 0, 'a tile let go of after it was freed');
    _holds -= 1;
    if (_holds == 0) {
      picture.free();
    }
  }
}
