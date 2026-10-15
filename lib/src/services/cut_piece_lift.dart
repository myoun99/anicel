import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/brush_frame_key.dart';
import '../models/brush_stamp_image.dart';
import '../models/cut_piece.dart';
import '../models/dirty_region.dart';
import 'brush_frame_editing_coordinator.dart';
import 'cache_invalidation_executor.dart';
import 'canvas_selection.dart';
import 'canvas_selection_region.dart';
import 'command.dart';
import 'commands/brush_lift_move_history_command.dart';

/// What a cut READ off a cel: the piece, and the lift it was packed from —
/// what [cutPixelsTaken] takes off the cel when the cut is to take them.
typedef CutRead = ({CutPiece piece, SelectionPixels lifted});

/// Reads the pixels under [region] out of [surface] and packs them into a
/// [CutPiece], the lift kept beside it ([CutRead]). Returns null when the
/// outline covers nothing paintable.
///
/// This is the CUT verb, and it differs from the selection MOVE lift next
/// door in exactly one way that matters: it produces only the piece, never
/// the erase that would remove the source. 유저 확정: "잘라내기는 원본 남기는
/// 복사" — the cut tool copies, and nothing about it can be routed into a
/// path that also deletes.
/// ↩️I-90 (유저 2026-10-10) asked for a cut that DOES take what it cuts —
/// 「원본 삭제」 on the cut tool, 「픽셀 잘라내기」 in 색 편집. It is still not
/// in here: the read stays a read, and the taking is a step of its own,
/// asked for by name ([cutPixelsTaken]).
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
///
/// [options] is the softness of a USER'S SELECTION, and only ever that. The
/// pixel copy (I-55) reads through the marquee the user drew, and a pixel
/// verb follows that marquee's 확장·페더·AA (유저 2026-09-09,
/// pixel-verbs-mask-options: 「선택의 aa 따르게」) — the same reading the
/// move's lift gives it. ⛔The cut tool's own outline and a whole picture
/// pass nothing: the hard edge above is their law, not a default.
CutRead? readCutPiece({
  required CanvasSelectionRegion region,
  required BitmapSurface surface,
  SelectionMaskOptions options = SelectionMaskOptions.none,
}) {
  // The MOVE's lift, the same steps: whole pixels unless a feather asked
  // for a soft edge — with no options every mask byte is 0 or 255 and there
  // is nothing to decide.
  final lifted = liftSelectionPixels(
    region: region,
    surface: surface,
    options: options,
  );
  // Scraping an empty stretch of cel must NOT hand back a blank piece: the
  // slot is a long-term holder that survives frames, cuts and projects, and
  // overwriting it with nothing would make one stray drag the only way to
  // lose work you meant to keep.
  if (lifted == null) {
    return null;
  }
  final box = lifted.box;
  return (
    piece: CutPiece(
      image: BrushStampImage(
        id: _nextCutPieceId(),
        width: box.width,
        height: box.height,
        rgba: lifted.rgba,
      ),
      originLeft: box.left,
      originTop: box.top,
    ),
    lifted: lifted,
  );
}

/// The step that takes what [read] cut off [key]'s cel, as one undo — the
/// move's erase ([selectionEraseDab]): a pixel the piece took whole leaves
/// whole, so nothing it took stays behind in part.
///
/// 🗣️I-90 (유저 2026-10-10): 「잘라내기시 해당 그림 없애는것」 · 「원본대상
/// 삭제하고 복사한단느낌. 진짜 단어 그대로 잘라내기」 — the cut tool's
/// 「원본 삭제」 and 색 편집's 「픽셀 잘라내기」 both take through here.
Command cutPixelsTaken({
  required BrushFrameEditingCoordinator coordinator,
  required BrushFrameKey key,
  required CutRead read,
  CacheInvalidationSink? cacheInvalidationSink,
}) => BrushLiftMoveHistoryCommand(
  coordinator: coordinator,
  frameKey: key,
  preLiftSurface: coordinator.currentSurfaceOf(key),
  landingDabs: [
    selectionEraseDab(read.lifted, id: 'cut-erase-${read.piece.image.id}'),
  ],
  description: 'Cut pixels',
  // Without a sink the canvas keeps the old composite until you leave the
  // frame — the pixels change and every cache serves what it had.
  cacheInvalidationSink: cacheInvalidationSink,
);

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

/// The CUT verb over a picture that is not a cel — a page in the media
/// viewer (I-14, 유저 2026-09-11: 「뷰어패널의 잘라내기툴 사용 가능하도록.
/// 원본크기로 잘라냄. 그걸 캔버스에 배치하는용도」).
///
/// [region] is in the picture's own pixels, and [readRgba] hands back the
/// straight RGBA of the box the region chose
/// ([CanvasSelectionRegion.pixelBoxWithin]), at that size — so the piece
/// holds the SOURCE's pixels, whatever zoom the drag was made at. The laws
/// are [readCutPiece]'s: a hard mask, no blank piece for an empty drag
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
  final box = region.pixelBoxWithin(
    DirtyRegion(
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
