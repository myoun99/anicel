import 'dart:ui' show Size;

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
  TimelineGridTilePicture(this.picture, {Size? drawn})
    : drawn =
          drawn ?? Size(picture.width.toDouble(), picture.height.toDouble()) {
    _live += 1;
  }

  final GpuGridPicture picture;
  int _holds = 1;

  int get width => picture.width;
  int get height => picture.height;

  /// What of [picture] was drawn on, in its pixels from its top left: the
  /// cells' own extent at the ratio they were drawn at, which its whole
  /// pixels round up — all of it where nothing says less.
  ///
  /// 🔬F-604 (유저 2026-11-16 「엣지랑 블록이랑 안맞는 문제는 행 off로하면
  /// 또 이번엔 왼쪽아래 엣지가 밖으로 나간다거나」): a row 28 across at a
  /// ratio of 0.9 is 25.2 device pixels, its tile 26, and the whole 26 was
  /// laid onto the 25.2 — the paper's foot rose ¾ of a pixel above where its
  /// grip, drawn where it stands, ends. A tile is laid one of its pixels to
  /// a device pixel, as the wave band lays its band: this, onto the cells.
  final Size drawn;

  /// How many hold it: 0 once it is freed.
  @visibleForTesting
  int get debugHolds => _holds;

  /// How many are not freed yet — a tile the store drew and then dropped
  /// on its way, which nothing hands back to hold, among them.
  /// ⛔Read it around an operation, never as an absolute
  /// (`PremultipliedTileUpload.debugLiveCount`'s rule).
  @visibleForTesting
  static int get debugLive => _live;
  static int _live = 0;

  void hold() {
    assert(_holds > 0, 'a tile held after it was freed');
    _holds += 1;
  }

  void letGo() {
    assert(_holds > 0, 'a tile let go of after it was freed');
    _holds -= 1;
    if (_holds == 0) {
      _live -= 1;
      picture.free();
    }
  }
}
