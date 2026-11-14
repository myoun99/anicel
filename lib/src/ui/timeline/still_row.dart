import 'package:flutter/widgets.dart';

import '../widgets/still_raster.dart';

/// A row of the timeline's dock as a STILL REGION of its own — the frame
/// cells and the rail's controls alike, on both grids ([StillRaster]): a
/// scroll moves the row's image, and a row whose content changes is drawn
/// live in that frame alone.
///
/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q1 (유저 2026-11-07: 「스크롤하는
/// 동안에도 행은 그림으로」). The dock is one image only while it stands
/// still, so every frame of a scroll drew every row it shows. 🔬S5_BA cut
/// 352 on the main PC: a live dock frame was 7.8 ms of raster, and 3.9 with
/// each row drawn from an image of itself (11-06, a ceiling). The price the
/// user took with it: an image's edges are not bit for bit the live ones
/// (about 1/255), the rows turn into their images one snapshot a frame
/// (1.6–2.0 ms each on Windows), and the images of the rows built are held.
///
/// ⚠️The row's CONTENT, not what hangs past it: a region clips to its box,
/// and a row drag's caret and its badge stand across the row's boundary
/// ([layerRowDragWrapper] wraps them around this).
Widget stillRow(Widget content) =>
    StillRaster(debugLabel: 'row', child: content);
