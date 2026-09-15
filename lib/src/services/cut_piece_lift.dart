import 'dart:math' as math;
import 'dart:typed_data';

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
}) {
  final canvasSize = surface.canvasSize;
  final box = cutPieceBox(
    region,
    clip: (
      left: canvasSize.pasteboardLeft,
      top: canvasSize.pasteboardTop,
      rightExclusive: canvasSize.pasteboardRightExclusive,
      bottomExclusive: canvasSize.pasteboardBottomExclusive,
    ),
  );
  if (box == null) {
    return null;
  }
  final (:left, :top, :width, :height) = box;

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
    // ⚠️Nothing changes here either way: this mask comes from `maskFor` with
    // no soft options, so every byte is 0 or 255 and there is no partial
    // pixel to decide about. Set to match the move's law rather than left to
    // a default, because a default is where the next soft mask would land
    // silently.
    takeWholePixels: true,
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
      id: _nextCutPieceId(),
      width: width,
      height: height,
      rgba: gathered.rgba,
    ),
    originLeft: left,
    originTop: top,
  );
}

/// The id a NEW piece's pixels go by — minted here, where a piece is made,
/// and nowhere else.
///
/// 🚨F-112 (유저 2026-09-12: 「뷰어 패널에서 잘라내기툴로 pdf 그림
/// 잘라냈는데, 스탬프로 바로 안바뀌는 버그. 간헐적임 … 툴설정의 프리뷰에는
/// 잘라내기 전, 이전 기록의 그림이 있음」). The id is the PIXELS' identity to
/// both of its readers: the stamp arms only on a fresh one
/// (`armStampOnFreshCut`) and the settings preview decodes again only on a
/// new one (`CutPieceImageHost`). It used to be minted by whoever called — a
/// counter per State, one in the canvas and one in each viewer — and a State
/// that remounts counted from 1 again, so a NEW piece arrived under an OLD id:
/// no stamp, and the old picture in the preview. Intermittent, because only a
/// remount repeats. Until F-103 a neighbour panel opening or closing
/// remounted the viewer; a panel taken down and put back still makes a new
/// State.
///
/// ⛔Unique for the whole run, and across runs: the clock stamp is taken once
/// per launch, as the other stamps' ids are clock-stamped (`fill-…`,
/// `lift-…`), and the counter never restarts inside a run. The counter is
/// what keeps two cuts apart within one clock tick — a clock alone would
/// repeat the id for two quick cuts, which is this bug again.
String _nextCutPieceId() => 'cut-$_cutPieceRun-${_cutPieceSequence += 1}';

final String _cutPieceRun = '${DateTime.now().microsecondsSinceEpoch}';
var _cutPieceSequence = 0;

/// The pixel box a cut over [region] reads: the outline's coverage, inside
/// the half-open clip — null when the two do not meet.
///
/// Coverage, not the tight fold: the piece's box has to hold every pixel
/// a step could have added, and the mask zeroes what a 삭제 removed.
({int left, int top, int width, int height})? cutPieceBox(
  CanvasSelectionRegion region, {
  required ({int left, int top, int rightExclusive, int bottomExclusive}) clip,
}) {
  final bounds = region.coverageBounds;
  final left = math.max(clip.left, bounds.left.floor());
  final top = math.max(clip.top, bounds.top.floor());
  final rightExclusive = math.min(
    clip.rightExclusive,
    bounds.right.ceil() + 1,
  );
  final bottomExclusive = math.min(
    clip.bottomExclusive,
    bounds.bottom.ceil() + 1,
  );
  if (rightExclusive <= left || bottomExclusive <= top) {
    return null;
  }
  return (
    left: left,
    top: top,
    width: rightExclusive - left,
    height: bottomExclusive - top,
  );
}

/// The CUT verb over a picture that is not a cel — a page in the media
/// viewer (I-14, 유저 2026-09-11: 「뷰어패널의 잘라내기툴 사용 가능하도록.
/// 원본크기로 잘라냄. 그걸 캔버스에 배치하는용도」).
///
/// [region] is in the picture's own pixels, and [readRgba] hands back the
/// straight RGBA of the box [cutPieceBox] chose, at that size — so the piece
/// holds the SOURCE's pixels, whatever zoom the drag was made at. The laws
/// are [buildCutPiece]'s: a hard mask, no blank piece for an empty drag
/// (the slot outlives frames, cuts and projects), and its id minted here.
///
/// The origin is the box's place on the PICTURE, which is what paste at
/// origin reads: a reference the canvas's size lands where it was.
Future<CutPiece?> buildCutPieceFromPicture({
  required CanvasSelectionRegion region,
  required ({int width, int height}) picture,
  required Future<Uint8List> Function(
    ({int left, int top, int width, int height}) box,
  )
  readRgba,
}) async {
  final box = cutPieceBox(
    region,
    clip: (
      left: 0,
      top: 0,
      rightExclusive: picture.width,
      bottomExclusive: picture.height,
    ),
  );
  if (box == null) {
    return null;
  }
  final mask = region.maskFor(
    left: box.left,
    top: box.top,
    width: box.width,
    height: box.height,
  );
  final rgba = await readRgba(box);
  if (rgba.length != mask.length * 4) {
    throw StateError(
      'a ${box.width}x${box.height} read came back ${rgba.length} bytes',
    );
  }
  var liftedAnything = false;
  for (var pixel = 0; pixel < mask.length; pixel += 1) {
    final offset = pixel * 4;
    // Outside the outline, or nothing there: a zero pixel, as the cel's
    // gather leaves where it takes nothing.
    if (mask[pixel] == 0 || rgba[offset + 3] == 0) {
      rgba.fillRange(offset, offset + 4, 0);
    } else {
      liftedAnything = true;
    }
  }
  if (!liftedAnything) {
    return null;
  }
  return CutPiece(
    image: BrushStampImage(
      id: _nextCutPieceId(),
      width: box.width,
      height: box.height,
      rgba: rgba,
    ),
    originLeft: box.left,
    originTop: box.top,
  );
}
