import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../models/rgba_image_bytes.dart';

/// One GPU image of a picture, and the canvas-space rect it covers.
typedef ImagePiece = ({ui.Image image, ui.Rect worldRect});

/// Whether [image] drawn into [worldRect] lands texel for texel on a canvas
/// whose pixels are [texelScale] canvas units apart: one texel per target
/// pixel, starting on a whole pixel — the draw that resamples nothing.
bool landsTexelForTexel(
  ui.Image image,
  ui.Rect worldRect,
  double texelScale,
) {
  bool whole(double value) => value == value.roundToDouble();
  return image.width == worldRect.width * texelScale &&
      image.height == worldRect.height * texelScale &&
      whole(worldRect.left * texelScale) &&
      whole(worldRect.top * texelScale);
}

/// 🚨★★★A PICTURE LONGER ON A SIDE THAN THE ENGINE HOLDS IS HELD IN PIECES
/// (🗣️유저 2026-10-21, board a-cel-past-the-device-side-composes-smaller-Q1:
/// 「나눠 든다」 — playback and export show the file's pixels as they are).
///
/// A GPU image is no longer on a side than this device's engine holds
/// (`pictureSideLimit`), and one asked longer comes back SHRUNK to fit.
/// 🔬Measured on the Surface Pro 11 (Impeller GLES, 2026-10-20), a cel of
/// 20096×1152 composed as one image came back 16384×939 — drawn into its
/// rect at 0.815 of its resolution in every film frame exported and every
/// frame played at full quality. So a compose past the side is made as
/// pieces inside it, side by side ([piecesOver]); every holder holds them
/// all, and the one draw lays the part a draw can see into one image
/// (`drawPosedLayerImage`). A picture inside the side is ONE piece — the
/// image it always was, byte for byte.
///
/// [over] — a rect on whole canvas pixels whose image is [texelsPerUnit]
/// texels a canvas pixel — as the rects a compose of it makes one image
/// each: [over] itself where that image is no longer than [side] on either
/// side, and otherwise the cells of a grid from [over]'s corner, each the
/// longest power of two texels inside [side] across (the last of a row or a
/// column what is left), row by row.
///
/// ★A POWER OF TWO, so every level of the display's pyramid halves a piece
/// as it halves the whole: each 2×2 block lies inside one piece, and a
/// piece's inner edges are even — halved by one texture draw, as a tile is
/// (`drawHalvings`).
List<ui.Rect> piecesOver(
  ui.Rect over, {
  required int side,
  double texelsPerUnit = 1,
}) {
  if (over.width * texelsPerUnit <= side &&
      over.height * texelsPerUnit <= side) {
    return [over];
  }
  var texels = 1;
  while (texels * 2 <= side) {
    texels *= 2;
  }
  final step = texels / texelsPerUnit;
  return [
    for (var top = over.top; top < over.bottom; top += step)
      for (var left = over.left; left < over.right; left += step)
        ui.Rect.fromLTRB(
          left,
          top,
          math.min(left + step, over.right),
          math.min(top + step, over.bottom),
        ),
  ];
}

/// What every holder of a picture's pieces does with them.
extension ImagePieces on List<ImagePiece> {
  /// The rect the pieces cover together.
  ui.Rect get worldRect =>
      map((piece) => piece.worldRect).reduce((a, b) => a.expandToInclude(b));

  /// What the pieces weigh resident, together.
  int get estimatedBytes => fold(
    0,
    (sum, piece) =>
        sum + estimatedImageBytes(piece.image.width, piece.image.height),
  );

  /// A handle of its own on every piece — the pixels shared.
  List<ImagePiece> clones() => [
    for (final piece in this)
      (image: piece.image.clone(), worldRect: piece.worldRect),
  ];

  /// Lets every piece's handle go.
  void disposeAll() {
    for (final piece in this) {
      piece.image.dispose();
    }
  }
}
