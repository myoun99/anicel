import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_tip_shape.dart';
import '../models/canvas_point.dart';
import '../models/cut_piece.dart';
import 'canvas_selection.dart';
import 'resample/resample_kernel.dart';

/// One stamp of [piece], centred on [center], at [opacity].
///
/// 유저 확정 (2026-08-12): the piece does NOT inherit the brush — no
/// pressure, and every other dynamic at its default ("브러시마다 고르면
/// 다르지 않나? … 필압 없고. 다른 것들도 초기값으로").
///
/// 🚨The funnel's default is the opposite: a stamp dab ignores the tip and
/// texture fields but still MULTIPLIES by [BrushDab.opacity]. Hand it the
/// live BRUSH state and the 40% left over from shading rides along, and
/// there is no way to see why the stamp came out faint.
///
/// ⚠️**TP1/TP3 (2026-08-15) retired the hard-coded 100%.** That constant was
/// never the goal — it was the only way to block that leak while one opacity
/// field served every tool, which is exactly what 유저's reasoning said. The
/// stamp has a field of its own now
/// ([BrushToolState.cutStampOpacity]), so the leak cannot happen and the
/// tool can have the setting it was denied: *"잘라내기의 스탬프는 불투명도
/// 쓸수있게하고싶어."* The DEFAULT is still 100% — callers that mean "put it
/// back exactly" simply do not pass one.
///
/// ⚠️So the byte-exactness contract narrows: "what was held is what lands"
/// holds AT 100%. Below it the funnel multiplies, which is the whole point
/// of the setting.
///
/// The click point is the piece's CENTRE (Clip Studio and TVPaint both
/// anchor there, and TVPaint makes it configurable — which is a later
/// slice, not a different default).
BrushDab buildCutStampDab({
  required CutPiece piece,
  required CanvasPoint center,
  double opacity = 1.0,
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
    opacity: opacity,
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
