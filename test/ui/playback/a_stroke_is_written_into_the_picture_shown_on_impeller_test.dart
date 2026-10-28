@Tags(['gpu'])
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';

import '../../helpers/a_stroke_written_into_the_picture_shown.dart';

/// 🚨A stroke's step written into the picture the canvas shows
/// ([aStrokeIsWrittenIntoThePictureShown]) as Impeller shows it, where the
/// picture's chain and the frame drawn as it stands were apart (F-465, 유저
/// 2026-10-25: 「50%에서는 매번」, and on Windows the same night: 「10%에서
/// 발생하는거 확인 … 소수점배율에서 발생할거같아서」). The tester's Skia reads
/// the nearest level alone, on these views straight over its texels, and
/// cuts a pixel an edge crosses by its centre.
///
/// Impeller reads a chain zoomed out BETWEEN two levels, a texel past the
/// one the pixel lies over, and covers a pixel an edge crosses by what
/// falls on each side of it. On line art, under a stroke laid over it, at
/// a view whose edge cuts the page off the levels' grid, zoomed to 12.5%,
/// and at scales whose pixels the levels' grid does not land on — 10%,
/// 125% and 150%, and every view on a 1.25 and a 1.5 screen.
///
/// And on a page of 270 rows under line art of no period, which no level
/// averages flat, where the picture's levels stretch over the rows its page
/// does not fill; under opaque line art of no period at 20% and 10%, the
/// page cut by the view beside the step and not; turned by 30° at 33%; and
/// with a stroke at the page's corner at 20% and 15%.
///
/// ↩️Until the step was written into every level at once (F-465, 유저 채팅
/// 2026-10-26), it was drawn over the picture while it landed — as the
/// frame stood under a clip, then as its own patch — and these were the
/// scenes the two drew apart at: 🔬a step cut at its patch up to 12/255,
/// the frame as it stood off the levels' grid 8, a patch laid for 37.5%
/// shown at 18.75% 2, an edge between the picture and the step off the
/// screen's pixels 8, a patch reading its own edge again where the picture
/// holds what lies past it 8, the page's corner 9 and 13 (Impeller tester,
/// 2026-10-25 · 10-26).
///
/// 🔬Each pixel to within 1/255 a channel: the tester's Vulkan halves an
/// image cut where a patch is and the picture it is cut from a level apart
/// by one where line art changes under them (measured 2026-10-25 — one
/// pixel at 25% and 12.5%, 0 on one ink), and a turned view within 2/255
/// (measured 2026-10-26 — a pixel here and there inside the page at 33%,
/// as it is on master).
void main() {
  aStrokeIsWrittenIntoThePictureShown(
    views: {
      'at 50%': CanvasViewport(zoom: 0.5, panX: 8, panY: 4),
      'at 25%': CanvasViewport(zoom: 0.25, panX: 8, panY: 4),
      'at 25%, cut by the view': CanvasViewport(
        zoom: 0.25,
        panX: -1,
        panY: -1,
      ),
      'at 125%': CanvasViewport(zoom: 1.25, panX: 8, panY: 4),
      'at 150%': CanvasViewport(zoom: 1.5, panX: 8, panY: 4),
      'at 12.5%': CanvasViewport(zoom: 0.125, panX: 8, panY: 4),
      'at 125%, flipped': CanvasViewport(
        zoom: 1.25,
        panX: 8,
        panY: 4,
        flipHorizontal: true,
      ),
    },
    ratios: const [1.0, 1.25, 1.5],
    inkAt: (x, y) => [0, (x * 5 + y * 3) % 8 * 16, 0, 0x80],
    strokeAt: const ui.Rect.fromLTRB(9, 9, 15, 15),
    apartBy: 1,
    withThePinsOfNoView: false,
    skip: !ui.ImageFilter.isShaderFilterSupported,
  );
  aStrokeIsWrittenIntoThePictureShown(
    views: {
      'on a page of 270 rows at 20%': CanvasViewport(
        zoom: 0.2,
        panX: 8,
        panY: 4,
      ),
      'on a page of 270 rows at 10%': CanvasViewport(
        zoom: 0.1,
        panX: 8,
        panY: 4,
      ),
      'on a page of 270 rows at 6%': CanvasViewport(
        zoom: 0.06,
        panX: 8,
        panY: 4,
      ),
      'on a page of 270 rows at 7%': CanvasViewport(
        zoom: 0.07,
        panX: 8,
        panY: 4,
      ),
      'on a page of 270 rows at 10%, cut by the view': CanvasViewport(
        zoom: 0.1,
        panX: -1,
        panY: -1,
      ),
    },
    ratios: const [1.0, 1.25],
    inkAt: (x, y) => [0, ((x * 73856093) ^ (y * 19349663)) & 0xF0, 0, 0x80],
    strokeAt: const ui.Rect.fromLTRB(201, 161, 207, 167),
    page: const CanvasSize(width: 320, height: 270),
    apartBy: 1,
    withThePinsOfNoView: false,
    skip: !ui.ImageFilter.isShaderFilterSupported,
  );
  aStrokeIsWrittenIntoThePictureShown(
    views: {
      'under opaque line art at 20%': CanvasViewport(
        zoom: 0.2,
        panX: 8,
        panY: 4,
      ),
      'under opaque line art at 10%': CanvasViewport(
        zoom: 0.1,
        panX: 8,
        panY: 4,
      ),
    },
    ratios: const [1.0],
    inkAt: (x, y) => [0, ((x * 73856093) ^ (y * 19349663)) & 0xFF, 0, 0xFF],
    strokeAt: const ui.Rect.fromLTRB(73, 57, 79, 63),
    page: const CanvasSize(width: 160, height: 128),
    apartBy: 1,
    withThePinsOfNoView: false,
    skip: !ui.ImageFilter.isShaderFilterSupported,
  );
  aStrokeIsWrittenIntoThePictureShown(
    views: {
      'under opaque line art at 20%, cut by the view': CanvasViewport(
        zoom: 0.2,
        panX: -3,
        panY: -3,
      ),
      'under opaque line art at 10%, cut by the view': CanvasViewport(
        zoom: 0.1,
        panX: -3,
        panY: -3,
      ),
    },
    ratios: const [1.0],
    inkAt: (x, y) => [0, ((x * 73856093) ^ (y * 19349663)) & 0xFF, 0, 0xFF],
    strokeAt: const ui.Rect.fromLTRB(41, 41, 47, 47),
    page: const CanvasSize(width: 160, height: 128),
    apartBy: 1,
    withThePinsOfNoView: false,
    skip: !ui.ImageFilter.isShaderFilterSupported,
  );
  aStrokeIsWrittenIntoThePictureShown(
    views: {
      'turned by 30° at 33%': CanvasViewport(
        zoom: 0.33,
        panX: 8,
        panY: 4,
        rotationDegrees: 30,
      ),
    },
    ratios: const [1.0, 1.25],
    inkAt: (x, y) => [0, ((x * 73856093) ^ (y * 19349663)) & 0xF0, 0, 0x80],
    strokeAt: const ui.Rect.fromLTRB(9, 9, 15, 15),
    page: const CanvasSize(width: 320, height: 256),
    apartBy: 2,
    withThePinsOfNoView: false,
    skip: !ui.ImageFilter.isShaderFilterSupported,
  );
  aStrokeIsWrittenIntoThePictureShown(
    views: {
      'at the page\'s corner at 20%': CanvasViewport(
        zoom: 0.2,
        panX: -14,
        panY: -14,
      ),
      'at the page\'s corner at 15%': CanvasViewport(
        zoom: 0.15,
        panX: -2,
        panY: -4,
      ),
    },
    ratios: const [1.0, 1.25],
    inkAt: (x, y) => [0, ((x * 73856093) ^ (y * 19349663)) & 0xFF, 0, 0xFF],
    strokeAt: const ui.Rect.fromLTRB(249, 249, 256, 256),
    page: const CanvasSize(width: 256, height: 256),
    apartBy: 1,
    withThePinsOfNoView: false,
    skip: !ui.ImageFilter.isShaderFilterSupported,
  );
}
