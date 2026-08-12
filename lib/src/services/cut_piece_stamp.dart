import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_tip_shape.dart';
import '../models/canvas_point.dart';
import '../models/cut_piece.dart';
import 'canvas_selection.dart';
import 'resample/resample_kernel.dart';

/// One stamp of [piece], centred on [center].
///
/// 유저 확정 (2026-08-12): the piece does NOT inherit the brush. Opacity is
/// locked at 100%, there is no pressure, and every other dynamic sits at
/// its default — "브러시마다 고르면 다르지 않나? 그러니 100%로 함. 필압 없고.
/// 다른 것들도 초기값으로."
///
/// 🚨That has to be written down rather than left alone, because the stroke
/// funnel's default is the opposite: a stamp dab ignores the tip and
/// texture fields but still MULTIPLIES by [BrushDab.opacity]. Hand it the
/// live brush state and the 40% multiply left over from shading quietly
/// rides along, and the user would have no way to see why the stamp came
/// out faint.
///
/// The click point is the piece's CENTRE (Clip Studio and TVPaint both
/// anchor there, and TVPaint makes it configurable — which is a later
/// slice, not a different default).
BrushDab buildCutStampDab({
  required CutPiece piece,
  required CanvasPoint center,
  ResampleMode resampleMode = ResampleMode.pick,
}) {
  // Flip first: it is a byte re-order, so at 100% a flipped stamp is still
  // byte-exact with the cel it came from.
  final image = piece.flippedImage();
  final dab = BrushDab(
    center: center,
    // Ignored for a stamp dab (the pixels carry their own colour), but the
    // field is required and black is the neutral thing to say.
    color: 0xFF000000,
    size: math.max(image.width, image.height).toDouble(),
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
    stamp: image,
  );
  if (piece.scalePercent == CutPiece.defaultScalePercent) {
    return dab;
  }
  final scale = piece.scalePercent / 100;
  return transformStampDab(
    dab,
    SelectionAffine(pivot: center, sx: scale, sy: scale),
    // Pick (area argmax), not the smoothing tent: Blend produces new
    // colours by design, and on a two-value drawing those new colours are
    // the mid-alpha edge pixels that break the fill pass downstream. Same
    // reason the cut mask is hard-edged.
    mode: resampleMode,
  );
}

/// A stamp of [piece] back at the coordinates it was cut from.
///
/// Deliberately UNPOSED — original size, no flip — even when the stamp
/// tile is currently posing the piece. "Original position" and "original
/// picture" are one idea: a paste that landed at the source coordinates
/// but at 80% and mirrored would not reproduce anything. Photoshop draws
/// the same line, where clipboard pastes are always 1:1 and only a
/// registered brush tip scales.
///
/// The coordinates are CEL coordinates, which is what makes this land back
/// on the artwork rather than on the screen: the read was raw cel pixels,
/// so the write has to be in the same space, and a layer posed by a
/// transform track cannot pull the two apart.
BrushDab buildCutPasteDab(CutPiece piece) {
  final image = piece.image;
  return BrushDab(
    center: CanvasPoint(
      x: piece.originLeft + image.width / 2,
      y: piece.originTop + image.height / 2,
    ),
    color: 0xFF000000,
    size: math.max(image.width, image.height).toDouble(),
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
    stamp: image,
  );
}

/// The centres a drag lays stamps on, from [from] to [to].
///
/// Spacing is one whole piece — stamps touch and do not overlap. The user
/// took the spacing knob OUT of the held piece on purpose ("스페이싱 같은 거
/// 없애고"), so this is a law rather than a default, and non-overlap is the
/// choice that keeps a soft edge from accumulating where stamps stack.
List<CanvasPoint> cutStampCentersAlong({
  required CutPiece piece,
  required CanvasPoint from,
  required CanvasPoint to,
}) {
  final spacing = math
      .max(piece.stampWidth, piece.stampHeight)
      .toDouble();
  final dx = to.x - from.x;
  final dy = to.y - from.y;
  final distance = math.sqrt(dx * dx + dy * dy);
  if (distance < spacing) {
    return const [];
  }
  final steps = distance ~/ spacing;
  return [
    for (var step = 1; step <= steps; step += 1)
      CanvasPoint(
        x: from.x + dx * (step * spacing / distance),
        y: from.y + dy * (step * spacing / distance),
      ),
  ];
}
