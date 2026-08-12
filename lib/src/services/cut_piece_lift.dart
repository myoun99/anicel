import 'dart:math' as math;

import '../models/bitmap_surface.dart';
import '../models/brush_stamp_image.dart';
import '../models/cut_piece.dart';
import '../models/pasteboard_bounds.dart';
import 'canvas_selection.dart';
import 'canvas_selection_region.dart';

/// Reads the pixels under [region] out of [surface] and packs them into a
/// [CutPiece]. Returns null when the outline covers nothing paintable.
///
/// This is the CUT verb, and it differs from the selection MOVE lift next
/// door in exactly one way that matters: it produces only the piece, never
/// the erase that would remove the source. 유저 확정: "잘라내기는 원본 남기는
/// 복사" — the cut tool copies, and nothing about it can be routed into a
/// path that also deletes.
///
/// The mask is HARD-EDGED on purpose, and not merely by inheriting a
/// default. Japanese line art is two-value, and a soft edge writes the
/// mid-alpha pixels that break the fill pass downstream; this app has no
/// two-value layer flag to switch that behaviour off with, so the safe
/// value is the only value. It also keeps the piece byte-identical to the
/// cel it came from, which is what makes "paste back at the original
/// position" reproduce the source exactly.
///
/// The clip is the PASTEBOARD, not the canvas: artwork that overshoots the
/// frame is real artwork, and an animator draws limbs past the edge daily.
CutPiece? buildCutPiece({
  required CanvasSelectionRegion region,
  required BitmapSurface surface,
  required String pieceId,
}) {
  final canvasSize = surface.canvasSize;
  final bounds = region.bounds;
  final left = math.max(canvasSize.pasteboardLeft, bounds.left.floor());
  final top = math.max(canvasSize.pasteboardTop, bounds.top.floor());
  final rightExclusive = math.min(
    canvasSize.pasteboardRightExclusive,
    bounds.right.ceil() + 1,
  );
  final bottomExclusive = math.min(
    canvasSize.pasteboardBottomExclusive,
    bounds.bottom.ceil() + 1,
  );
  if (rightExclusive <= left || bottomExclusive <= top) {
    return null;
  }
  final width = rightExclusive - left;
  final height = bottomExclusive - top;

  final mask = region.maskFor(
    left: left,
    top: top,
    width: width,
    height: height,
  );
  final gathered = gatherMaskedSurfacePixels(
    surface: surface,
    mask: mask,
    left: left,
    top: top,
    width: width,
    height: height,
  );
  // Scraping an empty stretch of cel must NOT hand back a blank piece: the
  // slot is a long-term holder that survives frames, cuts and projects, and
  // overwriting it with nothing would make one stray drag the only way to
  // lose work you meant to keep.
  if (!gathered.liftedAnything) {
    return null;
  }

  return CutPiece(
    image: BrushStampImage(
      id: pieceId,
      width: width,
      height: height,
      rgba: gathered.rgba,
    ),
    originLeft: left,
    originTop: top,
  );
}
