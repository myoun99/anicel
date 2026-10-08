import 'dart:ui';

/// How [content] fits a slot [slot] large without distorting it: how many
/// of the slot's units a unit of the content takes, and which side of the
/// slot it FILLS — the width, or else the height.
///
/// 🚨THE ONE CONTAIN (유저 2026-10-05, F-294: 「통일할거는 법 통일해줘」).
/// [containRect] lays a stamp, a picture and the cut envelope's form by it
/// (`CutEnvelopeLayout.fit`), and a sheet's paper is measured round its form
/// by it (`SheetPaper.around`). ↩️The envelope's layout wrote the same
/// comparison out for itself, in aspect ratios.
///
/// The side the content fills is TOLD, not multiplied back out of the
/// scale: `width * (slot / width)` comes back a rounding short of the slot
/// as often as not, and that is a margin nobody asked for.
///
/// [content] must have area — a caller with none answers for itself
/// ([containRect]).
({double scale, bool fillsWidth}) containFit(Size content, Size slot) {
  final widthScale = slot.width / content.width;
  final heightScale = slot.height / content.height;
  final fillsWidth = widthScale <= heightScale;
  return (scale: fillsWidth ? widthScale : heightScale, fillsWidth: fillsWidth);
}

/// Fits [content] inside [slot] without distorting it — a stamp is a
/// stamp, not a stretched one.
///
/// ⚠️Aspect ratio is PRESERVED (`BoxFit.contain`) — 정본: 「늘어난 도장은
/// 도장이 아니다」. The staff stamp cell that first wrote the decision out
/// left the sheet window when the staff became names only (`22596a562`),
/// so this is where it lives now; the envelope stamp, the conte page
/// picture and the conte PDF picture all draw through it.
///
/// The result is centred in [slot] on both axes. A slot with no area is
/// the caller's question, not this one's: it answers with an empty rect at
/// the slot's own origin.
Rect containRect(Size content, Rect slot) {
  if (content.width <= 0 || content.height <= 0) {
    return Rect.fromLTWH(slot.left, slot.top, 0, 0);
  }
  final (:scale, :fillsWidth) = containFit(content, slot.size);
  final width = fillsWidth ? slot.width : content.width * scale;
  final height = fillsWidth ? content.height * scale : slot.height;
  return Rect.fromLTWH(
    slot.left + (slot.width - width) / 2,
    slot.top + (slot.height - height) / 2,
    width,
    height,
  );
}
