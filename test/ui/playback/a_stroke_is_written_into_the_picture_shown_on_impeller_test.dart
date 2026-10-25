@Tags(['impeller'])
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';

import '../../helpers/a_stroke_written_into_the_picture_shown.dart';

/// 🚨A stroke's step written into the picture the canvas shows
/// ([aStrokeIsWrittenIntoThePictureShown]) as Impeller reads a chain zoomed
/// out (F-465, 유저 2026-10-25: 「50%에서는 매번」): BETWEEN two levels,
/// a texel past the one the pixel lies over. The tester's Skia reads the
/// nearest level alone, on these views straight over its texels, and drew
/// a step cut at its patch, a buffer off the picture's grid and a patch
/// laid for a zoom left as one picture — so these run on the Impeller
/// tester (the `impeller` tag's batch) and skip on Skia.
///
/// On line art, under a stroke laid over it, at a view whose edge cuts the
/// page off the levels' grid, and zoomed from 50% to 12.5% with the step's
/// texels in and the picture's levels not yet.
///
/// 🔬Each pixel to within 1/255 a channel: the tester's Vulkan halves an
/// image cut where a patch is and the picture it is cut from a level apart
/// by one where line art changes under them (measured 2026-10-25 — one
/// pixel at 25% and 12.5%, 0 on one ink). A step cut at its patch was 4/255
/// off, a buffer off the grid 3, a patch laid for 50% shown at 12.5% 5.
void main() => aStrokeIsWrittenIntoThePictureShown(
  views: {
    'at 50%': CanvasViewport(zoom: 0.5, panX: 8, panY: 4),
    'at 25%': CanvasViewport(zoom: 0.25, panX: 8, panY: 4),
    'at 25%, cut by the view': CanvasViewport(zoom: 0.25, panX: -1, panY: -1),
  },
  ratios: const [1.0],
  thenAt: {'12.5%': CanvasViewport(zoom: 0.125, panX: 8, panY: 4)},
  inkAt: (x, y) => [0, (x * 5 + y * 3) % 8 * 16, 0, 0x80],
  strokeAt: const ui.Rect.fromLTRB(9, 9, 15, 15),
  apartBy: 1,
  withThePinsOfNoView: false,
  skip: !ui.ImageFilter.isShaderFilterSupported,
);
