import 'dart:math' as math;
import 'dart:typed_data';

import 'brush_stamp_image.dart';

/// A piece lifted by the CUT tool, plus how the stamp tool is currently
/// posing it.
///
/// The piece itself is a colour-preserving RGBA rectangle — the same
/// primitive selection MOVE lifts with ([BrushStampImage]) — because a cut
/// piece has to stamp back the artwork it came from, not a silhouette in
/// the current colour. Coverage-only pieces are what a registered brush TIP
/// is ([BrushTipMask]); registering is a separate, explicit act.
///
/// The pose ([flipHorizontal], [flipVertical], [scalePercent]) lives here
/// rather than being baked into [image] so that:
/// - the original bytes survive every pose change (undo of a stamp cannot
///   restore a piece that was destructively rewritten), and
/// - flipping stays a byte re-order, which keeps [BrushStampImage]'s
///   "1:1, no resampling, byte-exact round trip" contract intact.
///
/// 유저 확정 (2026-08-12): the cut tool copies — it never removes the source
/// pixels — and the piece it holds outlives the tool, the frame, the cut and
/// even the PROJECT ("다른 프로젝트에 붙여넣고 싶을 수 있으니"). Only quitting
/// the app loses it. That is why nothing here points at project-owned state:
/// it is a raw pixel copy and a few numbers.
class CutPiece {
  CutPiece({
    required this.image,
    required this.originLeft,
    required this.originTop,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.scalePercent = 100,
  }) {
    if (scalePercent < minScalePercent || scalePercent > maxScalePercent) {
      throw ArgumentError.value(
        scalePercent,
        'scalePercent',
        'CutPiece.scalePercent must be within '
            '$minScalePercent..$maxScalePercent.',
      );
    }
  }

  /// 100% is the piece at the size it was cut. The floor is not 0 because a
  /// zero-sized stamp is not a small stamp, it is a no-op that looks like a
  /// broken tool.
  static const int minScalePercent = 1;

  /// Every one of Photoshop, Clip Studio and TVPaint caps stamp scaling, so
  /// "unbounded" is nobody's precedent — and the memory cost here is real
  /// (the piece is resampled at commit time).
  static const int maxScalePercent = 1000;

  /// The lifted pixels, straight-alpha RGBA, exactly as they sat in the cel.
  final BrushStampImage image;

  /// Where the piece came from, in CEL coordinates.
  ///
  /// 유저 확정: "원래 위치는 진짜 소스의 위치. 즉 셀좌표". This is the anchor
  /// "paste above/below" uses, and it is deliberately NOT screen space — the
  /// layer may be posed by a transform track, and the copy read raw cel
  /// pixels ("트랜스폼이나 이런 거 반영 안 한 진짜 순수 픽셀"), so the write
  /// has to land in the same space the read came from.
  final int originLeft;
  final int originTop;

  final bool flipHorizontal;
  final bool flipVertical;

  /// Percent of the original size. 100 = as cut.
  ///
  /// Percent rather than pixels because the number has to mean the same
  /// thing for every piece: with pixels, "original" is 300 for one piece and
  /// 40 for the next, so the user would have to remember it. This value is
  /// also deliberately NOT the top strip's brush-size slider — sharing it
  /// would multiply the piece by whatever pen width was last used, which is
  /// the same failure the fixed 100% opacity avoids, one field over.
  final int scalePercent;

  bool get isPosed =>
      flipHorizontal || flipVertical || scalePercent != defaultScalePercent;

  static const int defaultScalePercent = 100;

  /// The stamped size in canvas pixels, never smaller than one pixel a side.
  int get stampWidth =>
      math.max(1, (image.width * scalePercent / 100).round());
  int get stampHeight =>
      math.max(1, (image.height * scalePercent / 100).round());

  CutPiece copyWith({
    bool? flipHorizontal,
    bool? flipVertical,
    int? scalePercent,
  }) {
    return CutPiece(
      image: image,
      originLeft: originLeft,
      originTop: originTop,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      scalePercent: scalePercent ?? this.scalePercent,
    );
  }

  /// Drops the pose without touching the pixels — what the Reset button
  /// does. Size and both flips go back at once, which is why there is no
  /// separate "original size" button: the two knobs the panel offers are
  /// exactly the two this clears.
  CutPiece reset() => CutPiece(
    image: image,
    originLeft: originLeft,
    originTop: originTop,
  );

  /// The piece's bytes with the flips applied, at the ORIGINAL resolution.
  ///
  /// Flipping is a row/column re-order, so it costs one copy and no
  /// resampling — the scale is applied later, by the stamp path, so that a
  /// flipped piece at 100% is still byte-exact with the source.
  BrushStampImage flippedImage() {
    if (!flipHorizontal && !flipVertical) {
      return image;
    }
    final width = image.width;
    final height = image.height;
    final source = image.rgba;
    final out = Uint8List(source.length);
    for (var y = 0; y < height; y += 1) {
      final sourceY = flipVertical ? height - 1 - y : y;
      final destRow = y * width * 4;
      final sourceRow = sourceY * width * 4;
      for (var x = 0; x < width; x += 1) {
        final sourceX = flipHorizontal ? width - 1 - x : x;
        final dest = destRow + x * 4;
        final from = sourceRow + sourceX * 4;
        out[dest] = source[from];
        out[dest + 1] = source[from + 1];
        out[dest + 2] = source[from + 2];
        out[dest + 3] = source[from + 3];
      }
    }
    return BrushStampImage(
      id: '${image.id}-flip'
          '${flipHorizontal ? 'h' : ''}${flipVertical ? 'v' : ''}',
      width: width,
      height: height,
      rgba: out,
    );
  }
}
