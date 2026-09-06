import 'dart:typed_data';

import '../core/gray_downscale.dart';
import '../models/brush_tip_mask.dart';
import '../models/cut_piece.dart';

/// Turns a held cut piece into a brush tip mask.
///
/// 🚨**Coverage comes from ALPHA, not brightness** — and that is the one
/// place this deliberately parts company with Photoshop and with our own
/// image-import codec.
///
/// Photoshop's rule when you Define Brush Preset is that black is opaque
/// and white is transparent, which is right when the source is an opaque
/// scan of ink on paper. Our source is the opposite: a transparent-
/// background animation cel. Apply the brightness rule to one of those and
/// a bright drawing — a white highlight, a pale fill — reads as "nearly
/// transparent" and all but disappears; in Photoshop a bright piece on
/// transparency is refused outright as an empty selection. The silhouette
/// is what the animator drew, so the silhouette is the coverage.
///
/// The library's own shape rules still apply: square, and no longer than
/// [maxBrushTipMaskSide] on a side.
BrushTipMask cutPieceToTipMask(CutPiece piece, {required String id}) {
  // The POSE is honoured here, unlike paste-at-origin: registering says
  // "this shape, the way I have it set up", and a flipped or resized piece
  // is what the user is looking at when they press the button.
  final source = piece.flippedImage();
  final width = source.width;
  final height = source.height;

  final coverage = Uint8List(width * height);
  for (var index = 0; index < coverage.length; index += 1) {
    coverage[index] = source.rgba[index * 4 + 3];
  }

  // Square, content centred — the mask contract.
  return brushTipMaskFromCoverage(
    coverage,
    size: (width: width, height: height),
    id: id,
    downscale: areaAveragedGray,
  );
}
